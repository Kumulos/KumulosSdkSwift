//
//  KeyValPersistenceHelper.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 13/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

internal class KeyValPersistenceHelper {

    internal static let MIGRATED_TO_GROUPS_KEY = "KumulosDidMigrateToAppGroups"
    
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
    
    internal static func maybeMigrateUserDefaultsToAppGroups() {
        let standardDefaults = UserDefaults.standard
        if (!isKumulosAppGroupDefined()){
            standardDefaults.set(false, forKey: MIGRATED_TO_GROUPS_KEY)
            return;
        }
        
        if (standardDefaults.bool(forKey: MIGRATED_TO_GROUPS_KEY)){
            return
        }
       
        let groupDefaults = UserDefaults(suiteName: "group.com.kumulos")
        if (groupDefaults == nil){
            return
        }
        
        for key in standardDefaults.dictionaryRepresentation().keys {
            groupDefaults!.set(standardDefaults.dictionaryRepresentation()[key], forKey: key)
        }
        standardDefaults.set(true, forKey: MIGRATED_TO_GROUPS_KEY)
    }
    
    fileprivate static func getUserDefaults() -> UserDefaults {
        if (!isKumulosAppGroupDefined()){
            return UserDefaults.standard
        }
        
        if let suiteUserDefaults = UserDefaults(suiteName: "group.com.kumulos") {
            return suiteUserDefaults
        }
        
        return UserDefaults.standard
    }
    
    fileprivate static func isKumulosAppGroupDefined() -> Bool {
        let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.kumulos")//TODO: normal name
        
        return containerUrl != nil
    }
}
