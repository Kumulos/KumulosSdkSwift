//
//  SharedKeys.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 19/03/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

internal enum KumulosUserDefaultsKey : String {
    case API_KEY = "KumulosApiKey"
    case SECRET_KEY = "KumulosSecretKey"
    
    case MESSAGES_LAST_SYNC_TIME = "KumulosMessagesLastSyncTime"
    case IN_APP_CONSENTED = "KumulosInAppConsented"
    case INSTALL_UUID = "KumulosUUID"
    case USER_ID = "KumulosCurrentUserID"
    //exists only in standard defaults for app
    case MIGRATED_TO_GROUPS = "KumulosDidMigrateToAppGroups"
    //exists only in standard defaults for extension
    case DYNAMIC_CATEGORY = "__kumulos__dynamic__categories__"
    
    //all keys added to UserDefaults have to be here to be migrated from standard to suite UserDefaults
    static let sharedKeys = [
        API_KEY,
        SECRET_KEY,
        MESSAGES_LAST_SYNC_TIME,
        IN_APP_CONSENTED,
        INSTALL_UUID,
        USER_ID
    ]
}
