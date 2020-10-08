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
        let haveMigratedKey : String = KumulosUserDefaultsKey.MIGRATED_TO_GROUPS.rawValue
        if (!AppGroupsHelper.isKumulosAppGroupDefined()){
            standardDefaults.set(false, forKey: haveMigratedKey)
            return;
        }
        
        guard let groupDefaults = UserDefaults(suiteName: AppGroupsHelper.getKumulosGroupName()) else { return }
        if (groupDefaults.bool(forKey: haveMigratedKey) && standardDefaults.bool(forKey: haveMigratedKey)){
            return
        }
        
        let defaultsAsDict : [String: Any] = standardDefaults.dictionaryRepresentation()
        for key in KumulosUserDefaultsKey.sharedKeys{
            groupDefaults.set(defaultsAsDict[key.rawValue], forKey: key.rawValue)
        }
        
        standardDefaults.set(true, forKey: haveMigratedKey)
        groupDefaults.set(true, forKey: haveMigratedKey)
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
