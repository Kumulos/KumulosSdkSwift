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

// MARK: class
open class Kumulos {

    internal let baseApiUrl = "https://api.kumulos.com/b2.2/"
    internal let baseStatsUrl = "https://stats.kumulos.com/v1/"
    internal let basePushUrl = "https://push.kumulos.com/v1/"
    internal let baseCrashUrl = "https://crash.kumulos.com/v1/"

    internal let pushNotificationDeviceType = 1
    internal let pushNotificationProductionTokenType:Int = 1

    internal(set) var networkRequestsInProgress = 0

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

    fileprivate(set) var apiKey: String
    fileprivate(set) var secretKey: String

    open static var apiKey:String {
        get {
            return sharedInstance.apiKey
        }
    }

    open static var secretKey:String {
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
    open static var sessionToken:String {
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
    open static var installId :String {
        get {
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
    open static func initialize(config: KSConfig) {
        if (instance !== nil) {
            assertionFailure("The KumulosSDK has already been initialized")
        }

        instance = Kumulos(apiKey: config.apiKey, secretKey: config.secretKey)
        
        instance!.sendDeviceInformation()
        
        if (config.enableCrash) {
            instance!.trackAndReportCrashes()
        }
    }

    fileprivate init(apiKey: String, secretKey: String){
        self.apiKey = apiKey
        self.secretKey = secretKey

        sessionToken = UUID().uuidString
    }

    internal func makeNetworkRequest(_ method: Alamofire.HTTPMethod, url: URLConvertible, parameters: [String : AnyObject]?) -> Alamofire.DataRequest {
        let requestHeaders: HTTPHeaders = [
            "Authorization": getAuth()
        ];
        
        return Alamofire.request(url, method: method, parameters: parameters, headers: requestHeaders)
    }
    
    internal func makeJsonNetworkRequest(_ method: Alamofire.HTTPMethod, url: URLConvertible, parameters: [String : AnyObject]?) -> Alamofire.DataRequest {
        let requestHeaders: HTTPHeaders = [
            "Authorization": getAuth(),
            "Accept": "application/json",
            "Content-Type": "application/json"
        ];
        
        return Alamofire.request(url, method: method, parameters: parameters, encoding: JSONEncoding.default, headers: requestHeaders)
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
