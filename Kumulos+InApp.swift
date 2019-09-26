//
//  Kumulos+InApp.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation
import CoreData

public class InAppInboxItem: NSObject {
    internal(set) open var id: Int
    internal(set) open var title: String
    internal(set) open var subtitle: String
    internal(set) open var availableFrom: Date?
    internal(set) open var availableTo: Date?
    internal(set) open var dismissedAt : Date?
    
     init(entity: InAppMessageEntity) {
        id = entity.id
        
        //- TODO not sure how to access these from the entity?
        title = "title"
        subtitle = "sub"
        
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

public extension Kumulos {
    func updateConsent(forUser consentGiven: Bool) {
        if self.inAppConsentStrategy != InAppConsentStrategy.ExplicitByUser {
            NSException(name:NSExceptionName(rawValue: "Kumulos: Invalid In-app consent strategy"), reason:"You can only manage in-app messaging consent when the feature is enabled and strategy is set to KSInAppConsentStrategyExplicitByUser", userInfo:nil).raise()
            
            return
        }

        self.inAppHelper.updateUserConsent(consentGiven: consentGiven)
    }
    
    func getInboxItems() -> [InAppInboxItem]
     {
        if self.inAppHelper.messagesContext == nil {
            return []
        }

        var results: [InAppInboxItem] = []
        
        self.inAppHelper.messagesContext!.performAndWait({
            let context = self.inAppHelper.messagesContext!
            
            let request = NSFetchRequest<InAppMessageEntity>(entityName: "Message")
            request.returnsObjectsAsFaults = false
            request.includesPendingChanges = false
            request.sortDescriptors = [ NSSortDescriptor(key: "updatedAt", ascending: false) ]
            request.predicate = NSPredicate(format: "(inboxConfig != %@)")
            request.propertiesToFetch = ["id", "inboxConfig", "inboxFrom", "inboxTo", "dismissedAt"]
            
            
            var items: [InAppMessageEntity] = []
            do {
                items = try context.fetch(request) as [InAppMessageEntity]
            } catch err {
                print("Failed to fetch items: \(err)")
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
    
    func presentInboxMessage(item: InAppInboxItem) -> InAppMessagePresentationResult {
        if item.isAvailable() == false {
            return InAppMessagePresentationResult.EXPIRED
        }

        // TODO
        let result = self.inAppHelper.presentMessage(withId: item.id)

        return result ? InAppMessagePresentationResult.PRESENTED : InAppMessagePresentationResult.FAILED as! InAppMessagePresentationResult
    }
}
