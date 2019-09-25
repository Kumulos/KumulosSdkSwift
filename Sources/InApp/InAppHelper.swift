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
    
    
    internal var messagesContext : NSManagedObjectContext?
    
    //TODO - date?
    //internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = nil
    
    internal let KUMULOS_IN_APP_CONSENTED_KEY = "KumulosInAppConsented"
    internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = "KumulosMessagesLastSyncTime"
    
    internal let MESSAGE_TYPE_IN_APP = 2
    
    
    
    //internal let pendingTickleIds;
    
    // MARK: Initialization
    
    init() {//TODO: initWithKumulos in Objective-C
        
        
        
        messagesContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        
//        self.pendingTickleIds = []
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
            return NSData.self
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
        
    }
    
    
    private func setupSyncTask() -> Void {
    
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
        
        Kumulos.trackEvent(eventType: KumulosEvent.IN_APP_CONSENT_CHANGED, properties: props)
        
        if (consentGiven) {
            UserDefaults.standard.set(consentGiven, forKey: KUMULOS_IN_APP_CONSENTED_KEY)
            handleEnrollmentAndSyncSetup()
        }
        else {
            resetMessagingState()
        }
    }
    
    private func handleEnrollmentAndSyncSetup() -> Void {
        if (Kumulos.inAppConsentStrategy == InAppConsentStrategy.AutoEnroll && userConsented() == false) {
            updateUserConsent(consentGiven: true)
        }
        else if (Kumulos.inAppConsentStrategy == InAppConsentStrategy.NotEnabled && userConsented() == true) {
            updateUserConsent(consentGiven: false)
        }
        
        if (inAppEnabled()) {
            setupSyncTask()
            //TODO - NSNotificationCenter.defaultCenter addObserver
        }
    }
    
    private func resetMessagingState() -> Void {
        //TODO - NSNotificationCenter removeObserver...
        
        UserDefaults.standard.removeObject(forKey: KUMULOS_IN_APP_CONSENTED_KEY)
        UserDefaults.standard.removeObject(forKey: KUMULOS_MESSAGES_LAST_SYNC_TIME)
        
        //TODO - performBlockAndWait...
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
    
    
}
