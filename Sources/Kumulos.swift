//
//  Kumulos.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation
import Alamofire

// MARK: delegate protocol
/*!
 *  The KumulosDelegate defines the methods for completion or failure of Kumulos operations.
 */
protocol KumulosDelegate: class {
    func didComplete(_ kumulos: Kumulos, operation: KSAPIOperation, method: String, results: KSResponse)
    func didFail(_ kumulos: Kumulos, operation: KSAPIOperation, error: NSError?)
}

internal enum KumulosEvent : String {
    case STATS_FOREGROUND = "k.fg"
    case STATS_BACKGROUND = "k.bg"
    case STATS_CALL_HOME = "k.stats.installTracked"
    case STATS_ASSOCIATE_USER = "k.stats.userAssociated"
    case STATS_USER_ASSOCIATION_CLEARED = "k.stats.userAssociationCleared"
    case PUSH_DEVICE_REGISTER = "k.push.deviceRegistered"
    case PUSH_OPEN_TRACK = "k.push.opened"
    case ENGAGE_BEACON_ENTERED_PROXIMITY = "k.engage.beaconEnteredProximity"
    case ENGAGE_LOCATION_UPDATED = "k.engage.locationUpdated"
    case DEVICE_UNSUBSCRIBED = "k.push.deviceUnsubscribed"
}

// MARK: class
open class Kumulos {

    private static let installIdLock = DispatchSemaphore(value: 1)
    
    internal let baseApiUrl = "https://api.kumulos.com/b2.2"
    internal let basePushUrl = "https://push.kumulos.com/v1"
    internal let baseCrashUrl = "https://crash.kumulos.com/v1"
    internal let baseEventsUrl = "https://events.kumulos.com/v1"

    internal let pushNotificationDeviceType = 1
    internal let pushNotificationProductionTokenType:Int = 1

    var networkRequestsInProgress = 0

    fileprivate static var instance:Kumulos?

    internal static var sharedInstance:Kumulos {
        get {
            if(false == isInitialized()) {
                assertionFailure("The KumulosSDK has not been initialized")
            }

            return instance!
        }
    }
    
    public static func getInstance() -> Kumulos
    {
        return sharedInstance;
    }

    fileprivate(set) var config : KSConfig
    fileprivate(set) var apiKey: String
    fileprivate(set) var secretKey: String
    fileprivate(set) var analyticsHelper: AnalyticsHelper? = nil

    public static var apiKey:String {
        get {
            return sharedInstance.apiKey
        }
    }

    public static var secretKey:String {
        get {
            return sharedInstance.secretKey
        }
    }

    weak var delegate:KumulosDelegate?

    internal var operationQueue = OperationQueue()

    fileprivate var sessionToken: String

    /**
        The token for the current session
    */
    public static var sessionToken:String {
        get {
            return sharedInstance.sessionToken
        }
        set {
            sharedInstance.sessionToken = newValue
        }
    }

    /**
        The unique installation Id of the current app

        - Returns: String - UUID
    */
    public static var installId :String {
        get {
            installIdLock.wait()
            defer {
                installIdLock.signal()
            }
            
            if let existingID = UserDefaults.standard.object(forKey: "KumulosUUID") {
                return existingID as! String
            }

            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "KumulosUUID")
            UserDefaults.standard.synchronize()
            
            return newID
        }
    }

    internal static func isInitialized() -> Bool {
        return instance != nil
    }

    /**
        Initialize the KumulosSDK.

        - Parameters:
              - config: An instance of KSConfig
    */
    public static func initialize(config: KSConfig) {
        if (instance !== nil) {
            assertionFailure("The KumulosSDK has already been initialized")
        }

        instance = Kumulos(config: config)
        
        DispatchQueue.global().async {
            instance!.sendDeviceInformation()
        }
        
        if (config.enableCrash) {
            instance!.trackAndReportCrashes()
        }
    }

    fileprivate init(config: KSConfig) {
        self.config = config
        apiKey = config.apiKey
        secretKey = config.secretKey

        sessionToken = UUID().uuidString
        
        analyticsHelper = AnalyticsHelper(kumulos: self)
    }

    internal func makeNetworkRequest(_ method: Alamofire.HTTPMethod, url: URLConvertible, parameters: [String : AnyObject]?) -> Alamofire.DataRequest {
        let requestHeaders: HTTPHeaders = [
            "Authorization": getAuth()
        ];
        
        return Alamofire.request(url, method: method, parameters: parameters, headers: requestHeaders)
    }
    
    internal func makeJsonNetworkRequest(_ method: Alamofire.HTTPMethod, url: URLConvertible, parameters: [String : AnyObject]?) -> Alamofire.DataRequest {
        return makeJsonNetworkRequest(method, url: url, parameters: parameters, encoding: JSONEncoding.default)
    }
    
    internal func makeJsonNetworkRequest(_ method: Alamofire.HTTPMethod, url: URLConvertible, parameters : Parameters?, encoding: ParameterEncoding) -> Alamofire.DataRequest {
        let requestHeaders: HTTPHeaders = [
            "Authorization": getAuth(),
            "Accept": "application/json",
            "Content-Type": "application/json"
        ];
        
        return Alamofire.request(url, method: method, parameters: parameters, encoding: encoding, headers: requestHeaders)
    }

    fileprivate func getAuth()-> String {
        let authString = "\(apiKey):\(secretKey)"
        let authData = authString.data(using: String.Encoding.ascii)

        return "Basic \(authData!.base64EncodedString(options: NSData.Base64EncodingOptions.endLineWithLineFeed))"
    }

    internal static func getUrlForApiMethod(_ methodName: String) -> String {
        let k = Kumulos.sharedInstance

        return "\(k.baseApiUrl)/\(k.apiKey)/\(methodName).plist"
    }
}
