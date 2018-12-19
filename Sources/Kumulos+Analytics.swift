//
//  Kumulos+Analytics.swift
//  KumulosSDK
//
//  Copyright © 2018 Kumulos. All rights reserved.
//

import Foundation

public extension Kumulos {
    
    internal static func trackEvent(eventType: KumulosEvent, properties: [String:Any]?, immediateFlush: Bool = false) {
        getInstance().analyticsHelper?.trackEvent(eventType: eventType.rawValue, properties: properties, immediateFlush: immediateFlush)
    }
    
    /**
     Logs an analytics event to the local database
     
     Parameters:
     - eventType: Unique identifier for the type of event
     - properties: Optional meta-data about the event
     */
    public static func trackEvent(eventType: String, properties: [String:Any]?) {
        getInstance().analyticsHelper?.trackEvent(eventType: eventType, properties: properties, immediateFlush: false)
    }
    
    /**
     Logs an analytics event to the local database then flushes all locally stored events to the server
     
     Parameters:
     - eventType: Unique identifier for the type of event
     - properties: Optional meta-data about the event
     */
    public static func trackEventImmediately(eventType: String, properties: [String:Any]?) {
        getInstance().analyticsHelper?.trackEvent(eventType: eventType, properties: properties, immediateFlush: true)
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
        Kumulos.trackEvent(eventType: KumulosEvent.STATS_ASSOCIATE_USER, properties: params as [String : AnyObject], immediateFlush: true)
    }
    
    /**
     Associates a user identifier with the current Kumulos installation record, additionally setting the attributes for the user
     
     Parameters:
     - userIdentifier: Unique identifier for the current user
     - attributes: JSON encodable dictionary of attributes to store for the user
     */
    public static func associateUserWithInstall(userIdentifier: String, attributes: [String:AnyObject]) {
        if userIdentifier == "" {
            print("User identifier cannot be empty, aborting!")
            return
        }
        
        let params = ["id": userIdentifier, "attributes": attributes] as [String : Any]
        Kumulos.trackEvent(eventType: KumulosEvent.STATS_ASSOCIATE_USER, properties: params, immediateFlush: true)
    }
    
}
