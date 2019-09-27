//
//  Kumulos+Push.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation
import UserNotifications

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


typealias kumulos_applicationDidRegisterForRemoteNotifications = @convention(c) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ deviceToken:Data) -> Void
typealias didRegBlock = @convention(block) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ deviceToken:Data) -> Void
typealias kumulos_applicationDidFailToRegisterForRemoteNotificaitons = @convention(c) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ error:Error) -> Void
typealias didFailToRegBlock = @convention(block) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ error:Error) -> Void
typealias kumulos_applicationDidReceiveRemoteNotificationFetchCompletionHandler = @convention(c) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ userInfo: [AnyHashable : Any], _ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void
typealias didReceiveBlock = @convention(block) (_ obj:Any, _ _cmd:Selector, _ application:UIApplication, _ userInfo: [AnyHashable : Any], _ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Void

fileprivate var existingDidReg : IMP?
fileprivate var existingDidFailToReg : IMP?
fileprivate var existingDidReceive : IMP?

class PushHelper {

    let pushInit:Void = {
        let klass : AnyClass = type(of: UIApplication.shared.delegate!)

        // Did register push delegate
        let didRegisterSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let regType = NSString(string: "v@:@@").utf8String
        let regBlock : didRegBlock = { (obj:Any, _cmd:Selector, application:UIApplication, deviceToken:Data) -> Void in
            if let _ = existingDidReg {
                unsafeBitCast(existingDidReg, to: kumulos_applicationDidRegisterForRemoteNotifications.self)(obj, _cmd, application, deviceToken)
            }

            Kumulos.pushRegister(deviceToken)
        }
        let kumulosDidRegister = imp_implementationWithBlock(unsafeBitCast(regBlock, to: AnyObject.self))
        existingDidReg = class_replaceMethod(klass, didRegisterSelector, kumulosDidRegister, regType)

        // Failed to register handler
        let didFailToRegisterSelector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        let didFailToRegType = NSString(string: "v@:@@").utf8String
        let didFailToRegBlock : didFailToRegBlock = { (obj:Any, _cmd:Selector, application:UIApplication, error:Error) -> Void in
            if let _ = existingDidFailToReg {
                unsafeBitCast(existingDidFailToReg, to: kumulos_applicationDidFailToRegisterForRemoteNotificaitons.self)(obj, _cmd, application, error)
            }

            print("Failed to register for remote notifications: \(error)")
        }
        let kumulosDidFailToRegister = imp_implementationWithBlock(unsafeBitCast(didFailToRegBlock, to: AnyObject.self))
        existingDidFailToReg = class_replaceMethod(klass, didFailToRegisterSelector, kumulosDidFailToRegister, didFailToRegType)

        // iOS9 did receive remote delegate
        // iOS9+ content-available handler
        let didReceiveSelector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
        let receiveType = NSString(string: "v@:@@@?").utf8String
        let didReceive : didReceiveBlock = { (obj:Any, _cmd:Selector, _ application: UIApplication, userInfo: [AnyHashable : Any], completionHandler: @escaping (UIBackgroundFetchResult) -> Void) in
            var fetchResult : UIBackgroundFetchResult = .noData
            let fetchBarrier = DispatchSemaphore(value: 0)

            if let _ = existingDidReceive {
                unsafeBitCast(existingDidReceive, to: kumulos_applicationDidReceiveRemoteNotificationFetchCompletionHandler.self)(obj, _cmd, application, userInfo, { (result : UIBackgroundFetchResult) in
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
            guard let contentAvailable = aps["content-available"] as? Int, contentAvailable != 1 else {
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
            let notificationCenterDelegate = KSUserNotificationCenterDelegate()
            UNUserNotificationCenter.current().delegate = notificationCenterDelegate
        }
    }()
}

public extension Kumulos {

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
}
