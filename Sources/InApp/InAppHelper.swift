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

typealias kumulos_applicationPerformFetchWithCompletionHandler = @convention(c) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ completionHandler: (UIBackgroundFetchResult) -> Void) -> Void;

private var ks_existingBackgroundFetchDelegate: IMP? = nil

internal class InAppHelper {
    

    private var kumulos: Kumulos!
    private var presenter: InAppPresenter!
    private var pendingTickleIds: NSMutableOrderedSet = NSMutableOrderedSet(capacity: 1)
    
    var messagesContext: NSManagedObjectContext? = nil;
    
    internal let KUMULOS_IN_APP_CONSENTED_KEY = "KumulosInAppConsented"
    internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = "KumulosMessagesLastSyncTime"
    
    internal let MESSAGE_TYPE_IN_APP = 2
    
    
    // MARK: Initialization
    
    init(kumulos: Kumulos) {
        self.kumulos = kumulos
        presenter = InAppPresenter(kumulos: kumulos)
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
        objc_sync_enter(self.pendingTickleIds)
        defer { objc_sync_exit(self.pendingTickleIds) }
        
        let messagesToPresent = self.getMessagesToPresent([InAppPresented.IMMEDIATELY.rawValue, InAppPresented.NEXT_OPEN.rawValue])
        presenter.queueMessagesForPresentation(messages: messagesToPresent, tickleIds: self.pendingTickleIds)
    }
    
    let setupSyncTask:Void = {
        let klass : AnyClass = type(of: UIApplication.shared.delegate!)
        
        // Perform background fetch
        let performFetchSelector = #selector(UIApplicationDelegate.application(_:performFetchWithCompletionHandler:))
        let performFetchMethod = class_getInstanceMethod(klass, performFetchSelector)
        let regType = method_getTypeEncoding(performFetchMethod!)
        let kumulosPerformFetch = imp_implementationWithBlock({ (obj:Any, _cmd:Selector, application:UIApplication, completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void in
            var fetchResult : UIBackgroundFetchResult = .noData
            let fetchBarrier = DispatchSemaphore(value: 0)
            
            if let _ = ks_existingBackgroundFetchDelegate {
                unsafeBitCast(ks_existingBackgroundFetchDelegate, to: kumulos_applicationPerformFetchWithCompletionHandler.self)(obj, _cmd, application, { (result : UIBackgroundFetchResult) in
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
                    } else if result > 1 {
                        fetchResult = .newData
                    }
                    // No data case is default, allow override from other handler
                    completionHandler(fetchResult)
                }
            }
            else{
                completionHandler(fetchResult)
            }
        })
        
        ks_existingBackgroundFetchDelegate = class_replaceMethod(klass, performFetchSelector, kumulosPerformFetch, regType)
    }()
    
    // MARK: State helpers
    func inAppEnabled() -> Bool {
        return Kumulos.inAppConsentStrategy != InAppConsentStrategy.NotEnabled && userConsented();
    }
    
    func userConsented() -> Bool {
        return UserDefaults.standard.bool(forKey: KUMULOS_IN_APP_CONSENTED_KEY);
    }
    
    func updateUserConsent(consentGiven: Bool) {
        let props: [String: Any] = ["consented":consentGiven]
        
        Kumulos.trackEventImmediately(eventType: KumulosEvent.IN_APP_CONSENT_CHANGED.rawValue, properties: props)
        
        if (consentGiven) {
            UserDefaults.standard.set(consentGiven, forKey: KUMULOS_IN_APP_CONSENTED_KEY)
            handleEnrollmentAndSyncSetup()
        }
        else {
            DispatchQueue.global(qos: .default).async(execute: {
                self.resetMessagingState()
            })
        }
    }
    
    func handleAssociatedUserChange() -> Void {
        if (Kumulos.inAppConsentStrategy == InAppConsentStrategy.NotEnabled) {
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
        if (Kumulos.inAppConsentStrategy == InAppConsentStrategy.AutoEnroll && userConsented() == false) {
            updateUserConsent(consentGiven: true)
            return;
        }
        else if (Kumulos.inAppConsentStrategy == InAppConsentStrategy.NotEnabled && userConsented() == true) {
            updateUserConsent(consentGiven: false)
            return;
        }
        
        if (inAppEnabled()) {
            _ = setupSyncTask
            
            NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        }
    }

    private func resetMessagingState() -> Void {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        UserDefaults.standard.removeObject(forKey: KUMULOS_IN_APP_CONSENTED_KEY)
        UserDefaults.standard.removeObject(forKey: KUMULOS_MESSAGES_LAST_SYNC_TIME)
        
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
        let lastSyncTime = UserDefaults.standard.object(forKey: KUMULOS_MESSAGES_LAST_SYNC_TIME) as? NSDate
        var after = ""
        
        if lastSyncTime != nil {
            let formatter = DateFormatter()
            formatter.timeStyle = .full
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            formatter.timeZone = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
            if let lastSyncTime = lastSyncTime {
                //TODO: extend String with urlEncoded
                //after = "?after=\(formatter.string(from: lastSyncTime).urlEncoded())"
            }
        }
        
        let path = "/v1/users/\(Kumulos.currentUserIdentifier)/messages\(after)"
        
        kumulos.pushHttpClient.sendRequest(.GET, toPath: path, data: nil, onSuccess: { response, decodedBody in
            let messagesToPersist = decodedBody as? [[AnyHashable : Any]]
            if (messagesToPersist == nil || messagesToPersist!.count == 0) {
                if onComplete != nil {
                    onComplete?(0)
                }
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
        }, onFailure: { response, error in
            if onComplete != nil {
                onComplete?(-1)
            }
        })
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
            
            for message in messages {
                let partId = message["id"] as! Int
                
                let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
                fetchRequest.entity = entity
                let predicate: NSPredicate = NSPredicate(format: "id = %@", partId)
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
                model.dismissedAt =  dateParser.date(from: message["openedAt"] as? String ?? "") as NSDate?
                model.presentedWhen = message["presentedWhen"] as! String

                model.content = message["content"] as! NSDictionary
                model.data = message["data"] as? NSDictionary
                model.badgeConfig = message["badge"] as? NSDictionary
                model.inboxConfig = message["inbox"] as? NSDictionary
                
                if (model.inboxConfig != nil){
                    let inbox = model.inboxConfig!
                    
                    model.inboxFrom = dateParser.date(from: inbox["from"] as? String ?? "") as NSDate?
                    model.inboxTo = dateParser.date(from: inbox["to"] as? String ?? "") as NSDate?
                }
                
                if (model.updatedAt.timeIntervalSince1970 > lastSyncTime.timeIntervalSince1970) {
                    lastSyncTime = model.updatedAt
                }
            }
            
            // Evict
            evictMessages(context: context)
            
            do{
                try context.save()
            }
            catch let err {
                print("Failed to persist messages: \(err)")
                return
            }
            
            UserDefaults.standard.set(lastSyncTime, forKey: KUMULOS_MESSAGES_LAST_SYNC_TIME)
            
            trackMessageDelivery(messages: messages)
        })
    }
    
    private func evictMessages(context: NSManagedObjectContext) -> Void {
        let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
        fetchRequest.includesPendingChanges = true
        
        let predicate: NSPredicate? = NSPredicate(format: "((dismissedAt != nil AND inboxConfig = nil) OR (inboxTo != nil AND inboxTo < %@))", NSDate())
        fetchRequest.predicate = predicate
        
        
        var toEvict: [InAppMessageEntity]
        do {
            toEvict = try context.fetch(fetchRequest) as! [InAppMessageEntity]
        } catch let err {
            print("Failed to evict messages: \(err)")
            return;
        }
        
        for messageToEvict in toEvict {
            context.delete(messageToEvict)
        }
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
            
            let predicate: NSPredicate? = NSPredicate(format: "((presentedWhen IN %@) OR (id IN %@)) AND (dismissedAt = %@)", presentedWhenOptions, self.pendingTickleIds)
            fetchRequest.predicate = predicate
            
            let sortDescriptor = NSSortDescriptor(key: "updatedAt", ascending: true)
            fetchRequest.sortDescriptors = [sortDescriptor]
            
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
    

    private func trackMessageOpened(message: InAppMessage) -> Void {
        let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":message.id]
        
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_OPENED, properties: props)
    }
    
    private func markMessageDismissed(message: InAppMessage) -> Void {
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
  
            let predicate: NSPredicate? = NSPredicate(format: "id = %@", message.id)
            fetchRequest.predicate = predicate
            
            var messageEntities: [InAppMessageEntity]
            do {
                messageEntities = try context.fetch(fetchRequest) as! [InAppMessageEntity]
            } catch let err {
                print("Failed to evict messages: \(err)")
                return;
            }
            
            if (messageEntities.count == 1){
                messageEntities[0].dismissedAt = NSDate()
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
            Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_DELIVERED, properties: props)
        }
    }
    
    // MARK Interop with other components
    
    func presentMessageWithId(messageId: Int) -> Bool {
        var result = true;
        
        messagesContext!.performAndWait({
            let context = self.messagesContext!
            
            let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
            
            fetchRequest.includesPendingChanges = false
            fetchRequest.returnsObjectsAsFaults = false
            
            let predicate: NSPredicate? = NSPredicate(format: "id = %@", messageId)
            fetchRequest.predicate = predicate
            
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
            let tickles = NSOrderedSet(array: [messageId])
            presenter.queueMessagesForPresentation(messages: [message], tickleIds: tickles)
        })
        
        return result
    }
    
    func handlePushOpen(notification: KSPushNotification) -> Void {
        let deepLink: [AnyHashable:Any]? = notification.inAppDeepLink();
        if (!inAppEnabled() || deepLink == nil){
            return;
        }
        
        let isActive = UIApplication.shared.applicationState == .active
        
        DispatchQueue.global(qos: .default).async(execute: {
            let data = deepLink!["data"] as! [AnyHashable:Any];
            let inAppPartId:Int = data["id"] as! Int
            
            objc_sync_enter(self.pendingTickleIds)
            defer { objc_sync_exit(self.pendingTickleIds) }
            
            self.pendingTickleIds.add(inAppPartId)
            if (isActive){
                let messagesToPresent = self.getMessagesToPresent([])
                self.presenter.queueMessagesForPresentation(messages: messagesToPresent, tickleIds: self.pendingTickleIds)
            }
        })
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
        messageProps.reserveCapacity(10);
        
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
        
        messageEntity.properties = messageProps;
        
        model.setEntities([messageEntity], forConfigurationName: "default");
        
        return model;
    }
    
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
