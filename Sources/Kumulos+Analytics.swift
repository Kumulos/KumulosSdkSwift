//
//  Kumulos+Analytics.swift
//  KumulosSDK
//
//  Copyright © 2018 Kumulos. All rights reserved.
//

import Foundation

public extension Kumulos {
    
    /**
     Logs an analytics event to the local database
     
     Parameters:
     - eventType: Unique identifier for the type of event
     - properties: Optional meta-data about the event
     */
    public static func trackEvent(eventType: String, properties: [String:Any]?) {
        getInstance().analyticsHelper?.trackEvent(eventType: eventType, properties: properties)
    }
    
    /**
     Associates a user identifier with the current Kumulos installation record
     
     Parameters:
     - userIdentifier: Unique identifier for the current user
     */
    public static func associateUserWithInstall(userIdentifier: String) {
        if userIdentifier == "" {
            print("User identifier cannot be empty, aborting!")
            return
        }

        let params = ["id": userIdentifier]
        let url = "\(getInstance().baseStatsUrl)app-installs/\(Kumulos.installId)/user-id"
        _ = getInstance().makeJsonNetworkRequest(.put, url: url, parameters: params as [String : AnyObject])
    }
    
}
