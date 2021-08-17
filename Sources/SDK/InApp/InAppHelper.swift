//
//  InAppHelper.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation
import CoreData

public enum InAppMessagePresentationResult : String {
    case PRESENTED = "presented"
    case EXPIRED = "expired"
    case FAILED = "failed"
}

typealias kumulos_applicationPerformFetchWithCompletionHandler = @convention(c) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void;
typealias fetchBlock = @convention(block) (_ obj:Any, _ application:UIApplication, _ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void;
private var ks_existingBackgroundFetchDelegate: IMP? = nil

internal class InAppHelper {
    
    private var presenter: InAppPresenter
    private var pendingTickleIds: NSMutableOrderedSet = NSMutableOrderedSet(capacity: 1)
    private var registered : Bool = false
    
    var messagesContext: NSManagedObjectContext? = nil;
    
    internal let MESSAGE_TYPE_IN_APP = 2
    
    private var syncBarrier: DispatchSemaphore
    private var syncQueue: DispatchQueue
    private let STORED_IN_APP_LIMIT = 50;
    
    // MARK: Initialization
    
    init() {
        presenter = InAppPresenter()
        syncBarrier = DispatchSemaphore(value: 0)
        syncQueue = DispatchQueue(label: "kumulos.in-app.sync")
    }
    
    func initialize() {
        initContext()
        handleEnrollmentAndSyncSetup()
    }
    
    func initContext() {
        
        let objectModel: NSManagedObjectModel? = getDataModel()
        
        if objectModel == nil {
            print("Failed to create object model")
            return
        }
        
        var storeCoordinator: NSPersistentStoreCoordinator? = nil
        if let objectModel = objectModel {
            storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: objectModel)
        }
        
        let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last
        let storeUrl = URL(string: "KSMessagesDb.sqlite", relativeTo: docsUrl)
        
        let options = [
            NSMigratePersistentStoresAutomaticallyOption: NSNumber(value: true),
            NSInferMappingModelAutomaticallyOption: NSNumber(value: true)
        ]
        
        do {
            try storeCoordinator?.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeUrl, options: options)
        } catch let err {
            print("Failed to set up persistent store: \(err)")
            return;
        }
        
        messagesContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        messagesContext!.performAndWait({
            messagesContext!.persistentStoreCoordinator = storeCoordinator
        })
    }
    
    @objc func appBecameActive() -> Void {
        presentImmediateAndNextOpenContent()
        
        let onComplete: ((Int) -> Void)? = { result in
            if result > 0 {
                self.presentImmediateAndNextOpenContent()
            }
        }
        
        #if DEBUG
        sync(onComplete)
        #else
        let lastSyncTime = UserDefaults.standard.object(forKey: KumulosUserDefaultsKey.MESSAGES_LAST_SYNC_TIME.rawValue) as? Date
        if lastSyncTime != nil && lastSyncTime!.timeIntervalSinceNow < -3600 as Double {
            sync(onComplete)
        }
        #endif
    }
    
    let setupSyncTask:Void = {
        let klass : AnyClass = type(of: UIApplication.shared.delegate!)
        
        // Perform background fetch
        let performFetchSelector = #selector(UIApplicationDelegate.application(_:performFetchWithCompletionHandler:))
        let fetchType = NSString(string: "v@:@@?").utf8String
        let block : fetchBlock = { (obj:Any, application:UIApplication, completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void in
            var fetchResult : UIBackgroundFetchResult = .noData
            let fetchBarrier = DispatchSemaphore(value: 0)
            
            if let _ = ks_existingBackgroundFetchDelegate {
                unsafeBitCast(ks_existingBackgroundFetchDelegate, to: kumulos_applicationPerformFetchWithCompletionHandler.self)(obj, performFetchSelector, application, { (result : UIBackgroundFetchResult) in
                    fetchResult = result
                    fetchBarrier.signal()
                })
            } else {
                fetchBarrier.signal()
            }
            
            if (Kumulos.sharedInstance.inAppHelper.inAppEnabled()){
                Kumulos.sharedInstance.inAppHelper.sync { (result:Int) in
                    _ = fetchBarrier.wait(timeout: DispatchTime.now() + DispatchTimeInterval.seconds(20))
                    
                    if result < 0 {
                        fetchResult = .failed
                    } else if result > 0 {
                        fetchResult = .newData
                    }
                    // No data case is default, allow override from other handler
                    completionHandler(fetchResult)
                }
            }
            else{
                completionHandler(fetchResult)
            }
        }
        let kumulosPerformFetch = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
        
        ks_existingBackgroundFetchDelegate = class_replaceMethod(klass, performFetchSelector, kumulosPerformFetch, fetchType)
    }()
    
    // MARK: State helpers
    func inAppEnabled() -> Bool {
        return Kumulos.sharedInstance.inAppConsentStrategy != InAppConsentStrategy.NotEnabled && userConsented();
    }
    
    func userConsented() -> Bool {
        return UserDefaults.standard.bool(forKey: KumulosUserDefaultsKey.IN_APP_CONSENTED.rawValue)
    }
    
    func updateUserConsent(consentGiven: Bool) {
        let props: [String: Any] = ["consented":consentGiven]
        
        Kumulos.trackEventImmediately(eventType: KumulosEvent.IN_APP_CONSENT_CHANGED.rawValue, properties: props)
        
        if (consentGiven) {
            UserDefaults.standard.set(consentGiven, forKey: KumulosUserDefaultsKey.IN_APP_CONSENTED.rawValue)
            handleEnrollmentAndSyncSetup()
        }
        else {
            DispatchQueue.global(qos: .default).async(execute: {
                self.resetMessagingState()
            })
        }
    }
    
    func handleAssociatedUserChange() -> Void {
        if (Kumulos.sharedInstance.inAppConsentStrategy == InAppConsentStrategy.NotEnabled) {
            DispatchQueue.global(qos: .default).async(execute: {
                self.updateUserConsent(consentGiven: false)
            })
            return
        }
        
        DispatchQueue.global(qos: .default).async(execute: {
            self.resetMessagingState()
            self.handleEnrollmentAndSyncSetup()
        })
    }
    
    private func handleEnrollmentAndSyncSetup() -> Void {
        if (Kumulos.sharedInstance.inAppConsentStrategy == InAppConsentStrategy.AutoEnroll && userConsented() == false) {
            updateUserConsent(consentGiven: true)
            return;
        }
        else if (Kumulos.sharedInstance.inAppConsentStrategy == InAppConsentStrategy.NotEnabled && userConsented() == true) {
            updateUserConsent(consentGiven: false)
            return;
        }
        
        if (!inAppEnabled()) {
            return;
        }
        
        if registered == true {
            return
        }
        
        registered = true
        
        _ = setupSyncTask
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        DispatchQueue.main.async(execute: {
            if UIApplication.shared.applicationState == .background {
                return
            }
            
            let onComplete: ((Int) -> Void)? = { result in
                if result > 0 {
                    self.presentImmediateAndNextOpenContent()
                }
            }
            
            self.sync(onComplete)
            
        })
    }
    
    private func resetMessagingState() -> Void {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        UserDefaults.standard.removeObject(forKey: KumulosUserDefaultsKey.IN_APP_CONSENTED.rawValue)
        UserDefaults.standard.removeObject(forKey: KumulosUserDefaultsKey.MESSAGES_LAST_SYNC_TIME.rawValue)
        
        messagesContext!.performAndWait({
            let context = self.messagesContext
            let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
            fetchRequest.includesPendingChanges = true
            
            var messages: [InAppMessageEntity];
            do {
                messages = try context?.fetch(fetchRequest) as! [InAppMessageEntity]
            } catch {
                return
            }
            
            for message in messages {
                context?.delete(message)
            }
            
            do {
                try context?.save()
            } catch let err {
                print("Failed to clean up messages: \(err)")
            }
        })
    }
    
    // MARK: Message management
    func sync(_ onComplete: ((_ result: Int) -> Void)? = nil) {
        syncQueue.async(execute: {
            let lastSyncTime = UserDefaults.standard.object(forKey: KumulosUserDefaultsKey.MESSAGES_LAST_SYNC_TIME.rawValue) as? NSDate
            var after = ""
            
            if lastSyncTime != nil {
                let formatter = DateFormatter()
                formatter.timeStyle = .full
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                formatter.timeZone = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
                formatter.locale = Locale(identifier: "en_US_POSIX")
                if let lastSyncTime = lastSyncTime {
                    after = "?after=\(KSHttpUtil.urlEncode(formatter.string(from: lastSyncTime as Date))!)" ;
                }
            }
            
            let encodedIdentifier = KSHttpUtil.urlEncode(KumulosHelper.currentUserIdentifier)
            let path = "/v1/users/\(encodedIdentifier!)/messages\(after)"
            
            Kumulos.sharedInstance.pushHttpClient.sendRequest(.GET, toPath: path, data: nil, onSuccess: { response, decodedBody in
                let messagesToPersist = decodedBody as? [[AnyHashable : Any]]
                if (messagesToPersist == nil || messagesToPersist!.count == 0) {
                    if onComplete != nil {
                        onComplete?(0)
                    }
                    
                    self.syncBarrier.signal()
                    return
                }
                
                self.persistInAppMessages(messages: messagesToPersist!)
                
                if onComplete != nil {
                    onComplete?(1)
                }
                
                DispatchQueue.main.async(execute: {
                    if UIApplication.shared.applicationState != .active {
                        return
                    }
                    
                    DispatchQueue.global(qos: .default).async(execute: {
                        let messagesToPresent = self.getMessagesToPresent([InAppPresented.IMMEDIATELY.rawValue])
                        self.presenter.queueMessagesForPresentation(messages: messagesToPresent, tickleIds: self.pendingTickleIds)
                    })
                })
                
                self.syncBarrier.signal()
                
            }, onFailure: { response, error, data in
                if onComplete != nil {
                    onComplete?(-1)
                }
                
                self.syncBarrier.signal()
            })
        })
        _ = syncBarrier.wait(timeout: DispatchTime.now() + DispatchTimeInterval.seconds(20))
    }
    
    private func persistInAppMessages(messages: [[AnyHashable : Any]]) {
        messagesContext!.performAndWait({
            let context = self.messagesContext!
            let entity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Message", in: context)
            
            if entity == nil {
                print("Failed to get entity description for Message, aborting!")
                return
            }
            
            var lastSyncTime = NSDate(timeIntervalSince1970: 0)
            let dateParser = DateFormatter()
            dateParser.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            dateParser.locale = Locale(identifier: "en_US_POSIX")
            dateParser.timeZone = TimeZone(secondsFromGMT: 0)
            
            var fetchedWithInbox = false
            for message in messages {
                let partId = message["id"] as! Int64
                
                let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
                fetchRequest.entity = entity
                let predicate: NSPredicate = NSPredicate(format: "id = %i", partId)
                fetchRequest.predicate = predicate
                
                var fetchedObjects: [InAppMessageEntity];
                do {
                    fetchedObjects = try context.fetch(fetchRequest) as! [InAppMessageEntity]
                } catch {
                    continue;
                }
                
                // Upsert
                let model: InAppMessageEntity = fetchedObjects.count == 1 ? fetchedObjects[0] : InAppMessageEntity(entity: entity!, insertInto: context)
                
                model.id = partId
                model.updatedAt = dateParser.date(from: message["updatedAt"] as! String)! as NSDate
                if (model.dismissedAt == nil){
                    model.dismissedAt =  dateParser.date(from: message["openedAt"] as? String ?? "") as NSDate?
                }
                model.presentedWhen = message["presentedWhen"] as! String
                
                if (model.readAt == nil){
                    model.readAt =  dateParser.date(from: message["readAt"] as? String ?? "") as NSDate?
                }
                
                if (model.sentAt == nil){
                    model.sentAt =  dateParser.date(from: message["sentAt"] as? String ?? "") as NSDate?
                }
                
                model.content = message["content"] as! NSDictionary
                model.data = message["data"] as? NSDictionary
                model.badgeConfig = message["badge"] as? NSDictionary
                model.inboxConfig = message["inbox"] as? NSDictionary
                
                if (model.inboxConfig != nil){
                    //crude way to refresh when new inbox, updated readAt, updated inbox title/subtite
                    //may cause redundant refreshes (if message with inbox updated, but not inbox itself).
                    fetchedWithInbox = true
                    
                    let inbox = model.inboxConfig!
                    
                    model.inboxFrom = dateParser.date(from: inbox["from"] as? String ?? "") as NSDate?
                    model.inboxTo = dateParser.date(from: inbox["to"] as? String ?? "") as NSDate?
                }
                
                let inboxDeletedAt = message["inboxDeletedAt"] as? String
                if (inboxDeletedAt != nil){
                    model.inboxConfig = nil;
                    model.inboxFrom = nil;
                    model.inboxTo = nil;
                    if (model.dismissedAt == nil){
                        model.dismissedAt = dateParser.date(from: inboxDeletedAt!) as NSDate?
                    }
                }
                
                model.expiresAt = dateParser.date(from: message["expiresAt"] as? String ?? "") as NSDate?
                
                if (model.updatedAt.timeIntervalSince1970 > lastSyncTime.timeIntervalSince1970) {
                    lastSyncTime = model.updatedAt
                }
            }
            
            // Evict
            var (idsEvicted, evictedWithInbox) = evictMessages(context: context)
            
            do{
                try context.save()
            }
            catch let err {
                print("Failed to persist messages: \(err)")
                return
            }
            
            //exceeders evicted after saving because fetchOffset is ignored when have unsaved changes
            //https://stackoverflow.com/questions/10725252/possible-issue-with-fetchlimit-and-fetchoffset-in-a-core-data-query
            let (exceederIdsEvicted, evictedExceedersWithInbox) = evictMessagesExceedingLimit(context: context)
            if (exceederIdsEvicted.count > 0){
                idsEvicted += exceederIdsEvicted
                
                do{
                    try context.save()
                }
                catch let err {
                    print("Failed to evict exceeding messages: \(err)")
                    return
                }
            }
            
            for idEvicted in idsEvicted {
                removeNotificationTickle(id: idEvicted)
            }
            
            UserDefaults.standard.set(lastSyncTime, forKey: KumulosUserDefaultsKey.MESSAGES_LAST_SYNC_TIME.rawValue)
            
            trackMessageDelivery(messages: messages)
            
            let inboxUpdated = fetchedWithInbox || evictedWithInbox || evictedExceedersWithInbox
            KumulosInApp.maybeRunInboxUpdatedHandler(inboxNeedsUpdate: inboxUpdated)
        })
    }
    
    private func removeNotificationTickle(id: Int64) -> Void {
        if (pendingTickleIds.contains(id)){
            pendingTickleIds.remove(id)
        }
        
        if #available(iOS 10, *) {
            let tickleNotificationId = "k-in-app-message:\(id)"
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [tickleNotificationId])
            PendingNotificationHelper.remove(identifier: tickleNotificationId)
        }
    }
    
    private func evictMessages(context: NSManagedObjectContext) -> ([Int64], Bool) {
        let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
        fetchRequest.includesPendingChanges = true
        
        let messageExpiredCondition = "(expiresAt != nil AND expiresAt <= %@)"
        
        let noInboxAndMessageDismissed = "(inboxConfig = nil AND dismissedAt != nil)"
        let noInboxAndMessageExpired = "(inboxConfig = nil AND "+messageExpiredCondition+")"
        let inboxExpiredAndMessageDismissedOrExpired = "(inboxTo != nil AND inboxTo < %@ AND (dismissedAt != nil OR "+messageExpiredCondition+"))"
        
        let predicate: NSPredicate? =
            NSPredicate(format: noInboxAndMessageDismissed+" OR "+noInboxAndMessageExpired+" OR "+inboxExpiredAndMessageDismissedOrExpired, NSDate(), NSDate(), NSDate())
        fetchRequest.predicate = predicate
        
        var toEvict: [InAppMessageEntity]
        do {
            toEvict = try context.fetch(fetchRequest) as! [InAppMessageEntity]
        } catch let err {
            print("Failed to evict messages: \(err)")
            return ([], false);
        }
        
        var idsEvicted: [Int64] = []
        var evictedInbox = false
        for messageToEvict in toEvict {
            idsEvicted.append(messageToEvict.id)
            if (messageToEvict.inboxConfig != nil){
                evictedInbox = true
            }
            context.delete(messageToEvict)
        }
        
        return (idsEvicted, evictedInbox)
    }
    
    private func evictMessagesExceedingLimit(context: NSManagedObjectContext) -> ([Int64], Bool) {
        let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "sentAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "id", ascending: false)
        ]
        fetchRequest.fetchOffset = STORED_IN_APP_LIMIT
        
        var toEvict: [InAppMessageEntity]
        do {
            toEvict = try context.fetch(fetchRequest) as! [InAppMessageEntity]
        } catch let err {
            print("Failed to evict exceeding messages: \(err)")
            return ([], false);
        }
        
        var idsEvicted: [Int64] = []
        var evictedInbox = false
        for messageToEvict in toEvict {
            idsEvicted.append(messageToEvict.id)
            if (messageToEvict.inboxConfig != nil){
                evictedInbox = true
            }
            context.delete(messageToEvict)
        }
        
        return (idsEvicted, evictedInbox)
    }
    
    private func getMessagesToPresent(_ presentedWhenOptions: [String]) -> [InAppMessage] {
        var messages: [InAppMessage] = []
        
        messagesContext!.performAndWait({
            let context = self.messagesContext!
            let entity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Message", in: context)
            
            let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
            fetchRequest.entity = entity
            fetchRequest.includesPendingChanges = false
            fetchRequest.returnsObjectsAsFaults = false
            
            let predicate = NSPredicate(format: "((presentedWhen IN %@) OR (id IN %@)) AND (dismissedAt = nil) AND (expiresAt = nil OR expiresAt > %@)", presentedWhenOptions, self.pendingTickleIds, NSDate())
            fetchRequest.predicate = predicate
            
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "sentAt", ascending: true),
                NSSortDescriptor(key: "updatedAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            
            var entities: [Any] = []
            do {
                entities = try context.fetch(fetchRequest)
            } catch let err {
                print("Failed to fetch: \(err)")
                return;
            }
            
            if (entities.isEmpty){
                return
            }
            
            messages = self.mapEntitiesToModels(entities: entities as! [InAppMessageEntity] )
        })
        
        return messages
    }
    
    internal func handleMessageOpened(message: InAppMessage) -> Void {
        var markedRead = false
        if (message.readAt == nil){
            markedRead = markInboxItemRead(withId: message.id, shouldWait: false);
        }
       
        if (message.inboxConfig != nil){
            KumulosInApp.maybeRunInboxUpdatedHandler(inboxNeedsUpdate: markedRead);
        }
        
        let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":message.id]
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_OPENED, properties: props)
    }
    
    internal func markMessageDismissed(message: InAppMessage) -> Void {
        
        let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":message.id]
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_DISMISSED, properties: props)
        
        if (pendingTickleIds.contains(message.id)){
            pendingTickleIds.remove(message.id)
        }
        
        messagesContext!.performAndWait({
            let context = self.messagesContext!
            let entity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Message", in: context)
            
            let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
            fetchRequest.entity = entity
            fetchRequest.includesPendingChanges = false
            fetchRequest.predicate = NSPredicate(format: "id = %i", message.id)
            
            var messageEntities: [InAppMessageEntity]
            do {
                messageEntities = try context.fetch(fetchRequest) as! [InAppMessageEntity]
            } catch let err {
                print("Failed to evict messages: \(err)")
                return;
            }
            
            if (messageEntities.count == 1){
                messageEntities[0].dismissedAt = NSDate()
                if (messageEntities[0].readAt == nil){
                    messageEntities[0].readAt = NSDate()
                }
            }
            
            do{
                try context.save()
            }
            catch let err {
                print("Failed to update message: \(err)")
                return
            }
            
        });
    }
    
    private func trackMessageDelivery(messages: [[AnyHashable : Any]]) -> Void {
        for message in messages {
            let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":message["id"] as! Int]
            Kumulos.trackEvent(eventType: KumulosSharedEvent.MESSAGE_DELIVERED.rawValue, properties: props)
        }
    }
    
    // MARK Interop with other components
    func presentImmediateAndNextOpenContent() -> Void{
        objc_sync_enter(self.pendingTickleIds)
        defer { objc_sync_exit(self.pendingTickleIds) }
        
        let messagesToPresent = self.getMessagesToPresent([InAppPresented.IMMEDIATELY.rawValue, InAppPresented.NEXT_OPEN.rawValue])
        presenter.queueMessagesForPresentation(messages: messagesToPresent, tickleIds: self.pendingTickleIds)
    }
    
    func presentMessage(withId: Int64) -> Bool {
        var result = true;
        
        messagesContext!.performAndWait({
            let context = self.messagesContext!
            
            let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
            
            fetchRequest.includesPendingChanges = false
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.predicate = NSPredicate(format: "id = %i", withId)
            
            var items: [InAppMessageEntity]
            do {
                items = try context.fetch(fetchRequest) as! [InAppMessageEntity]
            } catch let err {
                result = false;
                print("Failed to evict messages: \(err)")
                return;
            }
            
            if (items.count != 1){
                result = false;
                return;
            }
            
            let message: InAppMessage = InAppMessage(entity: items[0]);
            let tickles = NSOrderedSet(array: [withId])
            presenter.queueMessagesForPresentation(messages: [message], tickleIds: tickles)
        })
        
        return result
    }
    
    func handlePushOpen(notification: KSPushNotification) -> Void {
        let deepLink: [AnyHashable:Any]? = notification.inAppDeepLink();
        if (!inAppEnabled() || deepLink == nil){
            return;
        }
        
        DispatchQueue.global(qos: .default).async(execute: {
            let data = deepLink!["data"] as! [AnyHashable:Any];
            let inAppPartId:Int = data["id"] as! Int
            
            objc_sync_enter(self.pendingTickleIds)
            defer { objc_sync_exit(self.pendingTickleIds) }
            
            self.pendingTickleIds.add(inAppPartId)
            
            let messagesToPresent = self.getMessagesToPresent([])
            
            let tickleMessageFound = messagesToPresent.contains(where: { (message) -> Bool in
                return message.id == inAppPartId
            })
            
            if (!tickleMessageFound) {
                self.sync()
                return
            }
            
            self.presenter.queueMessagesForPresentation(messages: messagesToPresent, tickleIds: self.pendingTickleIds)
        })
    }
    
    func deleteMessageFromInbox(withId : Int64) -> Bool {
        let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":withId]
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_DELETED_FROM_INBOX, properties: props)
        
        removeNotificationTickle(id: withId)
        
        var result = true;
        messagesContext!.performAndWait({
            let context = self.messagesContext!
            let entity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Message", in: context)
            
            let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
            fetchRequest.entity = entity
            fetchRequest.includesPendingChanges = false
            fetchRequest.predicate = NSPredicate(format: "id = %i", withId)
            
            var messageEntities: [InAppMessageEntity]
            do {
                messageEntities = try context.fetch(fetchRequest) as! [InAppMessageEntity]
            } catch let err {
                result = false;
                print("Failed to delete message with id: \(withId) \(err)")
                return;
            }
            
            //setting inbox columns to nil and dismissedAt to now turns this message into a message to be evicted
            if (messageEntities.count == 1){
                messageEntities[0].inboxTo = nil
                messageEntities[0].inboxFrom = nil
                messageEntities[0].inboxConfig = nil
                messageEntities[0].dismissedAt = NSDate()
                if (messageEntities[0].readAt == nil){
                    messageEntities[0].readAt = NSDate()
                }
            }
            
            do{
                try context.save()
            }
            catch let err {
                result = false;
                print("Failed to delete message with id: \(withId) \(err)")
                return
            }
        });
        
        KumulosInApp.maybeRunInboxUpdatedHandler(inboxNeedsUpdate: result);
        
        return result
    }
    
    func markInboxItemRead(withId : Int64, shouldWait: Bool) -> Bool {
        var result = true;
        let block = {
            let context = self.messagesContext!
            let entity: NSEntityDescription? = NSEntityDescription.entity(forEntityName: "Message", in: context)
            
            let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
            fetchRequest.entity = entity
            fetchRequest.includesPendingChanges = false
            fetchRequest.includesPropertyValues = false
            fetchRequest.predicate = NSPredicate(format: "id = %i AND readAt = nil", withId)
            
            var messageEntities: [InAppMessageEntity]
            do {
                messageEntities = try context.fetch(fetchRequest) as! [InAppMessageEntity]
            } catch let err {
                result = false;
                print("Failed to mark as read message with id: \(withId) \(err)")
                return;
            }
            
            if (messageEntities.count == 0){
                result = false
                return
            }
            
            if (messageEntities.count == 1){
                messageEntities[0].readAt = NSDate()
            }
            
            do{
                try context.save()
            }
            catch let err {
                result = false;
                print("Failed to mark as read message with id: \(withId) \(err)")
                return
            }
        }
        shouldWait ? messagesContext!.performAndWait(block) : messagesContext!.perform(block);
        
        
        if (!result){
            return result
        }
        
        let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":withId]
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_READ, properties: props)
        
        removeNotificationTickle(id: withId)
        
        return result
    }
    
    func markAllInboxItemsAsRead() -> Bool {
        var result = true;
        let inboxItems = KumulosInApp.getInboxItems()
        var inboxNeedsUpdate = false
        for item in inboxItems {
            if (item.isRead()){
                continue
            }
            
            let success = markInboxItemRead(withId: item.id, shouldWait: true)
            if (success && !inboxNeedsUpdate) {
                inboxNeedsUpdate = true;
            }
            
            if (!success){
                result = false
            }
        }
        
        KumulosInApp.maybeRunInboxUpdatedHandler(inboxNeedsUpdate: inboxNeedsUpdate);
        
        return result
    }
    
    func readInboxSummary(inboxSummaryBlock: @escaping InboxSummaryBlock) -> Void {
        guard let context = Kumulos.sharedInstance.inAppHelper.messagesContext else {
            self.fireInboxSummaryCallback(callback: inboxSummaryBlock, summary: nil)
            return
        }
        
        context.perform({
            let request = NSFetchRequest<InAppMessageEntity>(entityName: "Message")
            request.includesPendingChanges = false
            request.predicate = NSPredicate(format: "(inboxConfig != nil)")
            request.propertiesToFetch = ["inboxFrom", "inboxTo", "readAt"]
            
            var items: [InAppMessageEntity] = []
            do {
                items = try context.fetch(request) as [InAppMessageEntity]
            } catch {
                print("Failed to fetch items: \(error)")

                self.fireInboxSummaryCallback(callback: inboxSummaryBlock, summary: nil)
                return
            }
            
            var totalCount: Int64 = 0
            var unreadCount: Int64 = 0
            for item in items {
                if (!item.isAvailable()){
                    continue
                }
                
                totalCount += 1
                if (item.readAt == nil){
                    unreadCount += 1
                }
            }
            
            self.fireInboxSummaryCallback(callback: inboxSummaryBlock, summary: InAppInboxSummary(totalCount: totalCount, unreadCount: unreadCount))
        })
    }
    
    private func fireInboxSummaryCallback(callback: @escaping InboxSummaryBlock, summary: InAppInboxSummary?){
        DispatchQueue.main.async {
            callback(summary)
        }
    }
    
    // MARK: Data model
    
    private func mapEntitiesToModels(entities: [InAppMessageEntity] ) -> [InAppMessage]{
        var models: [InAppMessage] = [];
        models.reserveCapacity(entities.count)
        
        for entity in entities {
            let model = InAppMessage(entity: entity);
            models.append(model)
        }
        
        return models;
    }
    
    private func getDataModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel();
        
        let messageEntity = NSEntityDescription();
        messageEntity.name = "Message";
        messageEntity.managedObjectClassName = NSStringFromClass(InAppMessageEntity.self);
        
        var messageProps: [NSAttributeDescription] = [];
        messageProps.reserveCapacity(13);
        
        let partId = NSAttributeDescription();
        partId.name = "id";
        partId.attributeType = NSAttributeType.integer64AttributeType;
        partId.isOptional = false;
        messageProps.append(partId);
        
        let updatedAt = NSAttributeDescription();
        updatedAt.name = "updatedAt";
        updatedAt.attributeType = NSAttributeType.dateAttributeType;
        updatedAt.isOptional = false;
        messageProps.append(updatedAt);
        
        let presentedWhen = NSAttributeDescription();
        presentedWhen.name = "presentedWhen";
        presentedWhen.attributeType = NSAttributeType.stringAttributeType;
        presentedWhen.isOptional = false;
        messageProps.append(presentedWhen);
        
        let content = NSAttributeDescription();
        content.name = "content";
        content.attributeType = NSAttributeType.transformableAttributeType;
        content.valueTransformerName = NSStringFromClass(KSJsonValueTransformer.self);
        content.isOptional = false;
        messageProps.append(content);
        
        let data = NSAttributeDescription();
        data.name = "data";
        data.attributeType = NSAttributeType.transformableAttributeType;
        data.valueTransformerName = NSStringFromClass(KSJsonValueTransformer.self);
        data.isOptional = true;
        messageProps.append(data);
        
        let badgeConfig = NSAttributeDescription();
        badgeConfig.name = "badgeConfig";
        badgeConfig.attributeType = NSAttributeType.transformableAttributeType;
        badgeConfig.valueTransformerName = NSStringFromClass(KSJsonValueTransformer.self);
        badgeConfig.isOptional = true;
        messageProps.append(badgeConfig);
        
        let inboxConfig = NSAttributeDescription();
        inboxConfig.name = "inboxConfig";
        inboxConfig.attributeType = NSAttributeType.transformableAttributeType;
        inboxConfig.valueTransformerName = NSStringFromClass(KSJsonValueTransformer.self);
        inboxConfig.isOptional = true;
        messageProps.append(inboxConfig);
        
        let inboxFrom = NSAttributeDescription();
        inboxFrom.name = "inboxFrom";
        inboxFrom.attributeType = NSAttributeType.dateAttributeType;
        inboxFrom.isOptional = true;
        messageProps.append(inboxFrom);
        
        let inboxTo = NSAttributeDescription();
        inboxTo.name = "inboxTo";
        inboxTo.attributeType = NSAttributeType.dateAttributeType;
        inboxTo.isOptional = true;
        messageProps.append(inboxTo);
        
        let dismissedAt = NSAttributeDescription();
        dismissedAt.name = "dismissedAt";
        dismissedAt.attributeType = NSAttributeType.dateAttributeType;
        dismissedAt.isOptional = true;
        messageProps.append(dismissedAt);
        
        let expiresAt = NSAttributeDescription();
        expiresAt.name = "expiresAt";
        expiresAt.attributeType = NSAttributeType.dateAttributeType;
        expiresAt.isOptional = true;
        messageProps.append(expiresAt);
        
        let readAt = NSAttributeDescription();
        readAt.name = "readAt";
        readAt.attributeType = NSAttributeType.dateAttributeType;
        readAt.isOptional = true;
        messageProps.append(readAt);
        
        let sentAt = NSAttributeDescription();
        sentAt.name = "sentAt";
        sentAt.attributeType = NSAttributeType.dateAttributeType;
        sentAt.isOptional = true;
        messageProps.append(sentAt);
        
        messageEntity.properties = messageProps;
        
        model.entities = [messageEntity]
        
        return model;
    }
    
    @objc
    class KSJsonValueTransformer: ValueTransformer {
        override class func transformedValueClass() -> AnyClass {
            return NSDictionary.self
        }
        
        override class func allowsReverseTransformation() -> Bool {
            return true
        }
        
        override func transformedValue(_ value: Any?) -> Any? {
            if value == nil || value is NSNull {
                return nil
            }
            
            if let value = value {
                if !JSONSerialization.isValidJSONObject(value) {
                    print("Object cannot be transformed to JSON data object!")
                    return nil
                }
            }
            
            var data: Data? = nil
            do {
                if let value = value {
                    data = try JSONSerialization.data(withJSONObject: value, options: [])
                }
            } catch {
                print("Failed to transform JSON to data object")
            }
            
            
            return data
        }
        
        override func reverseTransformedValue(_ value: Any?) -> Any? {
            
            var obj: Any? = nil
            do {
                if let value = value as? Data {
                    obj = try JSONSerialization.jsonObject(with: value, options: [])
                }
            } catch {
                print("Failed to transform data to JSON object")
            }
            
            return obj
        }
    }
}
