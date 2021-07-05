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
    internal(set) open var sentAt: Date
    internal(set) open var data: NSDictionary?
    private var readAt : Date?
    private var imagePath: String?
    
    private static let defaultImageWidth: UInt = 300
    
    init(entity: InAppMessageEntity) {
        id = Int64(entity.id)

        let inboxConfig = entity.inboxConfig?.copy() as! [String:Any]

        title = inboxConfig["title"] as! String
        subtitle = inboxConfig["subtitle"] as! String

        availableFrom = entity.inboxFrom?.copy() as? Date
        availableTo = entity.inboxTo?.copy() as? Date
        dismissedAt = entity.dismissedAt?.copy() as? Date
        readAt = entity.readAt?.copy() as? Date
        data = entity.data?.copy() as? NSDictionary
        
        if let sentAtNonNil = entity.sentAt?.copy() as? Date {
            sentAt = sentAtNonNil
        }
        else{
            sentAt = entity.updatedAt.copy() as! Date
        }
        
        imagePath = inboxConfig["imagePath"] as? String
    }

    public func isAvailable() -> Bool {
        if (self.availableFrom != nil && self.availableFrom!.timeIntervalSinceNow > 0) {
            return false;
        } else if (self.availableTo != nil && self.availableTo!.timeIntervalSinceNow < 0) {
            return false;
        }

        return true;
    }
    
    public func isRead() -> Bool {
        return readAt != nil;
    }
    
    public func getImageUrl() -> URL? {
        return self.getImageUrl(width: InAppInboxItem.defaultImageWidth)
    }
    
    public func getImageUrl(width: UInt) -> URL? {
        if let imagePathNotNil = imagePath {
            return MediaHelper.getCompletePictureUrl(pictureUrl: imagePathNotNil, width: width)
        }
        
        return nil
    }
}

public struct InAppInboxSummary {
    public let totalCount: Int64
    public let unreadCount: Int64
}

public typealias InboxUpdatedHandlerBlock = () -> Void
public typealias InboxSummaryBlock = (InAppInboxSummary?) -> Void

public class KumulosInApp {
    private static var _inboxUpdatedHandlerBlock: InboxUpdatedHandlerBlock?
    
    public static func updateConsent(forUser consentGiven: Bool) {
        if Kumulos.inAppConsentStrategy != InAppConsentStrategy.ExplicitByUser {
            NSException(name:NSExceptionName(rawValue: "Kumulos: Invalid In-app consent strategy"), reason:"You can only manage in-app messaging consent when the feature is enabled and strategy is set to KSInAppConsentStrategyExplicitByUser", userInfo:nil).raise()
            
            return
        }

        Kumulos.sharedInstance.inAppHelper.updateUserConsent(consentGiven: consentGiven)
    }
    
    public static func getInboxItems() -> [InAppInboxItem] {
        guard let context = Kumulos.sharedInstance.inAppHelper.messagesContext else {
            return []
        }
    
        var results: [InAppInboxItem] = []
        context.performAndWait({
            let request = NSFetchRequest<InAppMessageEntity>(entityName: "Message")
            request.includesPendingChanges = false
            request.sortDescriptors = [
                NSSortDescriptor(key: "sentAt", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false),
                NSSortDescriptor(key: "id", ascending: false)
            ]
            request.predicate = NSPredicate(format: "(inboxConfig != nil)")
            request.propertiesToFetch = ["id", "inboxConfig", "inboxFrom", "inboxTo", "dismissedAt", "readAt", "sentAt", "data", "updatedAt"]
            
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
    
    public static func markAsRead(item: InAppInboxItem) -> Bool {
        if (item.isRead()){
            return false
        }
        let res = Kumulos.sharedInstance.inAppHelper.markInboxItemRead(withId: item.id, shouldWait: true)
        maybeRunInboxUpdatedHandler(inboxNeedsUpdate: res)
        
        return res
    }
    
    public static func markAllInboxItemsAsRead() -> Bool {
        return Kumulos.sharedInstance.inAppHelper.markAllInboxItemsAsRead()
    }
    
    public static func setOnInboxUpdated(inboxUpdatedHandlerBlock: InboxUpdatedHandlerBlock?) -> Void {
        _inboxUpdatedHandlerBlock = inboxUpdatedHandlerBlock
    }
    
    public static func getInboxSummaryAsync(inboxSummaryBlock: @escaping InboxSummaryBlock){
        Kumulos.sharedInstance.inAppHelper.readInboxSummary(inboxSummaryBlock: inboxSummaryBlock)
    }

    // Internal helpers
    static func maybeRunInboxUpdatedHandler(inboxNeedsUpdate: Bool) -> Void {
        if (!inboxNeedsUpdate){
            return;
        }
        
        if let inboxUpdatedHandler = _inboxUpdatedHandlerBlock {
            DispatchQueue.main.async {
                inboxUpdatedHandler()
            }
        }
    }
}
