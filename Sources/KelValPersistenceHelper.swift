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
    
    internal static func maybeMigrateUserDefaultsToAppGroups() {
        let standardDefaults = UserDefaults.standard
        if (!isKumulosAppGroupDefined()){
            standardDefaults.set(false, forKey: KumulosUserDefaultsKey.MIGRATED_TO_GROUPS.rawValue)
            return;
        }
        
        if (standardDefaults.bool(forKey: KumulosUserDefaultsKey.MIGRATED_TO_GROUPS.rawValue)){
            return
        }
        
        guard let groupDefaults = UserDefaults(suiteName: "group.com.kumulos") else { return }
        
        for key in KumulosUserDefaultsKey.sharedKeys{
            groupDefaults.set(standardDefaults.dictionaryRepresentation()[key.rawValue], forKey: key.rawValue)
        }
        
        standardDefaults.set(true, forKey: KumulosUserDefaultsKey.MIGRATED_TO_GROUPS.rawValue)
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
