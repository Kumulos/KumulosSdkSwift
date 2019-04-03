//
//  Kumulos+Engage.swift
//  KumulosSDK
//
//  Created by Andrew Lindsay on 08/03/2018.
//  Copyright © 2018 Kumulos. All rights reserved.
//

import CoreLocation

public extension Kumulos{
    
    static func sendLocationUpdate(location: CLLocation) {
        let parameters = [
            "lat" : location.coordinate.latitude,
            "lng" : location.coordinate.longitude
        ]
        
        Kumulos.trackEvent(eventType: KumulosEvent.ENGAGE_LOCATION_UPDATED, properties: parameters, immediateFlush: true)
    }
    
    static func sendiBeaconProximity(beacon: CLBeacon) {
        
        let parameters = [
            "type": 1,
            "uuid": beacon.proximityUUID.uuidString,
            "major": beacon.major.stringValue,
            "minor": beacon.minor.stringValue,
            "proximity" : beacon.proximity.rawValue
        ] as [String : Any];
        
        Kumulos.trackEvent(eventType: KumulosEvent.ENGAGE_BEACON_ENTERED_PROXIMITY, properties: parameters, immediateFlush: true)
    }
}
