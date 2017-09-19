//
//  Kumulos+Stats.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation
import Alamofire
import CoreLocation

#if os(iOS) || os(watchOS) || os(tvOS)
    import UIKit
#endif

enum OSTypeID: NSNumber {
    case osTypeIDiOS = 1
    case osTypeIDOSX
    case osTypeIDAndroid
    case osTypeIDWindowsPhone
    case osTypeIDWindow
}

enum SDKTypeID: NSNumber {
    case sdkTypeObjC = 1
    case sdkTypeJavaSDK
    case sdkTypeCSharp
    case sdkTypeSwift
}

enum RuntimeType: NSNumber {
    case runtimeTypeUnknown = 0
    case runtimeTypeNative
    case runtimeTypeXamarin
    case runtimeTypeCordova
    case runtimeTypeJavaRuntime
}

enum TargetType: Int {
    case targetTypeDebug = 1
    case targetTypeRelease
}

struct Platform {
    static let isSimulator: Bool = {
        var isSim = false
        // if mac architechture and os is iOS, WatchOS or TVOS we're on a simulator
        #if (arch(i386) || arch(x86_64)) && (os(iOS) || os(watchOS) || os(tvOS))
            isSim = true
        #endif
        return isSim
    }()

    static let isMacintosh: Bool = {
        var isMac = false
        // check architechture for mac
        #if (arch(i386) || arch(x86_64))
            isMac = true
        #endif
        return isMac
    }()
}

internal extension Kumulos{

    func sendLocationInformation(location: CLLocation) {
        let url = "\(self.baseStatsUrl)app-installs/\(Kumulos.installId)/location"
        
        let parameters = [
            "latitude" : location.coordinate.latitude,
            "longitude" : location.coordinate.longitude
        ]
        
        _ = self.makeNetworkRequest(.put, url: url, parameters: parameters as [String: AnyObject])
    }
    
    func sendDeviceInformation() {

        var target = TargetType.targetTypeRelease

        //http://stackoverflow.com/questions/24111854/in-absence-of-preprocessor-macros-is-there-a-way-to-define-practical-scheme-spe
        #if DEBUG
            target = TargetType.targetTypeDebug
        #endif

        var app = [String : AnyObject]()
        app["version"] = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as AnyObject?
        app["target"] = target.rawValue as AnyObject?


        var sdk = [String : AnyObject]()
        sdk["id"] = SDKTypeID.sdkTypeObjC.rawValue

        let frameworkBundle = Bundle(for: Kumulos.self)
        let sdkVersion = frameworkBundle.infoDictionary!["CFBundleShortVersionString"]

        sdk["version"] = sdkVersion as AnyObject?

        var runtime = [String : AnyObject]()
        var os = [String : AnyObject]()
        var device = [String : AnyObject]()

        runtime["id"] = RuntimeType.runtimeTypeNative.rawValue

        let timeZone = TimeZone.autoupdatingCurrent
        let tzName = timeZone.identifier
        device["tz"] = tzName as AnyObject?
        device["name"] = Sysctl.model as AnyObject?

        if Platform.isMacintosh {
            runtime["version"] = ProcessInfo.processInfo.operatingSystemVersionString as AnyObject?

            os["id"] = OSTypeID.osTypeIDOSX.rawValue
            os["version"] = ProcessInfo.processInfo.operatingSystemVersionString as AnyObject?

            device["isSimulator"] = false as AnyObject?
            device["name"] = Sysctl.model as AnyObject?

        }
        else {
            runtime["version"] = UIDevice.current.systemVersion as AnyObject?

            os["id"] = OSTypeID.osTypeIDiOS.rawValue
            os["version"] = UIDevice.current.systemVersion as AnyObject?
        }


        device["isSimulator"] = Platform.isSimulator as AnyObject?

        let finalParameters = [
            "app" : app,
            "sdk" : sdk,
            "runtime" : runtime,
            "os" : os,
            "device" : device
        ]

        let url = "\(self.baseStatsUrl)app-installs/\(Kumulos.installId)"

        _ = self.makeNetworkRequest(.put, url: url, parameters: finalParameters as [String : AnyObject]?)
    }

}
