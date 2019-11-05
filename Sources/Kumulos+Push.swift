//
//  Kumulos+Push.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation
import UserNotifications
import ObjectiveC.runtime

internal let KS_MESSAGE_TYPE_PUSH = 1

public class KSPushNotification: NSObject {
    internal static let DeepLinkTypeInApp : Int = 1;

    internal(set) open var id: Int
    internal(set) open var aps: [AnyHashable:Any]
    internal(set) open var data : [AnyHashable:Any]
    internal(set) open var url: URL?

    init(userInfo: [AnyHashable:Any]) {
        let custom = userInfo["custom"] as! [AnyHashable:Any]
        data = custom["a"] as! [AnyHashable:Any]

        let msg = data["k.message"] as! [AnyHashable:Any]
        let msgData = msg["data"] as! [AnyHashable:Any]
        
        id = msgData["id"] as! Int
        aps = userInfo["aps"] as! [AnyHashable:Any]

        if let urlStr = custom["u"] as? String {
            url = URL(string: urlStr)
        } else {
            url = nil
        }
    }

    public func inAppDeepLink() -> [AnyHashable:Any]?  {
        guard let deepLink = data["k.deepLink"] as? [AnyHashable:Any] else {
            return nil
        }

        if deepLink["type"] as? Int != KSPushNotification.DeepLinkTypeInApp {
            return nil
        }

        return deepLink
    }
}

public extension Kumulos {
    
    internal static let KS_MEDIA_RESIZER_BASE_URL = "https://i.app.delivery"
    /**
        Helper method for requesting the device token with alert, badge and sound permissions.

        On success will raise the didRegisterForRemoteNotificationsWithDeviceToken UIApplication event
    */
    static func pushRequestDeviceToken() {
        if #available(iOS 10.0, *) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
                // actions based on whether notifications were authorized or not
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } else {
            DispatchQueue.main.async {
                requestTokenLegacy()
            }
        }
    }

    private static func requestTokenLegacy() {
         // Determine the type of notifications we want to ask permission for, for example we may want to alert the user, update the badge number and play a sound
         let notificationTypes: UIUserNotificationType = [UIUserNotificationType.alert, UIUserNotificationType.badge, UIUserNotificationType.sound]

         // Create settings  based on those notification types we want the user to accept
         let pushNotificationSettings = UIUserNotificationSettings(types: notificationTypes, categories: nil)

         // Get the main application
         let application = UIApplication.shared

         // Register the settings created above - will show alert first if the user hasn't previously done this
         // See delegate methods in AppDelegate - the AppDelegate conforms to the UIApplicationDelegate protocol
         application.registerUserNotificationSettings(pushNotificationSettings)
         application.registerForRemoteNotifications()
    }

    /**
        Register a device token with the Kumulos Push service

        Parameters:
            - deviceToken: The push token returned by the device
    */
    static func pushRegister(_ deviceToken: Data) {
        let token = serializeDeviceToken(deviceToken)
        let iosTokenType = getTokenType()

        let parameters = ["token" : token, "type" : sharedInstance.pushNotificationDeviceType, "iosTokenType" : iosTokenType] as [String : Any]
        
        Kumulos.trackEvent(eventType: KumulosEvent.PUSH_DEVICE_REGISTER, properties: parameters as [String : AnyObject], immediateFlush: true)
    }
    
    /**
        Unsubscribe your device from the Kumulos Push service
    */
    static func pushUnregister() {
        Kumulos.trackEvent(eventType: KumulosEvent.DEVICE_UNSUBSCRIBED, properties: [:], immediateFlush: true)
    }
 
    /**
        Track a user action triggered by a push notification

        Parameters:
            - notification: The notification which triggered the action
    */
    static func pushTrackOpen(notification: KSPushNotification?) {
        guard let notification = notification else {
            return
        }

        let params = ["type": KS_MESSAGE_TYPE_PUSH, "id": notification.id]
        Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_OPENED, properties:params)
    }

    internal func pushHandleOpen(withUserInfo: [AnyHashable: Any]?) {
        guard let userInfo = withUserInfo else {
            return
        }

        let notification = KSPushNotification(userInfo: userInfo)
        Kumulos.pushTrackOpen(notification: notification)

        // Handle URL pushes

        if let url = notification.url {
            if #available(iOS 10, *) {
                UIApplication.shared.open(url, options: [:]) { (success) in
                    // noop
                }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.openURL(url)
                }
            }
        }

        self.inAppHelper.handlePushOpen(notification: notification)

        if let userOpenedHandler = self.config.pushOpenedHandlerBlock {
            DispatchQueue.main.async {
                userOpenedHandler(notification)
            }
        }
    }

    fileprivate static func serializeDeviceToken(_ deviceToken: Data) -> String {
        var token: String = ""
        for i in 0..<deviceToken.count {
            token += String(format: "%02.2hhx", deviceToken[i] as CVarArg)
        }

        return token
    }

    fileprivate static func getTokenType() -> Int {
        let releaseMode = MobileProvision.releaseMode()
        
        if let index =  [
            UIApplicationReleaseMode.adHoc,
            UIApplicationReleaseMode.dev,
            UIApplicationReleaseMode.wildcard
            ].firstIndex(of: releaseMode), index > -1 {
            return releaseMode.rawValue + 1;
        }
        
        return Kumulos.sharedInstance.pushNotificationProductionTokenType
    }
    
    //MARK: Notification Service Extension
    
    @available(iOS 10.0, *)
    class func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let bestAttemptContent =  (request.content.mutableCopy() as! UNMutableNotificationContent)

        let userInfo = request.content.userInfo
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

    @available(iOS 10.0, *)
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

// MARK: Swizzling

fileprivate var existingDidReg : IMP?
fileprivate var existingDidFailToReg : IMP?
fileprivate var existingDidReceive : IMP?

class PushHelper {

    typealias kumulos_applicationDidRegisterForRemoteNotifications = @convention(c) (_ obj:UIApplicationDelegate, _ _cmd:Selector, _ application:UIApplication, _ deviceToken:Data) -> Void
    typealias didRegBlock = @convention(block) (_ obj:UIApplicationDelegate, _ application:UIApplication, _ deviceToken:Data) -> Void

    typealias kumulos_applicationDidFailToRegisterForRemoteNotificaitons = @convention(c) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ error:Error) -> Void
    typealias didFailToRegBlock = @convention(block) (_ obj:Any, _ application:UIApplication, _ error:Error) -> Void

    typealias kumulos_applicationDidReceiveRemoteNotificationFetchCompletionHandler = @convention(c) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ userInfo: [AnyHashable : Any], _ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void
    typealias didReceiveBlock = @convention(block) (_ obj:Any, _ application:UIApplication, _ userInfo: [AnyHashable : Any], _ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void

    lazy var pushInit:Void = {
        let klass : AnyClass = type(of: UIApplication.shared.delegate!)

        // Did register push delegate
        let didRegisterSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let meth = class_getInstanceMethod(klass, didRegisterSelector)
        let regType = NSString(string: "v@:@@").utf8String
        let regBlock : didRegBlock = { (obj:UIApplicationDelegate, application:UIApplication, deviceToken:Data) -> Void in
            if let _ = existingDidReg {
                unsafeBitCast(existingDidReg, to: kumulos_applicationDidRegisterForRemoteNotifications.self)(obj, didRegisterSelector, application, deviceToken)
            }

            Kumulos.pushRegister(deviceToken)
        }
        let kumulosDidRegister = imp_implementationWithBlock(regBlock as Any)
        existingDidReg = class_replaceMethod(klass, didRegisterSelector, kumulosDidRegister, regType)

        // Failed to register handler
        let didFailToRegisterSelector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        let didFailToRegType = NSString(string: "v@:@@").utf8String
        let didFailToRegBlock : didFailToRegBlock = { (obj:Any, application:UIApplication, error:Error) -> Void in
            if let _ = existingDidFailToReg {
                unsafeBitCast(existingDidFailToReg, to: kumulos_applicationDidFailToRegisterForRemoteNotificaitons.self)(obj, didFailToRegisterSelector, application, error)
            }

            print("Failed to register for remote notifications: \(error)")
        }
        let kumulosDidFailToRegister = imp_implementationWithBlock(didFailToRegBlock as Any)
        existingDidFailToReg = class_replaceMethod(klass, didFailToRegisterSelector, kumulosDidFailToRegister, didFailToRegType)

        // iOS9 did receive remote delegate
        // iOS9+ content-available handler
        let didReceiveSelector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
        let receiveType = NSString(string: "v@:@@@?").utf8String
        let didReceive : didReceiveBlock = { (obj:Any, _ application: UIApplication, userInfo: [AnyHashable : Any], completionHandler: @escaping (UIBackgroundFetchResult) -> Void) in
            var fetchResult : UIBackgroundFetchResult = .noData
            let fetchBarrier = DispatchSemaphore(value: 0)

            if let _ = existingDidReceive {
                unsafeBitCast(existingDidReceive, to: kumulos_applicationDidReceiveRemoteNotificationFetchCompletionHandler.self)(obj, didReceiveSelector, application, userInfo, { (result : UIBackgroundFetchResult) in
                    fetchResult = result
                    fetchBarrier.signal()
                })
            } else {
                fetchBarrier.signal()
            }

            if UIApplication.shared.applicationState == .inactive {
                if #available(iOS 10, *) {
                    // Noop (tap handler in delegate will deal with opening the URL)
                } else {
                    Kumulos.sharedInstance.pushHandleOpen(withUserInfo:userInfo)
                }
            }

            let aps = userInfo["aps"] as! [AnyHashable:Any]
            guard let contentAvailable = aps["content-available"] as? Int, contentAvailable == 1 else {
                completionHandler(fetchResult)
                return
            }

            Kumulos.sharedInstance.inAppHelper.sync { (result:Int) in
                _ = fetchBarrier.wait(timeout: DispatchTime.now() + DispatchTimeInterval.seconds(20))

                if result < 0 {
                    fetchResult = .failed
                } else if result > 1 {
                    fetchResult = .newData
                }
                // No data case is default, allow override from other handler

                completionHandler(fetchResult)
            }
        }
        let kumulosDidReceive = imp_implementationWithBlock(unsafeBitCast(didReceive, to: AnyObject.self))
        existingDidReceive = class_replaceMethod(klass, didReceiveSelector, kumulosDidReceive, receiveType)

        if #available(iOS 10, *) {
            let delegate = KSUserNotificationCenterDelegate()
            
            Kumulos.sharedInstance.notificationCenter = delegate
            UNUserNotificationCenter.current().delegate = delegate
        }
    }()
}
