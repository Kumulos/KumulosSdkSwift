//
//  AppGroupsHelper.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 19/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

public struct AppGroupConfig {
    public static var suffix : String = ".kumulos"
}

internal class AppGroupsHelper {

    internal static func isKumulosAppGroupDefined() -> Bool {
        let containerUrl = getSharedContainerPath()
        
        return containerUrl != nil
    }
    
    internal static func getSharedContainerPath() -> URL? {
       return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: getKumulosGroupName())
    }
    
    internal static func getKumulosGroupName() -> String {
        var targetBundle = Bundle.main
        if targetBundle.bundleURL.pathExtension == "appex" {
            let url = targetBundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let mainBundle = Bundle(url: url) {
                targetBundle = mainBundle
            }
            else{
                print("AppGroupsHelper: Error, could not obtain main bundle from extension!")
            }
        }
       
        return "group.\(targetBundle.bundleIdentifier!)\(AppGroupConfig.suffix)"
    }
}


