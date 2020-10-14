//
//  KSConfig.swift
//  KumulosSDK
//
//  Created by Andy on 05/10/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation

public struct KSConfig {
    let apiKey: String
    let secretKey: String

    let enableCrash: Bool

    let sessionIdleTimeout: UInt

    let inAppConsentStrategy : InAppConsentStrategy
    let inAppDeepLinkHandlerBlock : InAppDeepLinkHandlerBlock?

    let pushOpenedHandlerBlock : PushOpenedHandlerBlock?
    fileprivate let _pushReceivedInForegroundHandlerBlock : Any?
    @available(iOS 10.0, *)
    var pushReceivedInForegroundHandlerBlock: PushReceivedInForegroundHandlerBlock? {
        get {
            return _pushReceivedInForegroundHandlerBlock as? PushReceivedInForegroundHandlerBlock
        }
    }

    let deepLinkCname : URL?
    let deepLinkHandler : DeepLinkHandler?
}

open class KSConfigBuilder: NSObject {
    private var _apiKey: String
    private var _secretKey: String
    private var _enableCrash: Bool
    private var _sessionIdleTimeout: UInt
    private var _inAppConsentStrategy = InAppConsentStrategy.NotEnabled
    private var _inAppDeepLinkHandlerBlock: InAppDeepLinkHandlerBlock?
    private var _pushOpenedHandlerBlock: PushOpenedHandlerBlock?
    private var _pushReceivedInForegroundHandlerBlock: Any?
    private var _deepLinkCname : URL?
    private var _deepLinkHandler : DeepLinkHandler?
    
    public init(apiKey: String, secretKey: String) {
        _apiKey = apiKey
        _secretKey = secretKey
        _enableCrash = false
        _sessionIdleTimeout = 40
    }
    
    public func enableCrash() -> KSConfigBuilder {
        _enableCrash = true
        return self
    }
    
    public func setSessionIdleTimeout(seconds: UInt) -> KSConfigBuilder {
        _sessionIdleTimeout = seconds
        return self
    }
    
    public func enableInAppMessaging(inAppConsentStrategy: InAppConsentStrategy) -> KSConfigBuilder {
        _inAppConsentStrategy = inAppConsentStrategy
        return self
    }
    
    public func setInAppDeepLinkHandler(inAppDeepLinkHandlerBlock: @escaping InAppDeepLinkHandlerBlock) -> KSConfigBuilder {
        _inAppDeepLinkHandlerBlock = inAppDeepLinkHandlerBlock
        return self
    }
    
    public func setPushOpenedHandler(pushOpenedHandlerBlock: @escaping PushOpenedHandlerBlock) -> KSConfigBuilder {
        _pushOpenedHandlerBlock = pushOpenedHandlerBlock
        return self
    }
    
    @available(iOS 10.0, *)
    public func setPushReceivedInForegroundHandler(pushReceivedInForegroundHandlerBlock: @escaping PushReceivedInForegroundHandlerBlock) -> KSConfigBuilder {
        _pushReceivedInForegroundHandlerBlock = pushReceivedInForegroundHandlerBlock
        return self
    }

    public func enableDeepLinking(cname: String? = nil, _ handler: @escaping DeepLinkHandler) -> KSConfigBuilder {
        _deepLinkCname = URL(string: cname ?? "")
        _deepLinkHandler = handler

        return self
    }
    
    public func build() -> KSConfig {
        return KSConfig(
            apiKey: _apiKey,
            secretKey: _secretKey,
            enableCrash: _enableCrash,
            sessionIdleTimeout: _sessionIdleTimeout,
            inAppConsentStrategy: _inAppConsentStrategy,
            inAppDeepLinkHandlerBlock: _inAppDeepLinkHandlerBlock,
            pushOpenedHandlerBlock: _pushOpenedHandlerBlock,
            _pushReceivedInForegroundHandlerBlock: _pushReceivedInForegroundHandlerBlock,
            deepLinkCname: nil,
            deepLinkHandler: _deepLinkHandler
        )
    }
}
