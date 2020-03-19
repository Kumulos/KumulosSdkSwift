//
//  AppGroupsHelper.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 19/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation


internal class AppGroupsHelper {

    internal static func isKumulosAppGroupDefined() -> Bool {
        let containerUrl = getSharedContainerPath()
        
        return containerUrl != nil
    }
    
    internal static func getSharedContainerPath() -> URL? {
       return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: getKumulosGroupName())
    }
    
    internal static func getKumulosGroupName() -> String {
        return "group.com.kumulos"//TODO: normal name
    }
}

