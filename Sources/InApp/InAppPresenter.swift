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
       /* if (!self.messageQueue.count) {
            return;
        }

        if (self.loadingSpinner) {
            [self.loadingSpinner performSelectorOnMainThread:@selector(startAnimating) withObject:nil waitUntilDone:YES];
        }

        self.currentMessage = self.messageQueue[0];
        [self postClientMessage:@"PRESENT_MESSAGE" withData:self.currentMessage.content];*/
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

  /*  - (void) cancelCurrentPresentationQueue:(BOOL)waitForViewCleanup {
        @synchronized (self.messageQueue) {
            [self.messageQueue removeAllObjects];
            [self.pendingTickleIds removeAllObjects];
            self.currentMessage = nil;
        }

        [self performSelectorOnMainThread:@selector(destroyViews) withObject:nil waitUntilDone:waitForViewCleanup];
    }*/
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
           
       if message.name != "inAppHost" {
           return;
       }

        
        
        var type = message.body["type"]
        
        if (type == "READY") {
            /*
             TODO
             @synchronized (self.messageQueue) {
                [self presentFromQueue];
            }*/
        }
        else if (type == "MESSAGE_OPENED") {
            loadingSpinner?.stopAnimating()
            self.kumulos.inAppHelper.trackMessageOpened(self.currentMessage)
       } else if (type  == "MESSAGE_CLOSED") {
            self.handleMessageClosed()
       } else if (type == "EXECUTE_ACTIONS") {
            self.handleActions(actions: message.body["data"]["actions"])
       } else {
            
           NSLog("Unknown message: %@", message.body)
       }
   }
    

    
  /*  - (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
        [self cancelCurrentPresentationQueue:NO];
    }

    - (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
        [self cancelCurrentPresentationQueue:NO];
    }*/

    func handleActions(actions: [NSDictionary]) -> Void  {
        var hasClose : Bool = false;
        var trackEvent : String
        var subscribeToChannelUuid : String
        var userAction : NSDictionary
        
        for (action in actions) {
            var type = action["type"]
            
            if (type == InAppAction.CLOSE_MESSAGE) {
                hasClose = true;
            } else if (type == InAppAction.TRACK_EVENT) {
                trackEvent = action["data"]["eventType"];
            } else if (type == InAppAction.SUBSCRIBE_CHANNEL) {
                subscribeToChannelUuid = action["data"]["channelUuid"];
            } else {
                userAction = action;
            }
        }

        if (hasClose) {
            self.kumulos.inAppHelper.markMessageDismissed(message: self.currentMessage)
            self.postClientMessage("CLOSE_MESSAGE", withData:nil)
        }

        if (trackEvent != nil) {
            [self.kumulos trackEvent:trackEvent withProperties:nil];
        }

        if (subscribeToChannelUuid != nil) {
            KumulosPushSubscriptionManager* psm = [[KumulosPushSubscriptionManager alloc] initWithKumulos:self.kumulos];
            [psm subscribeToChannels:@[subscribeToChannelUuid]];
        }

        if (userAction != nil) {
            [self handleUserAction:userAction];
            [self cancelCurrentPresentationQueue:YES];
        }
    }

    func handleUserAction(userAction: NSDictionary) -> Void {
        /*NSString* type = userAction[@"type"];
        if ([type isEqualToString:KSInAppActionPromptPushPermission]) {
            [self.kumulos pushRequestDeviceToken];
        } else if ([type isEqualToString:KSInAppActionDeepLink]) {
            if (self.kumulos.config.inAppDeepLinkHandler == nil) {
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                NSDictionary* data = userAction[@"data"][@"deepLink"] ?: @{};
                self.kumulos.config.inAppDeepLinkHandler(data);
            });
        } else if ([type isEqualToString:KSInAppActionOpenUrl]) {
            NSURL* url = [NSURL URLWithString:userAction[@"data"][@"url"]];

            if (@available(iOS 10.0.0, *)) {
                [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
                    /* noop */
                }];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [UIApplication.sharedApplication openURL:url];
                });
            }
        } else if ([type isEqualToString:KSInAppActionRequestRating]) {
            if (@available(iOS 10.3.0, *)) {
                [SKStoreReviewController requestReview];
            } else {
                NSLog(@"Requesting a rating not supported on this iOS version");
            }
        }*/
    }
    
}
