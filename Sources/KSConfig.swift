//
//  KSConfig.swift
//  KumulosSDK
//
//  Created by Andy on 05/10/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation

open class KSConfig: NSObject {
    fileprivate init(apiKey: String, secretKey: String, enableCrash: Bool, sessionIdleTimeout: UInt) {
        _apiKey = apiKey
        _secretKey = secretKey
        _enableCrash = enableCrash
        _sessionIdleTimeout = sessionIdleTimeout
    }
    
    private var _apiKey: String
    private var _secretKey: String
    private var _enableCrash: Bool
    private var _sessionIdleTimeout: UInt
    
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
}

open class KSConfigBuilder: NSObject {
    private var _apiKey: String
    private var _secretKey: String
    private var _enableCrash: Bool
    private var _sessionIdleTimeout: UInt
    
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
    
    public func build() -> KSConfig {
        return KSConfig(apiKey: _apiKey, secretKey: _secretKey, enableCrash: _enableCrash, sessionIdleTimeout: _sessionIdleTimeout)
    }
}
