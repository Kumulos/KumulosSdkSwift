//
//  Kumulos+Analytics.swift
//  KumulosSDK
//
//  Copyright © 2018 Kumulos. All rights reserved.
//

import Foundation

public extension Kumulos {

    private static let userIdLock = DispatchSemaphore(value: 1)
    internal static let USER_ID_KEY = "KumulosCurrentUserID"
    
    internal static func trackEvent(eventType: KumulosEvent, properties: [String:Any]?, immediateFlush: Bool = false) {
        getInstance().analyticsHelper?.trackEvent(eventType: eventType.rawValue, properties: properties, immediateFlush: immediateFlush)
    }
    
    /**
     Logs an analytics event to the local database
     
     Parameters:
     - eventType: Unique identifier for the type of event
     - properties: Optional meta-data about the event
     */
    static func trackEvent(eventType: String, properties: [String:Any]?) {
        getInstance().analyticsHelper?.trackEvent(eventType: eventType, properties: properties, immediateFlush: false)
    }
    
    /**
     Logs an analytics event to the local database then flushes all locally stored events to the server
     
     Parameters:
     - eventType: Unique identifier for the type of event
     - properties: Optional meta-data about the event
     */
    static func trackEventImmediately(eventType: String, properties: [String:Any]?) {
        getInstance().analyticsHelper?.trackEvent(eventType: eventType, properties: properties, immediateFlush: true)
    }
    
    /**
     Associates a user identifier with the current Kumulos installation record
     
     Parameters:
     - userIdentifier: Unique identifier for the current user
     */
    static func associateUserWithInstall(userIdentifier: String) {
        associateUserWithInstallImpl(userIdentifier: userIdentifier, attributes: nil)
    }
    
    /**
     Associates a user identifier with the current Kumulos installation record, additionally setting the attributes for the user
     
     Parameters:
     - userIdentifier: Unique identifier for the current user
     - attributes: JSON encodable dictionary of attributes to store for the user
     */
    static func associateUserWithInstall(userIdentifier: String, attributes: [String:AnyObject]) {
        associateUserWithInstallImpl(userIdentifier: userIdentifier, attributes: attributes)
    }

    /**
     Returns the identifier for the user currently associated with the Kumulos installation record

     If no user is associated, it returns the Kumulos installation ID
    */
    static var currentUserIdentifier : String {
        get {
            userIdLock.wait()
            defer { userIdLock.signal() }
            if let userId = UserDefaults.standard.value(forKey: USER_ID_KEY) as! String? {
                return userId;
            }

            return Kumulos.installId
        }
    }

    /**
     Clears any existing association between this install record and a user identifier.

     See associateUserWithInstall and currentUserIdentifier for further information.
     */
    static func clearUserAssociation() {
        userIdLock.wait()
        let currentUserId = UserDefaults.standard.value(forKey: USER_ID_KEY)
        userIdLock.signal()

        Kumulos.trackEvent(eventType: KumulosEvent.STATS_USER_ASSOCIATION_CLEARED, properties: ["oldUserIdentifier": currentUserId ?? NSNull()])

        userIdLock.wait()
        UserDefaults.standard.removeObject(forKey: USER_ID_KEY)
        userIdLock.signal()
    }

    fileprivate static func associateUserWithInstallImpl(userIdentifier: String, attributes: [String:AnyObject]?) {
        if userIdentifier == "" {
            print("User identifier cannot be empty, aborting!")
            return
        }

        var params : [String:Any]
        if let attrs = attributes {
            params = ["id": userIdentifier, "attributes": attrs]
        }
        else {
            params = ["id": userIdentifier]
        }

        userIdLock.wait()
        UserDefaults.standard.set(userIdentifier, forKey: USER_ID_KEY)
        userIdLock.signal()

        Kumulos.trackEvent(eventType: KumulosEvent.STATS_ASSOCIATE_USER, properties: params, immediateFlush: true)
    }
    
}
