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
        if (!AppGroupsHelper.isKumulosAppGroupDefined()){
            standardDefaults.set(false, forKey: KumulosUserDefaultsKey.MIGRATED_TO_GROUPS.rawValue)
            return;
        }
        
        if (standardDefaults.bool(forKey: KumulosUserDefaultsKey.MIGRATED_TO_GROUPS.rawValue)){
            return
        }
        
        guard let groupDefaults = UserDefaults(suiteName: AppGroupsHelper.getKumulosGroupName()) else { return }
        
        for key in KumulosUserDefaultsKey.sharedKeys{
            groupDefaults.set(standardDefaults.dictionaryRepresentation()[key.rawValue], forKey: key.rawValue)
        }
        
        standardDefaults.set(true, forKey: KumulosUserDefaultsKey.MIGRATED_TO_GROUPS.rawValue)
    }
    
    fileprivate static func getUserDefaults() -> UserDefaults {
        if (!AppGroupsHelper.isKumulosAppGroupDefined()){
            return UserDefaults.standard
        }
        
        if let suiteUserDefaults = UserDefaults(suiteName: AppGroupsHelper.getKumulosGroupName()) {
            return suiteUserDefaults
        }
        
        return UserDefaults.standard
    }
}
