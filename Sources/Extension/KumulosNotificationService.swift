//
//  Kumulos.swift
//  KumulosSDKExtension
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation
import UIKit
import UserNotifications

public class KumulosNotificationService {
    fileprivate static var analyticsHelper: AnalyticsHelper?
    private static let syncBarrier = DispatchSemaphore(value: 0)

    public class func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let bestAttemptContent = (request.content.mutableCopy() as! UNMutableNotificationContent)
        let userInfo = request.content.userInfo

        if (!validateUserInfo(userInfo: userInfo)){
            return
        }

        let custom = userInfo["custom"] as! [AnyHashable:Any]
        let data = custom["a"] as! [AnyHashable:Any]

        let msg = data["k.message"] as! [AnyHashable:Any]
        let msgData = msg["data"] as! [AnyHashable:Any]
        let id = msgData["id"] as! Int

        if(bestAttemptContent.categoryIdentifier == "") {
            let actionButtons = getButtons(userInfo: userInfo, bestAttemptContent:bestAttemptContent)

            addCategory(bestAttemptContent:bestAttemptContent, actionArray: actionButtons, id: id)
        }

        let dispatchGroup = DispatchGroup()

        maybeAddImageAttachment(dispatchGroup: dispatchGroup, userInfo: userInfo, bestAttemptContent: bestAttemptContent)

        if (AppGroupsHelper.isKumulosAppGroupDefined()){
            maybeSetBadge(bestAttemptContent: bestAttemptContent, userInfo: userInfo)
            trackDeliveredEvent(dispatchGroup: dispatchGroup, userInfo: userInfo, notificationId: id)
            PendingNotificationHelper.add(notification: PendingNotification(id: id, deliveredAt: Date(), identifier: request.identifier))
        }

        dispatchGroup.notify(queue: .main) {
            contentHandler(bestAttemptContent)
        }
    }

    fileprivate class func validateUserInfo(userInfo:[AnyHashable:Any]) -> Bool {
        var dict: [AnyHashable:Any] = userInfo
        let keysInOrder = ["custom", "a", "k.message", "data"]

        for key in keysInOrder
        {
            if (dict[key] == nil) {
                return false
            }

            dict = dict[key] as! [AnyHashable:Any]
        }

        if (dict["id"] == nil) {
            return false
        }

        return true
    }

    fileprivate class func getButtons(userInfo:[AnyHashable:Any], bestAttemptContent: UNMutableNotificationContent) -> NSMutableArray {
        let actionArray = NSMutableArray()

        let custom = userInfo["custom"] as! [AnyHashable:Any]
        let data = custom["a"] as! [AnyHashable:Any]

        let buttons = data["k.buttons"] as? NSArray

        if (buttons == nil || buttons!.count == 0) {
            return actionArray;
        }

        for button in buttons! {
            let buttonDict = button as! [AnyHashable:Any]

            let id = buttonDict["id"] as! String
            let text = buttonDict["text"] as! String
            
            if #available(iOS 15.0, *) {
                let icon = getButtonIcon(button: buttonDict)
                let action = UNNotificationAction(identifier: id, title: text, options: .foreground, icon: icon)
                actionArray.add(action);
            } else {
                let action = UNNotificationAction(identifier: id, title: text, options: .foreground)
                actionArray.add(action);
            }
            
        }

        return actionArray;
    }
    
    @available(iOS 15.0, *)
    fileprivate class func getButtonIcon(button:[AnyHashable:Any]) -> UNNotificationActionIcon? {
        guard let icon = button["icon"] as? [String:String], let iconType = icon["type"], let iconId = icon["id"] else {
            return nil
        }
        
        if (iconType == "custom") {
            //TODO - What if this doesnt exist? Catch exception -> return nil?
            return UNNotificationActionIcon(templateImageName: iconId)
        }
        
        return UNNotificationActionIcon(systemImageName: iconId)
    }

    fileprivate class func addCategory(bestAttemptContent: UNMutableNotificationContent, actionArray:NSMutableArray, id: Int) {
        let categoryIdentifier = CategoryHelper.getCategoryIdForMessageId(messageId: id)

        let category = UNNotificationCategory(identifier: categoryIdentifier, actions: actionArray as! [UNNotificationAction], intentIdentifiers: [],  options: .customDismissAction)

        CategoryHelper.registerCategory(category: category)

        bestAttemptContent.categoryIdentifier = categoryIdentifier
    }

    fileprivate class func maybeAddImageAttachment(dispatchGroup: DispatchGroup, userInfo: [AnyHashable:Any], bestAttemptContent: UNMutableNotificationContent) {
        let attachments = userInfo["attachments"] as? [AnyHashable : Any]
        let pictureUrl = attachments?["pictureUrl"] as? String

        guard let picUrlNonNull = pictureUrl else { return }

        let picExtension = getPictureExtension(picUrlNonNull)
        let url = MediaHelper.getCompletePictureUrl(pictureUrl: picUrlNonNull as String, width: UInt(floor(UIScreen.main.bounds.size.width)))
        
        dispatchGroup.enter()

        loadAttachment(url!, withExtension: picExtension, completionHandler: { attachment in
            if attachment != nil {
               bestAttemptContent.attachments = [attachment!]

            }
            dispatchGroup.leave()
        })
    }

    fileprivate class func getPictureExtension(_ pictureUrl: String?) -> String? {
        if (pictureUrl == nil){
            return nil;
        }
        let pictureExtension = URL(fileURLWithPath: pictureUrl!).pathExtension
        if (pictureExtension == "") {
            return nil
        }

        return "." + (pictureExtension)
    }

    fileprivate class func loadAttachment(_ url: URL, withExtension pictureExtension: String?, completionHandler: @escaping (UNNotificationAttachment?) -> Void) {
        let session = URLSession(configuration: URLSessionConfiguration.default)

        (session.downloadTask(with: url, completionHandler: { temporaryFileLocation, response, error in
            if error != nil {
                print("NotificationServiceExtension: \(error!.localizedDescription)")
                completionHandler(nil)
                return
            }

            var finalExt = pictureExtension
            if finalExt == nil {
                finalExt = self.getPictureExtension(response?.suggestedFilename)
                if finalExt == nil {
                    completionHandler(nil)
                    return
                }
            }

            if (temporaryFileLocation == nil){
                completionHandler(nil)
                return
            }

            let fileManager = FileManager.default
            let localURL = URL(fileURLWithPath: temporaryFileLocation!.path + (finalExt!))
            do {
                try fileManager.moveItem(at: temporaryFileLocation!, to: localURL)
            } catch {
                completionHandler(nil)
                return
            }

            var attachment: UNNotificationAttachment? = nil
            do {
                attachment = try UNNotificationAttachment(identifier: "", url: localURL, options: nil)
            } catch let attachmentError {
                print("NotificationServiceExtension: attachment error: \(attachmentError.localizedDescription)")
            }

            completionHandler(attachment)
        })).resume()
    }

    fileprivate class func maybeSetBadge(bestAttemptContent: UNMutableNotificationContent, userInfo: [AnyHashable:Any]){
        let aps = userInfo["aps"] as! [AnyHashable:Any]
        if let contentAvailable = aps["content-available"] as? Int, contentAvailable == 1 {
            return
        }

        let newBadge: NSNumber? = KumulosHelper.getBadgeFromUserInfo(userInfo: userInfo)
        if (newBadge == nil){
            return;
        }

        bestAttemptContent.badge = newBadge
        KeyValPersistenceHelper.set(newBadge, forKey: KumulosUserDefaultsKey.BADGE_COUNT.rawValue)
    }

    fileprivate class func trackDeliveredEvent(dispatchGroup: DispatchGroup, userInfo: [AnyHashable:Any], notificationId: Int) {
        if (isBackgroundPush(userInfo: userInfo)){
            return
        }

        initializeAnalyticsHelper()
        guard let analyticsHelper = self.analyticsHelper else {
            return
        }

        let props: [String:Any] = ["type" : KS_MESSAGE_TYPE_PUSH, "id":notificationId]

        dispatchGroup.enter()

        analyticsHelper.trackEvent(eventType: KumulosSharedEvent.MESSAGE_DELIVERED.rawValue, atTime: Date(), properties: props, immediateFlush: true, onSyncComplete: {err in
            self.syncBarrier.signal()
        })

        _ = syncBarrier.wait(timeout: .now() + .seconds(10))
        dispatchGroup.leave()
    }

    fileprivate class func initializeAnalyticsHelper() {
        let apiKey = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.API_KEY.rawValue)
        let secretKey = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.SECRET_KEY.rawValue)

        guard let apiKey = apiKey as? String, let secretKey = secretKey as? String else {
            print("Extension: authorization credentials not present")
            return;
        }

        let eventsBaseUrl = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.EVENTS_BASE_URL.rawValue) as? String ?? "https://events.kumulos.com";

        analyticsHelper = AnalyticsHelper(apiKey: apiKey, secretKey: secretKey, baseEventsUrl: eventsBaseUrl)
    }

    fileprivate class func isBackgroundPush(userInfo: [AnyHashable:Any]) -> Bool{
        let aps = userInfo["aps"] as! [AnyHashable:Any]
        if let contentAvailable = aps["content-available"] as? Int, contentAvailable == 1 {
            return true
        }

        return false
    }
}
