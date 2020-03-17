//
//  KeyValPersistenceHelper.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 13/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

internal class KeyValPersistenceHelper {

    static func set(_ value: Any?, forKey: String)
    {
        getUserDefaults().set(value, forKey: forKey)
    }
    
    static func object(forKey: String) -> Any?
    {
        return getUserDefaults().object(forKey: forKey)
    }
    
    static func removeObject(forKey: String)
    {
        getUserDefaults().removeObject(forKey: forKey)
    }
    
    fileprivate static func getUserDefaults() -> UserDefaults {
        maybeMigrateUserDefaultsToAppGroups()
    
        if let suiteUserDefaults = UserDefaults(suiteName: "group.com.kumulos") {
           return suiteUserDefaults
        }
               
        return UserDefaults.standard
    }
    
    fileprivate static func maybeMigrateUserDefaultsToAppGroups() {
        
        //dont migrate if called from extension
        let bundleUrl: URL = Bundle.main.bundleURL
        let bundlePathExtension: String = bundleUrl.pathExtension
        let isAppex: Bool = bundlePathExtension == "appex"
        if (isAppex){
            return
        }
        
        let userDefaults = UserDefaults.standard
        let groupDefaults = UserDefaults(suiteName: "group.com.kumulos")
        if (groupDefaults == nil){
            userDefaults.set(false, forKey: "KumulosDidMigrateToAppGroups")
            return
        }
        
        if (userDefaults.bool(forKey: "KumulosDidMigrateToAppGroups")){
            return
        }
        
        for key in userDefaults.dictionaryRepresentation().keys {
            groupDefaults!.set(userDefaults.dictionaryRepresentation()[key], forKey: key)
        }
        userDefaults.set(true, forKey: "KumulosDidMigrateToAppGroups")
    }
}
