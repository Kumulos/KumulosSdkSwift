//
//  KumulosProtocol.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 19/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation


class KumulosHelper {
    private static let installIdLock = DispatchSemaphore(value: 1)
    
    internal static func getInstallId() -> String{
        installIdLock.wait()
        defer {
            installIdLock.signal()
        }
        
        if let existingID = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.INSTALL_UUID.rawValue) {
            return existingID as! String
        }

        let newID = UUID().uuidString
        KeyValPersistenceHelper.set(newID, forKey: KumulosUserDefaultsKey.INSTALL_UUID.rawValue)
        
        return newID
    }
}
