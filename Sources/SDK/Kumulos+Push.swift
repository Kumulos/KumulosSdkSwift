//
//  Kumulos+Push.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation
import UserNotifications
import ObjectiveC.runtime

public class KSPushNotification: NSObject {
    internal static let DeepLinkTypeInApp : Int = 1;

    internal(set) open var id: Int
    internal(set) open var aps: [AnyHashable:Any]
    internal(set) open var data : [AnyHashable:Any]
    internal(set) open var url: URL?
    internal(set) open var actionIdentifier: String?

    init(userInfo: [AnyHashable:Any]?) {
        self.id = 0
        self.aps = [:]
        self.data = [:]

        guard let userInfo = userInfo else {
            return
        }

        guard let aps = userInfo["aps"] as? [AnyHashable:Any] else {
            return
        }

        self.aps = aps

        guard let custom = userInfo["custom"] as? [AnyHashable:Any] else {
            return
        }

        guard let data = custom["a"] as? [AnyHashable:Any] else {
            return
        }

        self.data = data

        guard let msg = data["k.message"] as? [AnyHashable:Any] else {
            return
        }

        let msgData = msg["data"] as! [AnyHashable:Any]

        id = msgData["id"] as! Int

        if let urlStr = custom["u"] as? String {
            url = URL(string: urlStr)
        } else {
            url = nil
        }
    }
    
    @available(iOS 10.0, *)
    convenience init(userInfo: [AnyHashable:Any]?, response: UNNotificationResponse?) {
        self.init(userInfo: userInfo)

        if let notificationResponse = response {
            if (notificationResponse.actionIdentifier != UNNotificationDefaultActionIdentifier) {
                actionIdentifier = notificationResponse.actionIdentifier
            }
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

@available(iOS 10.0, *)
public typealias KSUNAuthorizationCheckedHandler = (UNAuthorizationStatus, Error?) -> Void

public extension Kumulos {

    /**
        Helper method for requesting the device token with alert, badge and sound permissions.

        On success will raise the didRegisterForRemoteNotificationsWithDeviceToken UIApplication event
    */
    @available(iOS 10.0, *)
    static func pushRequestDeviceToken(_ onAuthorizationStatus: KSUNAuthorizationCheckedHandler? = nil) {
        requestToken(onAuthorizationStatus)
    }

    /**
        Helper method for requesting the device token with alert, badge and sound permissions.

        On success will raise the didRegisterForRemoteNotificationsWithDeviceToken UIApplication event
    */
    static func pushRequestDeviceToken() {
        if #available(iOS 10.0, *) {
            requestToken()
        } else {
            DispatchQueue.main.async {
                requestTokenLegacy()
            }
        }
    }

    @available(iOS 10.0, *)
    fileprivate static func requestToken(_ onAuthorizationStatus: KSUNAuthorizationCheckedHandler? = nil) {
        let center = UNUserNotificationCenter.current()

        let requestToken : () -> Void = {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        let askPermission : () -> Void = {
            DispatchQueue.main.async {
                if UIApplication.shared.applicationState == .background {
                    onAuthorizationStatus?(.notDetermined,
                                           NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Application not active, aborting push permission request"]) as Error)
                    return
                }

                center.requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
                    if let err = error {
                        onAuthorizationStatus?(.notDetermined, err)
                        return
                    }

                    if (!granted) {
                        onAuthorizationStatus?(.denied, nil)
                        return
                    }

                    onAuthorizationStatus?(.authorized, nil)
                    requestToken()
                }
            }
        }

        center.getNotificationSettings { (settings) in
            switch settings.authorizationStatus {
            case .denied:
                onAuthorizationStatus?(settings.authorizationStatus, nil)
                return
            case .authorized:
                onAuthorizationStatus?(settings.authorizationStatus, nil)
                requestToken()
                break
            default:
                askPermission()
                break
            }
        }
    }

    @available(iOS, deprecated: 10.0)
    fileprivate static func requestTokenLegacy() {
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

        let bundleId = Bundle.main.infoDictionary!["CFBundleIdentifier"] as Any
        let parameters = ["token" : token,
                          "type" : sharedInstance.pushNotificationDeviceType,
                          "iosTokenType" : iosTokenType,
                          "bundleId": bundleId] as [String : Any]
        
        Kumulos.trackEvent(eventType: KumulosEvent.PUSH_DEVICE_REGISTER, properties: parameters as [String : AnyObject], immediateFlush: true)
    }
    
    /**
        Unsubscribe your device from the Kumulos Push service
    */
    static func pushUnregister() {
        Kumulos.trackEvent(eventType: KumulosEvent.DEVICE_UNSUBSCRIBED, properties: [:], immediateFlush: true)
    }
 
// MARK: Open handling
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
    
    @available(iOS 9.0, *)
    internal func pushHandleOpen(withUserInfo: [AnyHashable: Any]?) {
        guard let userInfo = withUserInfo else {
            return
        }

        let notification = KSPushNotification(userInfo: userInfo)
        if notification.id == 0 {
            return
        }

        self.pushHandleOpen(notification: notification)
    }
  
    @available(iOS 10.0, *)
    internal func pushHandleOpen(withUserInfo: [AnyHashable: Any]?, response: UNNotificationResponse?) -> Bool {
        let notification = KSPushNotification(userInfo: withUserInfo, response: response)

        if notification.id == 0 {
            return false
        }

        self.pushHandleOpen(notification: notification)
        
        PendingNotificationHelper.remove(id: notification.id)
       
        return true
    }
    
    private func pushHandleOpen(notification: KSPushNotification) {
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

// MARK: Dismissed handling
    @available(iOS 10.0, *)
    internal func pushHandleDismissed(withUserInfo: [AnyHashable: Any]?, response: UNNotificationResponse?) -> Bool {
        let notification = KSPushNotification(userInfo: withUserInfo, response: response)

        if notification.id == 0 {
            return false
        }

        self.pushHandleDismissed(notificationId: notification.id)

        return true
    }
    
    @available(iOS 10.0, *)
    private func pushHandleDismissed(notificationId: Int, dismissedAt: Date? = nil) {
        PendingNotificationHelper.remove(id: notificationId)
        self.pushTrackDismissed(notificationId: notificationId, dismissedAt: dismissedAt)
    }
    
    @available(iOS 10.0, *)
    private func pushTrackDismissed(notificationId: Int, dismissedAt: Date? = nil) {
        let params = ["type": KS_MESSAGE_TYPE_PUSH, "id": notificationId]
              
        if let unwrappedDismissedAt = dismissedAt {
            Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_DISMISSED.rawValue, atTime: unwrappedDismissedAt, properties:params)
        }
        else{
            Kumulos.trackEvent(eventType: KumulosEvent.MESSAGE_DISMISSED, properties:params)
        }
    }
    
    @available(iOS 10.0, *)
    internal func maybeTrackPushDismissedEvents() {
        if (!AppGroupsHelper.isKumulosAppGroupDefined()){
            return;
        }
        
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications: [UNNotification]) in
            var actualPendingNotificationIds: [Int] = []
            for notification in notifications {
                let notification = KSPushNotification(userInfo: notification.request.content.userInfo)
                if (notification.id == 0){
                    continue
                }
                
                actualPendingNotificationIds.append(notification.id)
            }
            
            let recordedPendingNotifications = PendingNotificationHelper.readAll()
           
            let deletions = recordedPendingNotifications.filter({ !actualPendingNotificationIds.contains( $0.id ) })
            for deletion in deletions {
                self.pushHandleDismissed(notificationId: deletion.id, dismissedAt: deletion.deliveredAt)
            }
            
        }
    }
    
// MARK: Token handling
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
                if #available(iOS 10, *) {} else {
                    self.setBadge(userInfo: userInfo)
                    self.trackPushDelivery(userInfo: userInfo)
                }
                
                completionHandler(fetchResult)
                return
            }
          
            self.setBadge(userInfo: userInfo)
            self.trackPushDelivery(userInfo: userInfo)
            
            Kumulos.sharedInstance.inAppHelper.sync { (result:Int) in
                _ = fetchBarrier.wait(timeout: DispatchTime.now() + DispatchTimeInterval.seconds(20))

                if result < 0 {
                    fetchResult = .failed
                } else if result > 0 {
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
    
    fileprivate func setBadge(userInfo: [AnyHashable:Any]){
        let badge: NSNumber? = KumulosHelper.getBadgeFromUserInfo(userInfo: userInfo)
        if let newBadge = badge {
            UIApplication.shared.applicationIconBadgeNumber = newBadge.intValue
        }
    }
    
    fileprivate func trackPushDelivery(userInfo: [AnyHashable : Any]){
        let notification = KSPushNotification(userInfo: userInfo)
        if (notification.id == 0) {
            return
        }
        
        let props: [String:Any] = ["type" : KS_MESSAGE_TYPE_PUSH, "id": notification.id]
        Kumulos.trackEvent(eventType: KumulosSharedEvent.MESSAGE_DELIVERED, properties:props, immediateFlush: true)
    }
}
