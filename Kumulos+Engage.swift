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
        
        Kumulos.trackKumulosEvent(eventType: "k.engage.locationUpdated", properties: parameters)
    }
    
    public static func sendiBeaconProximity(beaconIdentifier: String) {
        let parameters = [
            "iBeaconId" : beaconIdentifier
        ]
        
        Kumulos.trackKumulosEvent(eventType: "k.engage.beaconEnteredProximity", properties: parameters)
    }
}
