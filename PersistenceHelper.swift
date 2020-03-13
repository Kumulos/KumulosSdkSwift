//
//  PersistenceHelper.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 13/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

internal class PersistenceHelper {

    static func set(_ value: Any?, forKey: String)
    {
        UserDefaults.standard.set(value, forKey: forKey)
    }
    
    static func object(forKey: String) -> Any?
    {
        return UserDefaults.standard.object(forKey: forKey)
    }
    
    static func removeObject(forKey: String)
    {
        UserDefaults.standard.removeObject(forKey: forKey)
    }
}
