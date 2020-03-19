//
//  KSConfigExt.swift
//  KumulosSDKExtension
//
//  Created by Vladislav Voicehovics on 19/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

open class KSConfigForExtension: NSObject {
    fileprivate init(apiKey: String, secretKey: String) {
        _apiKey = apiKey
        _secretKey = secretKey
    }
    
    private var _apiKey: String
    private var _secretKey: String
    
    var apiKey: String {
        get { return _apiKey }
    }
    
    var secretKey: String {
        get { return _secretKey }
    }
}

open class KSConfigBuilder: NSObject {
    private var _apiKey: String
    private var _secretKey: String

    
    public init(apiKey: String, secretKey: String) {
        _apiKey = apiKey
        _secretKey = secretKey
    }

    public func build() -> KSConfigForExtension {
        return KSConfigForExtension(apiKey: _apiKey, secretKey: _secretKey)
    }
}
