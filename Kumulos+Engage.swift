//
//  Kumulos+Engage.swift
//  KumulosSDK
//
//  Created by Andrew Lindsay on 08/03/2018.
//  Copyright © 2018 Kumulos. All rights reserved.
//

import CoreLocation

public extension Kumulos{
    
    public static func sendLocationUpdate(location: CLLocation) {
        let parameters = [
            "lat" : location.coordinate.latitude,
            "lng" : location.coordinate.longitude
        ]
        
        Kumulos.trackEvent(eventType: KumulosEvent.ENGAGE_LOCATION_UPDATED.rawValue, properties: parameters, immediateFlush: true)
    }
    
    public static func sendiBeaconProximity(beaconIdentifier: String) {
        let parameters = [
            "iBeaconId" : beaconIdentifier
        ]
        
        Kumulos.trackEvent(eventType: KumulosEvent.ENGAGE_BEACON_ENTERED_PROXIMITY.rawValue, properties: parameters, immediateFlush: true)
    }
}
