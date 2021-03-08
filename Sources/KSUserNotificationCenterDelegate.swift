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

    let existingDelegate: UNUserNotificationCenterDelegate?

    override init() {
        self.existingDelegate = UNUserNotificationCenter.current().delegate
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let push = KSPushNotification.init(userInfo: notification.request.content.userInfo, response: nil)

        if push.id == 0 {
            chainCenter(center, willPresent: notification, with: completionHandler)
            return
        }

        if (Kumulos.sharedInstance.config.pushReceivedInForegroundHandlerBlock == nil) {
            completionHandler(.alert)
            return
        }

        Kumulos.sharedInstance.config.pushReceivedInForegroundHandlerBlock?(push, completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        if userInfo["aps"] == nil {
            chainCenter(center, didReceive: response, with: completionHandler)
            return
        }

        if (response.actionIdentifier == UNNotificationDismissActionIdentifier) {
            let handled = Kumulos.sharedInstance.pushHandleDismissed(withUserInfo: userInfo, response: response)
            if (!handled) {
                chainCenter(center, didReceive: response, with: completionHandler)
                return
            }
            
            completionHandler()
            return
        }

        let handled = Kumulos.sharedInstance.pushHandleOpen(withUserInfo: userInfo, response: response)

        if (!handled) {
            chainCenter(center, didReceive: response, with: completionHandler)
            return
        }

        completionHandler()
    }

    fileprivate func chainCenter(_ center: UNUserNotificationCenter, willPresent notification : UNNotification, with completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if self.existingDelegate != nil && self.existingDelegate?.responds(to: #selector(userNotificationCenter(_:willPresent:withCompletionHandler:))) == true {
            self.existingDelegate?.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            return
        }

        completionHandler(.alert)
    }

    fileprivate func chainCenter(_ center:UNUserNotificationCenter, didReceive notificationResponse:UNNotificationResponse, with completionHandler: @escaping () -> Void) {
        if self.existingDelegate != nil && self.existingDelegate?.responds(to: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:))) == true {
            self.existingDelegate?.userNotificationCenter?(center, didReceive: notificationResponse, withCompletionHandler: completionHandler)
            return
        }

        completionHandler();
    }
}
