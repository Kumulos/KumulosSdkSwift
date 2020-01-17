//
//  KSUserNotificationCenterDelegate.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation
import UserNotifications

class KSUserNotificationCenterDelegate : NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if (Kumulos.sharedInstance.config.pushReceivedInForegroundHandlerBlock != nil) {
            let push = KSPushNotification.init(userInfo: notification.request.content.userInfo, response: nil)
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
        Kumulos.sharedInstance.pushHandleOpen(withUserInfo: userInfo, response: response)

        completionHandler()
    }
}
