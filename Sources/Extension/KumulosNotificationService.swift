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

    public class func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let bestAttemptContent =  (request.content.mutableCopy() as! UNMutableNotificationContent)

        let userInfo = request.content.userInfo
        
        let custom = userInfo["custom"] as! [AnyHashable:Any]
        let data = custom["a"] as! [AnyHashable:Any]
        
        let msg = data["k.message"] as! [AnyHashable:Any]
        let msgData = msg["data"] as! [AnyHashable:Any]
        let id = msgData["id"] as! Int
        
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

    class func addButtons(messageId: Int, bestAttemptContent: UNMutableNotificationContent, buttons: NSArray) {
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
    
    class func getPictureExtension(_ pictureUrl: String?) -> String? {
        if (pictureUrl == nil){
            return nil;
        }
        let pictureExtension = URL(fileURLWithPath: pictureUrl!).pathExtension
        if (pictureExtension == "") {
            return nil
        }

        return "." + (pictureExtension)
    }

    class func getCompletePictureUrl(_ pictureUrl: String) -> URL? {
        if (((pictureUrl as NSString).substring(with: NSRange(location: 0, length: 8))) == "https://") || (((pictureUrl as NSString).substring(with: NSRange(location: 0, length: 7))) == "http://") {
            return URL(string: pictureUrl)
        }

        let width = UIScreen.main.bounds.size.width
        let num = Int(floor(width))

        let completeString = String(format: "%@%@%ld%@%@", KS_MEDIA_RESIZER_BASE_URL, "/", num, "x/", pictureUrl)
        return URL(string: completeString)
    }

    class func loadAttachment(_ url: URL, withExtension pictureExtension: String?, completionHandler: @escaping (UNNotificationAttachment?) -> Void) {
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
}
