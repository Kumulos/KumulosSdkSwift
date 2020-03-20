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
    static let userIdLock = DispatchSemaphore(value: 1)
    
    static var installId :String {
       get {
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
    
    /**
     Returns the identifier for the user currently associated with the Kumulos installation record

     If no user is associated, it returns the Kumulos installation ID
    */
    static var currentUserIdentifier : String {
        get {
            userIdLock.wait()
            defer { userIdLock.signal() }
            if let userId = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.USER_ID.rawValue) as! String? {
                return userId;
            }

            return KumulosHelper.installId
        }
    }
    
    
}
