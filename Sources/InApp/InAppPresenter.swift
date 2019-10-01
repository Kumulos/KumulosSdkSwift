//
//  InAppPresenter.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import UIKit
import WebKit
import StoreKit
import UserNotifications

internal enum InAppAction : String {
    case CLOSE_MESSAGE = "closeMessage"
    case TRACK_EVENT = "trackConversionEvent"
    case PROMPT_PUSH_PERMISSION = "promptPushPermission"
    case SUBSCRIBE_CHANNEL = "subscribeToChannel"
    case OPEN_URL = "openUrl"
    case DEEP_LINK = "deepLink"
    case REQUEST_RATING = "requestAppStoreRating"
}

class InAppPresenter : NSObject, WKScriptMessageHandler, WKNavigationDelegate{
   
    private let messageQueueLock = DispatchSemaphore(value: 1)
    
    private let inAppRendererUrl : String = "https://iar.app.delivery"
    
    private var webView : WKWebView?
    private var loadingSpinner : UIActivityIndicatorView?
    private var frame : UIView?
    private var window : UIWindow?
    
    private var contentController : WKUserContentController?
    
    private var messageQueue : NSMutableOrderedSet
    private var pendingTickleIds : NSMutableOrderedSet

    private var currentMessage : InAppMessage?

    override init() {
        self.messageQueue = NSMutableOrderedSet.init(capacity: 5)
        self.pendingTickleIds = NSMutableOrderedSet.init(capacity: 2)
        self.currentMessage = nil

        super.init()
    }

    func queueMessagesForPresentation(messages: [InAppMessage], tickleIds: NSOrderedSet) {
        messageQueueLock.wait()
    
        if (messages.count == 0 && messageQueue.count == 0) {
            messageQueueLock.signal()
            return;
        }
        
        for message in messages {
            if messageQueue.contains(message) {
                continue
            }
            
            messageQueue.add(message)
        }

        
        for tickleId in tickleIds {
            if pendingTickleIds.contains(tickleId) {
                continue
            }
            pendingTickleIds.insert(tickleId, at: 0)

            messageQueue.sort { (a, b) -> ComparisonResult in
                guard let a = a as? InAppMessage, let b = b as? InAppMessage else {
                    return .orderedSame
                }

                let aIsTickle = self.pendingTickleIds.contains(a.id)
                let bIsTickle = self.pendingTickleIds.contains(b.id)

                if aIsTickle && !bIsTickle {
                    return .orderedAscending
                } else if !aIsTickle && bIsTickle {
                    return .orderedDescending
                } else if aIsTickle && bIsTickle {
                    let aIdx = self.pendingTickleIds.index(of: a.id)
                    let bIdx = self.pendingTickleIds.index(of: b.id)

                    if aIdx < bIdx {
                        return .orderedAscending
                    } else if aIdx > bIdx {
                        return .orderedDescending
                    }
                }

                return .orderedSame
            }
        }

        messageQueueLock.signal()
      
        DispatchQueue.main.async {
            self.initViews()
            
            if (self.currentMessage != nil
                && self.currentMessage!.id != (self.messageQueue[0] as! InAppMessage).id
                && (self.messageQueue[0] as! InAppMessage).id == self.pendingTickleIds[0] as! Int64) {
                self.presentFromQueue()
            }
        }
    }
    
    func presentFromQueue() -> Void {
        if (self.messageQueue.count == 0) {
            return;
        }
        
        if let loadingSpinner = self.loadingSpinner {
            loadingSpinner.performSelector(onMainThread: #selector(UIActivityIndicatorView.startAnimating), with: nil, waitUntilDone: true)
        }

        self.currentMessage = (self.messageQueue[0] as! InAppMessage)
        self.postClientMessage(type: "PRESENT_MESSAGE", data: self.currentMessage?.content)
    }

    func handleMessageClosed() -> Void {
        guard let message = currentMessage else  {
            return
        }

        if #available(iOS 10, *) {
            let tickleNotificationId = "k-in-app-message:\(message.id)"
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [tickleNotificationId])
        }
        
        messageQueueLock.wait()
        defer {
            messageQueueLock.signal()
        }
        
        messageQueue.removeObject(at: 0)
        pendingTickleIds.remove(message.id)
        currentMessage = nil
        
        if messageQueue.count == 0 {
            pendingTickleIds.removeAllObjects()
            self.destroyViews()
        }
        else {
            presentFromQueue()
        }
   }
    
    func cancelCurrentPresentationQueue(waitForViewCleanup: Bool) -> Void {
        messageQueueLock.wait()
        defer {
            messageQueueLock.signal()
        }
             
        self.messageQueue.removeAllObjects()
        self.pendingTickleIds.removeAllObjects()
        self.currentMessage = nil
      
        if Thread.isMainThread && waitForViewCleanup == true {
            self.destroyViews()
        }
        else if waitForViewCleanup == true {
            DispatchQueue.main.sync {
                self.destroyViews()
            }
        }
        else {
            DispatchQueue.main.async {
                self.destroyViews()
            }
        }
    }
    
    func initViews() {
        if window != nil {
            return
        }
        
        // Window / frame setup
        window = UIWindow.init(frame: UIScreen.main.bounds)
        window!.windowLevel = UIWindow.Level.alert
        window!.rootViewController = UIViewController()
                      
        if #available(iOS 13.0, *) {
            window?.windowScene = UIApplication.shared
                .connectedScenes
                .first as? UIWindowScene
        } else {
            // Fallback on earlier versions
        }
             
        let frame = UIView.init(frame: window!.frame)
        self.frame = frame

        frame.backgroundColor = .clear

        window!.isHidden = false
        window!.rootViewController!.view = frame
        
        // Webview
        self.contentController = WKUserContentController()
        self.contentController!.add(self, name: "inAppHost")
        
        let config = WKWebViewConfiguration()
        config.userContentController = self.contentController!
        config.allowsInlineMediaPlayback = true
                
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        } else {
            if #available(iOS 9.0, *) {
                config.requiresUserActionForMediaPlayback = false
            } else {
                config.mediaPlaybackRequiresUserAction = false
            }
        }

        #if DEBUG
            config.preferences.setValue(true, forKey:"developerExtrasEnabled")
        #endif

        let webView = WKWebView(frame: window!.frame, configuration: config)
        self.webView = webView

        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
        webView.backgroundColor = .clear;
        webView.scrollView.backgroundColor = .clear;
        webView.isOpaque = false;
        webView.navigationDelegate = self;
        webView.scrollView.bounces = false;
        webView.scrollView.isScrollEnabled = false;
        webView.allowsBackForwardNavigationGestures = false;
        
        if #available(iOS 9.0, *) {
            webView.allowsLinkPreview = false;
        }

        if #available(iOS 11.0.0, *) {
            // Allow content to pass under the notch / home button
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        }

        frame.addSubview(webView)
        
        let request = URLRequest(url: URL(string: inAppRendererUrl)!, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        webView.load(request)
        
        // Spinner
        let loadingSpinner = UIActivityIndicatorView(style: UIActivityIndicatorView.Style.gray)
        self.loadingSpinner = loadingSpinner
        
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = true
        loadingSpinner.hidesWhenStopped = true
        loadingSpinner.startAnimating()
        
        frame.addSubview(loadingSpinner)

        let horizontalConstraint = NSLayoutConstraint(item: loadingSpinner, attribute: .centerX, relatedBy: .equal, toItem: frame, attribute: .centerX, multiplier: 1, constant: 0)
        let verticalConstraint = NSLayoutConstraint(item: loadingSpinner, attribute: .centerY, relatedBy: .equal, toItem: frame, attribute: .centerY, multiplier: 1, constant: 0)
        
        frame.addConstraints([horizontalConstraint,verticalConstraint])
        frame.bringSubviewToFront(loadingSpinner)
    }

    func destroyViews() {
        if let window = self.window {
            window.isHidden = true
            
            if let spinner = self.loadingSpinner {
                spinner.removeFromSuperview()
                self.loadingSpinner = nil
            }
            
            if let webView = self.webView {
                webView.removeFromSuperview()
                self.webView = nil
            }
            
            if let frame = self.frame {
                frame.removeFromSuperview()
                self.frame = nil
            }
        }
        
        self.window = nil;
    }
  
    func postClientMessage(type: String, data: Any?) {
        guard let webView = self.webView else {
            return
        }
        
        do {
        
            let msg: [String: Any] = ["type" : type, "data" : data != nil ? data! : NSNull()]
            let json : Data = try JSONSerialization.data(withJSONObject: msg, options: JSONSerialization.WritingOptions(rawValue: 0))
            
            
            let jsonMsg = String(data: json, encoding: .utf8)
            let evalString = String(format: "postHostMessage(%@);", jsonMsg!)
          
            webView.evaluateJavaScript(evalString, completionHandler: nil)
        } catch {
            //Noop?
        }
      }
        
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
       if message.name != "inAppHost" {
           return;
       }
        
        var body = message.body as! NSDictionary
        var type = body["type"] as! String
        
        if (type == "READY") {
              messageQueueLock.wait()
              defer {
                  messageQueueLock.signal()
              }
                          
            self.presentFromQueue()
        }
       else if (type == "MESSAGE_OPENED") {
            loadingSpinner?.stopAnimating()
            Kumulos.sharedInstance.inAppHelper.trackMessageOpened(message: self.currentMessage!)
       } else if (type  == "MESSAGE_CLOSED") {
            self.handleMessageClosed()
       } else if (type == "EXECUTE_ACTIONS") {
            guard let body = message.body as? [AnyHashable:Any],
                  let data = body["data"] as? [AnyHashable:Any],
                  let actions = data["actions"] as? [NSDictionary] else {
                return
            }
            self.handleActions(actions: actions)
       } else {
           print("Unknown message: \(message.body)")
       }
   }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Noop
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.cancelCurrentPresentationQueue(waitForViewCleanup: false)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.cancelCurrentPresentationQueue(waitForViewCleanup: false)
    }

    func handleActions(actions: [NSDictionary]) -> Void  {
        if let message = self.currentMessage {
            
            var hasClose = false;
            var trackEvent : String?
            var subscribeToChannelUuid : String?
            var userAction : NSDictionary?
            
            for action in actions {
                let type = InAppAction(rawValue: action["type"] as! String)!
                let data = action["data"] as? [AnyHashable:Any]

                switch type {
                case .CLOSE_MESSAGE:
                    hasClose = true
                case .TRACK_EVENT:
                    trackEvent = data!["eventType"] as? String
                case .SUBSCRIBE_CHANNEL:
                    subscribeToChannelUuid = data!["channelUuid"] as? String
                default:
                    userAction = action
                }
            }

            if hasClose {
                Kumulos.sharedInstance.inAppHelper.markMessageDismissed(message: message)
                self.postClientMessage(type: "CLOSE_MESSAGE", data: nil)
            }

            if let trackEvent = trackEvent {
                Kumulos.trackEvent(eventType: trackEvent, properties: [:]);
            }

            if let subscribeToChannelUuid = subscribeToChannelUuid {
                let psm = KumulosPushChannels(sdkInstance: Kumulos.sharedInstance)
                _ = psm.subscribe(uuids: [subscribeToChannelUuid])
            }

            if (userAction != nil) {
                self.handleUserAction(userAction: userAction!)
                self.cancelCurrentPresentationQueue(waitForViewCleanup: true)
            }
        }
    }

    func handleUserAction(userAction: NSDictionary) -> Void {
        let type = userAction["type"] as! String
                
        if (type == InAppAction.PROMPT_PUSH_PERMISSION.rawValue) {
            Kumulos.pushRequestDeviceToken()
        } else if (type == InAppAction.DEEP_LINK.rawValue) {
            if (Kumulos.sharedInstance.config.inAppDeepLinkHandlerBlock == nil) {
                return;
            }
            DispatchQueue.main.async {
                let data = userAction.value(forKeyPath: "data.deepLink") as? [AnyHashable:Any] ?? [:]
                Kumulos.sharedInstance.config.inAppDeepLinkHandlerBlock?(data)
            }
        } else if (type == InAppAction.OPEN_URL.rawValue) {
            guard let url = URL(string: userAction.value(forKeyPath: "data.url") as! String) else {
                return
            }

            if #available(iOS 10.0.0, *) {
                UIApplication.shared.open(url, options: [:]) { (win) in
                    // noop
                }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.openURL(url)
                }
            }
        } else if (type == InAppAction.REQUEST_RATING.rawValue) {
            if #available(iOS 10.3.0, *) {
                SKStoreReviewController.requestReview()
            } else {
                NSLog("Requesting a rating not supported on this iOS version");
            }
        }
    }
    
}
