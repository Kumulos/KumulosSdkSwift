//
//  KSConfig.swift
//  KumulosSDK
//
//  Created by Andy on 05/10/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation

open class KSConfig: NSObject {
    fileprivate init(apiKey: String, secretKey: String, enableCrash: Bool) {
        _apiKey = apiKey
        _secretKey = secretKey
        _enableCrash = enableCrash
    }
    
    private var _apiKey: String
    private var _secretKey: String
    private var _enableCrash: Bool
    
    var apiKey: String {
        get { return _apiKey }
    }
    
    var secretKey: String {
        get { return _secretKey }
    }
    
    var enableCrash: Bool {
        get { return _enableCrash }
    }
}

open class KSConfigBuilder: NSObject {
    private var _apiKey: String
    private var _secretKey: String
    private var _enableCrash: Bool
    
    public init(apiKey: String, secretKey: String) {
        _apiKey = apiKey
        _secretKey = secretKey
        _enableCrash = false
    }
    
    public func enableCrash() -> KSConfigBuilder {
        _enableCrash = true
        return self;
    }
    
    public func build() -> KSConfig {
        return KSConfig(apiKey: _apiKey, secretKey: _secretKey, enableCrash: _enableCrash)
    }
}
