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
    private var pendingTickleIds: NSMutableOrderedSet?
    
    var messagesContext: NSManagedObjectContext? = nil;
    
    //TODO - date?
    //internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = nil
    
    internal let KUMULOS_IN_APP_CONSENTED_KEY = "KumulosInAppConsented"
    internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = "KumulosMessagesLastSyncTime"
    
    internal let MESSAGE_TYPE_IN_APP = 2
    
    
    // MARK: Initialization
    
    init(kumulos: Kumulos) {
        self.kumulos = kumulos
        pendingTickleIds = NSMutableOrderedSet(capacity: 1)
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
    
    @objc func appBecameActive() -> Void {
        let lockQueue = DispatchQueue(label: "pendingTickleIds")
        lockQueue.sync {
            //TODO: implement
            //let messagesToPresent = getMessagesToPresent([KSInAppPresentedImmediately, KSInAppPresentedNextOpen])
            //presenter.queueMessages(forPresentation: messagesToPresent, presentingTickles: pendingTickleIds)
        }
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
    private func trackMessageOpened(message: InAppMessage) -> Void {
        let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":message.id]
        
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_OPENED, properties: props)
    }
    
    private func markMessageDismissed(message: InAppMessage) -> Void {
        let props: [String:Any] = ["type" : MESSAGE_TYPE_IN_APP, "id":message.id]
        
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_DISMISSED, properties: props)
        
        //TODO - update in local DB
    }
    
    // MARK: Swizzled behaviour handlers
    
   
}

private var ks_existingBackgroundFetchDelegate: IMP? = nil
typealias KSCompletionHandler = (UIBackgroundFetchResult) -> Void



func kumulos_applicationPerformFetchWithCompletionHandler(_ self: Any?, _ _cmd: Selector, _ application: UIApplication?, _ completionHandler: KSCompletionHandler) {
}
