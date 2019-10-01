//
//  KSUserNotificationCenterDelegate.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation
import UserNotifications

@available(iOS 10.0, *)
class KSUserNotificationCenterDelegate : NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if (Kumulos.sharedInstance.config.pushReceivedInForegroundHandlerBlock != nil) {
            let push = KSPushNotification.init(userInfo: notification.request.content.userInfo)
            Kumulos.sharedInstance.config.pushReceivedInForegroundHandlerBlock?(push, completionHandler);
        }
        else {
            completionHandler(.alert)
       }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if (response.actionIdentifier == UNNotificationDismissActionIdentifier) {
            completionHandler()
            return
        }

        let userInfo = response.notification.request.content.userInfo
        Kumulos.sharedInstance.pushHandleOpen(withUserInfo: userInfo)

        completionHandler()
    }

}
