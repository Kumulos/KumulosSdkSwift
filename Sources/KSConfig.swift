//
//  KSConfig.swift
//  KumulosSDK
//
//  Created by Andy on 05/10/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation

open class KSConfig: NSObject {
    fileprivate init(apiKey: String, secretKey: String, enableCrash: Bool, sessionIdleTimeout: UInt, inAppConsentStrategy: InAppConsentStrategy, inAppDeepLinkHandlerBlock : InAppDeepLinkHandlerBlock?, pushOpenedHandlerBlock : PushOpenedHandlerBlock?) {
        _apiKey = apiKey
        _secretKey = secretKey
        _enableCrash = enableCrash
        _sessionIdleTimeout = sessionIdleTimeout
        _inAppConsentStrategy = inAppConsentStrategy
        _inAppDeepLinkHandlerBlock = inAppDeepLinkHandlerBlock
        _pushOpenedHandlerBlock = pushOpenedHandlerBlock
    }
    
    private var _apiKey: String
    private var _secretKey: String
    private var _enableCrash: Bool
    private var _sessionIdleTimeout: UInt
    private var _inAppConsentStrategy : InAppConsentStrategy
    private var _inAppDeepLinkHandlerBlock : InAppDeepLinkHandlerBlock?
    private var _pushOpenedHandlerBlock : PushOpenedHandlerBlock?
    
    var apiKey: String {
        get { return _apiKey }
    }
    
    var secretKey: String {
        get { return _secretKey }
    }
    
    var enableCrash: Bool {
        get { return _enableCrash }
    }
    
    var sessionIdleTimeout: UInt {
        get { return _sessionIdleTimeout }
    }
    
    var inAppConsentStrategy: InAppConsentStrategy {
        get {
            return _inAppConsentStrategy
        }
    }
    
    var inAppDeepLinkHandlerBlock: InAppDeepLinkHandlerBlock? {
        get {
            return _inAppDeepLinkHandlerBlock
        }
    }
    
    var pushOpenedHandlerBlock: PushOpenedHandlerBlock? {
        get {
            return _pushOpenedHandlerBlock
        }
    }
}

open class KSConfigBuilder: NSObject {
    private var _apiKey: String
    private var _secretKey: String
    private var _enableCrash: Bool
    private var _sessionIdleTimeout: UInt
    private var _inAppConsentStrategy = InAppConsentStrategy.NotEnabled
    private var _inAppDeepLinkHandlerBlock: InAppDeepLinkHandlerBlock?
    private var _pushOpenedHandlerBlock: PushOpenedHandlerBlock?
    
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
    
    public func setInAppDeepLinkHandlerBlock(inAppDeepLinkHandlerBlock: InAppDeepLinkHandlerBlock) -> KSConfigBuilder {
        _inAppDeepLinkHandlerBlock = inAppDeepLinkHandlerBlock
        return self
    }
    
    public func setInAppDeepLinkHandlerBlock(pushOpenedHandlerBlock: PushOpenedHandlerBlock) -> KSConfigBuilder {
        _pushOpenedHandlerBlock = pushOpenedHandlerBlock
        return self
    }
    
    public func build() -> KSConfig {
        return KSConfig(apiKey: _apiKey, secretKey: _secretKey, enableCrash: _enableCrash, sessionIdleTimeout: _sessionIdleTimeout, inAppConsentStrategy: _inAppConsentStrategy, inAppDeepLinkHandlerBlock: _inAppDeepLinkHandlerBlock, pushOpenedHandlerBlock: _pushOpenedHandlerBlock)
    }
}
