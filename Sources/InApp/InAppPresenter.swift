//
//  InAppPresenter.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import UIKit
import WebKit
import StoreKit

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
    
    private var inAppRendererUrl : String = "https://iar.app.delivery"
    
    private var kumulos : Kumulos
    private var webView : WKWebView?
    private var loadingSpinner : UIActivityIndicatorView?
    private var frame : UIView?
    private var window : UIWindow?
    
    private var contentController : WKUserContentController
    
    // TODO - how to init this properly?
    private var messageQueue : NSMutableOrderedSet
    private var pendingTickleIds : NSMutableOrderedSet

    private var currentMessage : InAppMessage?

    init(kumulos: Kumulos) {
        super.init()
        
        self.kumulos = kumulos
        
        self.messageQueue = NSMutableOrderedSet.init(capacity: 5)
        self.pendingTickleIds = NSMutableOrderedSet.init(capacity: 2)
        self.currentMessage = nil
    }
    

   /*func queueMessagesForPresentation:(NSArray<KSInAppMessage*>*)messages presentingTickles:(NSOrderedSet<NSNumber*>*)tickleIds {
        @synchronized (self.messageQueue) {
            if (!messages.count && !self.messageQueue.count) {
                return;
            }

            for (KSInAppMessage* message in messages) {
                if ([self.messageQueue containsObject:message]) {
                    continue;
                }

                [self.messageQueue addObject:message];
            }

            if (tickleIds != nil && tickleIds.count > 0) {
                for (NSNumber* tickleId in tickleIds) {
                    if ([self.pendingTickleIds containsObject:tickleId]) {
                        continue;
                    }

                    [self.pendingTickleIds insertObject:tickleId atIndex:0];
                }

                [self.messageQueue sortUsingComparator:^NSComparisonResult(KSInAppMessage* _Nonnull a, KSInAppMessage* _Nonnull b) {
                    BOOL aIsTickle = [self.pendingTickleIds containsObject:a.id];
                    BOOL bIsTickle = [self.pendingTickleIds containsObject:b.id];

                    if (aIsTickle && !bIsTickle) {
                        return NSOrderedAscending;
                    } else if (!aIsTickle && bIsTickle) {
                        return NSOrderedDescending;
                    } else if (aIsTickle && bIsTickle) {
                        NSUInteger aIdx = [self.pendingTickleIds indexOfObject: a.id];
                        NSUInteger bIdx = [self.pendingTickleIds indexOfObject: b.id];

                        if (aIdx < bIdx) {
                            return NSOrderedAscending;
                        } else if (aIdx > bIdx) {
                            return NSOrderedDescending;
                        }
                    }

                    return NSOrderedSame;
                }];
            }
        }

        [self performSelectorOnMainThread:@selector(initViews) withObject:nil waitUntilDone:YES];

        if (self.currentMessage
            && ![self.currentMessage.id isEqualToNumber:self.messageQueue[0].id]
            && [self.messageQueue[0].id isEqualToNumber:self.pendingTickleIds[0]]) {
            [self presentFromQueue];
        }
    }*/
    
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
       /* @synchronized (self.messageQueue) {
            [self.messageQueue removeObjectAtIndex:0];
            [self.pendingTickleIds removeObject:self.currentMessage.id];
            self.currentMessage = nil;

            if (!self.messageQueue.count) {
                [self.pendingTickleIds removeAllObjects];
                [self performSelectorOnMainThread:@selector(destroyViews) withObject:nil waitUntilDone:YES];
            } else {
                [self presentFromQueue];
            }
        }

        if (@available(iOS 10, *)) {
            NSString* tickleNotificationId = [NSString stringWithFormat:@"k-in-app-message:%@", self.currentMessage.id];
            [UNUserNotificationCenter.currentNotificationCenter removeDeliveredNotificationsWithIdentifiers:@[tickleNotificationId]];
        }*/
    }
    
    func cancelCurrentPresentationQueue(waitForViewCleanup: Bool) -> Void {
        messageQueueLock.wait()
        defer {
            messageQueueLock.signal()
        }
             
        self.messageQueue.removeAllObjects()
        self.pendingTickleIds.removeAllObjects()
        self.currentMessage = nil
      
        if waitForViewCleanup == true {
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
        guard var window = self.window else {
            return;
        }
        
        // Window / frame setup
        window = UIWindow.init(frame: UIScreen.main.bounds)
        window.windowLevel = UIWindow.Level.alert
        window.rootViewController = UIViewController()
        
        let frame = UIView.init(frame: window.frame)
        self.frame = frame
        
        frame.backgroundColor = UIColor.clear
        
        window.rootViewController!.view = frame
        window.isHidden = false

        // Webview
        self.contentController = WKUserContentController()
        self.contentController.add(self, name: "inAppHost")
        
        let config = WKWebViewConfiguration()
        config.userContentController = self.contentController
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
/*
    #ifdef DEBUG
        [config.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
    #endif

        self.webView = [[WKWebView alloc] initWithFrame:self.frame.frame configuration:config];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.backgroundColor = UIColor.clearColor;
        self.webView.scrollView.backgroundColor = UIColor.clearColor;
        self.webView.opaque = NO;
        self.webView.navigationDelegate = self;
        self.webView.scrollView.bounces = NO;
        self.webView.scrollView.scrollEnabled = NO;
        self.webView.allowsBackForwardNavigationGestures = NO;
        if (@available(iOS 9.0, *)) {
            self.webView.allowsLinkPreview = NO;
        }

        if (@available(iOS 11.0.0, *)) {
            // Allow content to pass under the notch / home button
            [self.webView.scrollView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
        }

        [self.frame addSubview:self.webView];

        NSURLRequest* req = [NSURLRequest requestWithURL:[NSURL URLWithString:KSInAppRendererUrl] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:30];
        [self.webView loadRequest:req];*/

        // Spinner
        let loadingSpinner = UIActivityIndicatorView(style: UIActivityIndicatorView.Style.gray)
        self.loadingSpinner = loadingSpinner
        
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = true
        loadingSpinner.hidesWhenStopped = true
        loadingSpinner.startAnimating()
        
        frame.addSubview(loadingSpinner)

        /*NSLayoutConstraint* horCon = [NSLayoutConstraint constraintWithItem:self.loadingSpinner attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.frame attribute:NSLayoutAttributeCenterX multiplier:1 constant:0];
        NSLayoutConstraint* verCon = [NSLayoutConstraint constraintWithItem:self.loadingSpinner attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.frame attribute:NSLayoutAttributeCenterY multiplier:1 constant:0];
        [self.frame addConstraints:@[horCon, verCon]];*/

        
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
          /*NSDictionary* msg = @{@"type": type, @"data": data != nil ? data : NSNull.null};
          NSData* jsonMsg = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
          NSString* evalString = [NSString stringWithFormat:@"postHostMessage(%@);", [[NSString alloc] initWithData:jsonMsg encoding:NSUTF8StringEncoding]];

          [self.webView evaluateJavaScript:evalString completionHandler:nil];*/
      }
        
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
       if message.name != "inAppHost" {
           return;
       }
        
        var type = message.body["type"]
        
        if (type == "READY") {
              messageQueueLock.wait()
              defer {
                  messageQueueLock.signal()
              }
                          
            self.presentFromQueue()
        }
        else if (type == "MESSAGE_OPENED") {
            loadingSpinner?.stopAnimating()
            self.kumulos.inAppHelper.trackMessageOpened(message: self.currentMessage!)
       } else if (type  == "MESSAGE_CLOSED") {
            self.handleMessageClosed()
       } else if (type == "EXECUTE_ACTIONS") {
            self.handleActions(actions: message.body["data"]["actions"])
       } else {
            
           NSLog("Unknown message: %@", message.body)
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
        
            var hasClose : Bool = false;
            var trackEvent : String?
            var subscribeToChannelUuid : String?
            var userAction : NSDictionary?
            
            for action in actions {
                var type = action["type"] as! String
                
                if (type == InAppAction.CLOSE_MESSAGE.rawValue) {
                    hasClose = true;
                } else if (type == InAppAction.TRACK_EVENT.rawValue) {
                    trackEvent = action["data"]["eventType"];
                } else if (type == InAppAction.SUBSCRIBE_CHANNEL.rawValue) {
                    subscribeToChannelUuid = action["data"]["channelUuid"];
                } else {
                    userAction = action;
                }
            }

            if (hasClose) {
                self.kumulos.inAppHelper.markMessageDismissed(message: message)
                self.postClientMessage(type: "CLOSE_MESSAGE", data: nil)
            }

            if (trackEvent != nil) {
                Kumulos.trackEvent(eventType: trackEvent!, properties: [:]);
            }

            if (subscribeToChannelUuid != nil) {
                /*KumulosPushSubscriptionManager* psm = [[KumulosPushSubscriptionManager alloc] initWithKumulos:self.kumulos];
                [psm subscribeToChannels:@[subscribeToChannelUuid]];*/
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
            if (self.kumulos.config.inAppDeepLinkHandlerBlock == nil) {
                return;
            }
            //TODO!
            /*dispatch_async(dispatch_get_main_queue(), ^{
                NSDictionary* data = userAction[@"data"][@"deepLink"] ?: @{};
                self.kumulos.config.inAppDeepLinkHandler(data);
            });*/
        } else if (type == InAppAction.OPEN_URL.rawValue) {
            //NSURL* url = [NSURL URLWithString:userAction[@"data"][@"url"]];

            if #available(iOS 10.0.0, *) {
                //UIApplication.shared.openURL(url: url)
            } else {
                /*dispatch_async(dispatch_get_main_queue(), ^{
                    [UIApplication.sharedApplication openURL:url];
                });*/
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
