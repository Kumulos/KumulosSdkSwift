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
    internal static let KS_MEDIA_RESIZER_BASE_URL = "https://i.app.delivery"
    fileprivate static var analyticsHelper: AnalyticsHelper?
    
    public class func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let bestAttemptContent =  (request.content.mutableCopy() as! UNMutableNotificationContent)
        let userInfo = request.content.userInfo
        
        if (!validateUserInfo(userInfo: userInfo)){
            return
        }
        
        let custom = userInfo["custom"] as! [AnyHashable:Any]
        let data = custom["a"] as! [AnyHashable:Any]
        
        let msg = data["k.message"] as! [AnyHashable:Any]
        let msgData = msg["data"] as! [AnyHashable:Any]
        let id = msgData["id"] as! Int
        
        if (AppGroupsHelper.isKumulosAppGroupDefined()){
            maybeSetBadge(bestAttemptContent: bestAttemptContent, userInfo: userInfo)
            trackDeliveredEvent(userInfo: userInfo, notificationId: id)
        }
       
        let buttons = data["k.buttons"] as? NSArray
        
        if (buttons != nil && bestAttemptContent.categoryIdentifier == "") {
            addButtons(messageId: id, bestAttemptContent: bestAttemptContent, buttons: buttons!)
        }
        
        let attachments = userInfo["attachments"] as? [AnyHashable : Any]
        let pictureUrl = attachments?["pictureUrl"] as? String

        if pictureUrl == nil {
            contentHandler(bestAttemptContent)
            return
        }

        let picExtension = getPictureExtension(pictureUrl)
        let url = getCompletePictureUrl(pictureUrl!)

        if (url == nil){
            contentHandler(bestAttemptContent)
            return
        }

        loadAttachment(url!, withExtension: picExtension, completionHandler: { attachment in
               if attachment != nil {
                   bestAttemptContent.attachments = [attachment!]
               }
               contentHandler(bestAttemptContent)
           })
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
        
        if (dict["id"] == nil){
            return false
        }

        return true
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
    
    fileprivate class func addButtons(messageId: Int, bestAttemptContent: UNMutableNotificationContent, buttons: NSArray) {
        if (buttons.count == 0) {
            return;
        }
        
        let actionArray = NSMutableArray()
        
        for button in buttons {
            let buttonDict = button as! [AnyHashable:Any]
            
            let id = buttonDict["id"] as! String
            let text = buttonDict["text"] as! String
            
            let action = UNNotificationAction(identifier: id, title: text, options: .foreground)
            actionArray.add(action);
        }
        
        let categoryIdentifier = CategoryHelper.getCategoryIdForMessageId(messageId: messageId)
        
        let category = UNNotificationCategory(identifier: categoryIdentifier, actions: actionArray as! [UNNotificationAction], intentIdentifiers: [],  options: .customDismissAction)
        
        CategoryHelper.registerCategory(category: category)
          
        bestAttemptContent.categoryIdentifier = categoryIdentifier
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

    fileprivate class func getCompletePictureUrl(_ pictureUrl: String) -> URL? {
        if (((pictureUrl as NSString).substring(with: NSRange(location: 0, length: 8))) == "https://") || (((pictureUrl as NSString).substring(with: NSRange(location: 0, length: 7))) == "http://") {
            return URL(string: pictureUrl)
        }

        let width = UIScreen.main.bounds.size.width
        let num = Int(floor(width))

        let completeString = String(format: "%@%@%ld%@%@", KS_MEDIA_RESIZER_BASE_URL, "/", num, "x/", pictureUrl)
        return URL(string: completeString)
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

    fileprivate static func trackDeliveredEvent(userInfo: [AnyHashable:Any], notificationId: Int) {
        let aps = userInfo["aps"] as! [AnyHashable:Any]
        if let contentAvailable = aps["content-available"] as? Int, contentAvailable == 1 {
            return
        }

        initializeAnalyticsHelper()
        guard let analyticsHelper = self.analyticsHelper else {
            return
        }
        
        let props: [String:Any] = ["type" : KS_MESSAGE_TYPE_PUSH, "id":notificationId]
        analyticsHelper.trackEvent(eventType: KumulosSharedEvent.MESSAGE_DELIVERED.rawValue, properties: props, immediateFlush: true)
    }
    
    fileprivate static func initializeAnalyticsHelper() {
        let apiKey = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.API_KEY.rawValue) as! String?
        let secretKey = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.SECRET_KEY.rawValue) as! String?
        if (apiKey == nil || secretKey == nil){
            print("Extension: authorization credentials not present")
            return;
        }
        
        analyticsHelper = AnalyticsHelper(apiKey: apiKey!, secretKey: secretKey!)
    }

}
