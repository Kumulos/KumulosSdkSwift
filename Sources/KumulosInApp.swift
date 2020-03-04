//
//  Kumulos+InApp.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation
import CoreData

public class InAppInboxItem {
    internal(set) open var id: Int64
    internal(set) open var title: String
    internal(set) open var subtitle: String
    internal(set) open var availableFrom: Date?
    internal(set) open var availableTo: Date?
    internal(set) open var dismissedAt : Date?
    
    init(entity: InAppMessageEntity) {
        id = Int64(entity.id)

        let inboxConfig = entity.inboxConfig?.copy() as! [String:Any]

        title = inboxConfig["title"] as! String
        subtitle = inboxConfig["subtitle"] as! String

        availableFrom = entity.inboxFrom?.copy() as? Date
        availableTo = entity.inboxTo?.copy() as? Date
        dismissedAt = entity.dismissedAt?.copy() as? Date
    }

    public func isAvailable() -> Bool {
        if (self.availableFrom != nil && self.availableFrom!.timeIntervalSinceNow > 0) {
            return false;
        } else if (self.availableTo != nil && self.availableTo!.timeIntervalSinceNow < 0) {
            return false;
        }

        return true;
    }
}

public class KumulosInApp {
    public static func updateConsent(forUser consentGiven: Bool) {
        if Kumulos.inAppConsentStrategy != InAppConsentStrategy.ExplicitByUser {
            NSException(name:NSExceptionName(rawValue: "Kumulos: Invalid In-app consent strategy"), reason:"You can only manage in-app messaging consent when the feature is enabled and strategy is set to KSInAppConsentStrategyExplicitByUser", userInfo:nil).raise()
            
            return
        }

        Kumulos.sharedInstance.inAppHelper.updateUserConsent(consentGiven: consentGiven)
    }
    
    public static func getInboxItems() -> [InAppInboxItem]
     {
        if Kumulos.sharedInstance.inAppHelper.messagesContext == nil {
            return []
        }

        var results: [InAppInboxItem] = []
        
        Kumulos.sharedInstance.inAppHelper.messagesContext!.performAndWait({
            guard let context = Kumulos.sharedInstance.inAppHelper.messagesContext else {
                return
            }
            
            let request = NSFetchRequest<InAppMessageEntity>(entityName: "Message")
            request.returnsObjectsAsFaults = false
            request.includesPendingChanges = false
            request.sortDescriptors = [ NSSortDescriptor(key: "updatedAt", ascending: false) ]
            request.predicate = NSPredicate(format: "(inboxConfig != nil)")
            request.propertiesToFetch = ["id", "inboxConfig", "inboxFrom", "inboxTo", "dismissedAt"]
            
            
            var items: [InAppMessageEntity] = []
            do {
                items = try context.fetch(request) as [InAppMessageEntity]
            } catch {
                print("Failed to fetch items: \(error)")

                return
            }
            
            for item in items {
                let inboxItem = InAppInboxItem(entity: item)

                if inboxItem.isAvailable() == false {
                    continue
                }
                
                results.append(inboxItem)
            }
        })

        return results
    }
    
    public static func presentInboxMessage(item: InAppInboxItem) -> InAppMessagePresentationResult {
        if item.isAvailable() == false {
            return InAppMessagePresentationResult.EXPIRED
        }

        let result = Kumulos.sharedInstance.inAppHelper.presentMessage(withId: item.id)
        
        return result ? InAppMessagePresentationResult.PRESENTED : InAppMessagePresentationResult.FAILED 
    }
    
    public static func deleteMessageFromInbox(item: InAppInboxItem) -> Bool {
        return Kumulos.sharedInstance.inAppHelper.deleteMessageFromInbox(withId: item.id)
    }
}
