//
//  InAppHelper.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation
import CoreData

public enum InAppPresented : String {
    case IMMEDIATELY = "immediately"
    case NEXT_OPEN = "next-open"
    case NEVER = "never"
}

public enum InAppMessagePresentationResult : String {
    case PRESENTED = "presented"
    case EXPIRED = "expired"
    case FAILED = "failed"
}

class InAppMessageEntity : NSManagedObject {
    @NSManaged var id : Int
    @NSManaged var updatedAt: Date
    @NSManaged var presentedWhen: String
    @NSManaged var content: String
    @NSManaged var data : NSObject
    @NSManaged var badgeConfig : NSObject
    @NSManaged var inboxConfig : NSObject
    @NSManaged var dismissedAt : Date
}

public class InAppMessage: NSObject {
    internal(set) open var id: Int
    internal(set) open var updatedAt: Date
    internal(set) open var presentedWhen: InAppPresented
    internal(set) open var content: String
    internal(set) open var data : NSObject
    internal(set) open var badgeConfig : NSObject
    internal(set) open var inboxConfig : NSObject
    internal(set) open var dismissedAt : Date
    
    init(entity: InAppMessageEntity) {
        id = entity.id
        updatedAt = entity.updatedAt
        presentedWhen = InAppPresented.NEVER
        
        if (entity.presentedWhen == InAppPresented.IMMEDIATELY.rawValue) {
            presentedWhen = InAppPresented.IMMEDIATELY
        }
        
        if (entity.presentedWhen == InAppPresented.NEXT_OPEN.rawValue){
            presentedWhen = InAppPresented.NEXT_OPEN
        }
        
        content = entity.content
        data = entity.data
        badgeConfig = entity.badgeConfig
        inboxConfig = entity.inboxConfig
        dismissedAt = entity.dismissedAt
    }
}


class InAppHelper {
    
    
    internal var messagesContext : NSManagedObjectContext?
    
    //TODO - date?
    //internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = nil
    
    internal let KUMULOS_IN_APP_CONSENTED_KEY = "KumulosInAppConsented"
    internal let KUMULOS_MESSAGES_LAST_SYNC_TIME = "KumulosMessagesLastSyncTime"
    
    internal let MESSAGE_TYPE_IN_APP = 2
    
    
    
    //internal let pendingTickleIds;
    
    // MARK: Initialization
    
    init() {
        
        
        
        messagesContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        
//        self.pendingTickleIds = []
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
