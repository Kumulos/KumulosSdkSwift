//
//  MediaHelper.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 05/07/2021.
//  Copyright © 2021 Kumulos. All rights reserved.
//

import Foundation

public class MediaHelper {
    private static let mediaResizerBaseUrl: String = "https://i.app.delivery"
    
    internal static func getCompletePictureUrl(pictureUrl: String, width: UInt) -> URL? {
        
        if (((pictureUrl as NSString).substring(with: NSRange(location: 0, length: 8))) == "https://") || (((pictureUrl as NSString).substring(with: NSRange(location: 0, length: 7))) == "http://") {
            return URL(string: pictureUrl)
        }

        let baseUrl = KeyValPersistenceHelper.object(forKey: KumulosUserDefaultsKey.MEDIA_BASE_URL.rawValue) as? String ?? mediaResizerBaseUrl;

        let completeString = String(format: "%@%@%ld%@%@", baseUrl, "/", width, "x/", pictureUrl)
        return URL(string: completeString)
    }
}
