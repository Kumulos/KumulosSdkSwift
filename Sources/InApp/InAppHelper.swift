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


internal class InAppHelper {
    

    private var kumulos: Kumulos!
    private var presenter: InAppPresenter!
    private var pendingTickleIds: NSMutableOrderedSet = NSMutableOrderedSet(capacity: 1)
    
    var messagesContext: NSManagedObjectContext? = nil;
    
    //TODO - date?
    //internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = nil
    
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
        //TODO: implement
        //presenter.queueMessages(forPresentation: messagesToPresent, presentingTickles: pendingTickleIds)
    }
    
    private func setupSyncTask() -> Void {
        //TODO: dispatch_once
        
        
        //        let klass : AnyClass = type(of: UIApplication.shared.delegate!)
        //
        //        // Perform background fetch
        //        let performFetchSelector = #selector(UIApplicationDelegate.application(_:performFetchWithCompletionHandler:))
        //        let fetchType = "\("Void")\("Any?")\("Selector")\("UIApplication")\("KSCompletionHandler")".utf8CString
        
        //TODO: swizzling
        //ks_existingBackgroundFetchDelegate = class_replaceMethod(klass, performFetchSelector, kumulos_applicationPerformFetchWithCompletionHandler as? IMP, fetchType)
    }
    
    
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
            setupSyncTask()
            
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
            
            var messages: [InAppMessageEntity]? = nil
            do {
                messages = try context?.fetch(fetchRequest) as? [InAppMessageEntity]
            } catch {
                return
            }

            for message in messages ?? [] {
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
    
    private func sync(_ onComplete: ((_ result: Int) -> Void)? = nil) {
        let lastSyncTime = UserDefaults.standard.object(forKey: KUMULOS_MESSAGES_LAST_SYNC_TIME) as? Date
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
                    //TODO:
                    //presenter.queueMessages(forPresentation: messagesToPresent, presentingTickles: pendingTickleIds)
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
            
            var lastSyncTime = Date(timeIntervalSince1970: 0)
            let dateParser = DateFormatter()
            dateParser.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            
            for message in messages {
                let partId = message["id"] as! Int
                
                let fetchRequest:NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
                fetchRequest.entity = entity
                var predicate: NSPredicate = NSPredicate(format: "id = %@", partId)
               
                fetchRequest.predicate = predicate
                
                
                
                
                var fetchedObjects: [InAppMessageEntity];
                do {
                    fetchedObjects = try context.fetch(fetchRequest) as! [InAppMessageEntity]
                } catch {
                    continue;
                }
                
                // Upsert
                var model: InAppMessageEntity = fetchedObjects.count == 1 ? fetchedObjects[0] : InAppMessageEntity(entity: entity!, insertInto: context)
               
                
                model.id = partId
                model.updatedAt = dateParser.date(from: message["updatedAt"] as? String ?? "")
                model.dismissedAt =  dateParser.date(from: message["openedAt"] as? String ?? "")
                model.presentedWhen = message["presentedWhen"] as! String
                //TODO:
//                model.content = message["content"]
//                model.data = message["data"] == NSNull.null ? nil : message["data"]
//                model.badgeConfig = message["badge"] == NSNull.null ? nil : message["badge"]
//                model.inboxConfig = message["inbox"] == NSNull.null ? nil : message["inbox"]
//
//                if model.inboxConfig != nil {
//                    let inbox = model.inboxConfig
//                    model.inboxFrom = !(inbox["from"] == NSNull.null) ? dateParser.date(from: inbox["from"] as? String ?? "") : nil
//                    model.inboxTo = !(inbox["to"] == NSNull.null) ? dateParser.date(from: inbox["to"] as? String ?? "") : nil
//                }
                
//                if model.updatedAt.timeIntervalSince1970 > lastSyncTime.timeIntervalSince1970 {
//                    lastSyncTime = model.updatedAt
//                }
            }
            
            // Evict
            evictMessages(context: context)
            
           
            do{
                try context.save()
            }
            catch let err {
                print("Failed to persist messages")
                print("\(err)")
                return
            }
            
            
            UserDefaults.standard.set(lastSyncTime, forKey: KUMULOS_MESSAGES_LAST_SYNC_TIME)
            
            trackMessageDelivery(messages: messages)
        })
    }
    
    private func evictMessages(context: NSManagedObjectContext) -> Void {
        //TODO:
//        NSFetchRequest* fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Message"];
//        [fetchRequest setIncludesPendingChanges:YES];
//
//        NSPredicate* predicate = [NSPredicate
//            predicateWithFormat:@"(dismissedAt != %@ AND inboxConfig = %@) OR (inboxTo != %@ AND inboxTo < %@)",
//            nil, nil, nil, [NSDate date]];
//        [fetchRequest setPredicate:predicate];
//
//        NSError* err = nil;
//        NSArray<KSInAppMessageEntity*>* toEvict = [context executeFetchRequest:fetchRequest error:&err];
//
//        if (err != nil) {
//            NSLog(@"Failed to evict messages %@", err);
//            return;
//        }
//
//        for (KSInAppMessageEntity* message in toEvict) {
//            [context deleteObject:message];
//        }
    }
    
    private func trackMessageDelivery(messages: [[AnyHashable : Any]]) -> Void {
        //TODO:
//        for (NSDictionary* message in messages) {
//            [self.kumulos trackEvent:KumulosEventMessageDelivered withProperties:@{@"type": @(KS_MESSAGE_TYPE_IN_APP), @"id": message[@"id"]}];
//        }
    }
   
    private func getMessagesToPresent(_ presentedWhenOptions: [String]) -> [InAppMessage]? {
        var messages: [InAppMessage]? = []
        
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
        
        //TODO - update in local DB
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
            return NSData.self//TODO: mb Data? implicitly converted?
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
    
    // MARK: Swizzled behaviour handlers
    
   
}

private var ks_existingBackgroundFetchDelegate: IMP? = nil
typealias KSCompletionHandler = (UIBackgroundFetchResult) -> Void



func kumulos_applicationPerformFetchWithCompletionHandler(_ self: Any?, _ _cmd: Selector, _ application: UIApplication?, _ completionHandler: KSCompletionHandler) {
}
