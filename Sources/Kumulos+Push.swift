//
//  Kumulos+Push.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation
import Alamofire
import UserNotifications

public extension Kumulos{

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
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            requestTokenLegacy()
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
    static func pushTrackOpen(notification: [AnyHashable: Any]) {
        if let custom = notification["custom"] as? [String:AnyObject], let id = custom["i"]
        {
            let parameters = ["id" : id]
            Kumulos.trackEvent(eventType: KumulosEvent.PUSH_OPEN_TRACK, properties: parameters, immediateFlush: true)
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
            ].index(of: releaseMode), index > -1 {
            return releaseMode.rawValue + 1;
        }
        
        return Kumulos.sharedInstance.pushNotificationProductionTokenType
    }
}
