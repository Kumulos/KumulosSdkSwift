//
//  Kumulos.swift
//  KumulosSDKExtension
//
//  Created by Vladislav Voicehovics on 19/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

class KumulosForExtension  {
    
    fileprivate static var instance:KumulosForExtension?
    fileprivate let analyticsHelper: AnalyticsHelper
    
    fileprivate init(apiKey: String, secretKey: String) {
        analyticsHelper = AnalyticsHelper()
        analyticsHelper.initialize(apiKey: apiKey, secretKey: secretKey, sessionIdleTimeout: nil)
    }
    
    internal static func initialize() -> Bool {
        if (instance !== nil) {
            assertionFailure("The KumulosSDK has already been initialized in extension")
        }
        
        let apiKey = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.API_KEY.rawValue) as! String?
        let secretKey = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.SECRET_KEY.rawValue) as! String?
        if (apiKey == nil || secretKey == nil){
            print("Extension: authorization credentials not present")
            return false;
        }
        
        instance = KumulosForExtension(apiKey: apiKey!, secretKey: secretKey!)
        
        return true
    }
    
    internal static func getInstance() -> KumulosForExtension
    {
        if(instance == nil) {
            assertionFailure("The KumulosSDK has not been initialized")
        }
        
        return instance!
    }
    
    internal static func trackEventImmediately(eventType: String, properties: [String:Any]?) {
        getInstance().analyticsHelper.trackEvent(eventType: eventType, properties: properties, immediateFlush: true)
    }
}
