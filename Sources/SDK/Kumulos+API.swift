//
//  Kumulos+API.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation

enum KSResponseCode: NSNumber {
    case success = 1
    case notAuthorized = 2
    case noSuchMethod = 4
    case noSuchFormat = 8
    case accountSuspended = 16
    case invalidRequest = 32
    case unknownServerError = 64
    case databaseError = 128
}

public extension Kumulos {

    /**
        Call an API method

        - Parameters:
            - methodName: The alias of your API method
    */
    static func call(_ methodName: String) -> KSAPIOperation {
        return performMethod(methodName, kumulosParameters: nil)
    }

    /**
        Call an API method

        - Parameters:
            - methodName: The alias of your API method
            - parameters: A dictionary of parameters for your method
     */
    static func call(_ methodName: String, parameters: Dictionary<String, AnyObject>) -> KSAPIOperation {
        return performMethod(methodName, kumulosParameters: parameters)
    }

    fileprivate static func performMethod(_ methodName: String, kumulosParameters:Dictionary<String, AnyObject>?) -> KSAPIOperation {
        let k = Kumulos.sharedInstance
        let operation = k.createAPIOperation(methodName, parameters: kumulosParameters)
        k.operationQueue.addOperation(operation)

        return operation
    }

    fileprivate func createAPIOperation(_ methodName: String, parameters: Dictionary<String, AnyObject>?) -> KSAPIOperation {
        let operation = KSAPIOperation(methodName: methodName, params: parameters)

        operation.delegate = self

        return operation
    }

    internal static func apiMethodRequestStart()
    {
        updateNetworkStatus(1)
    }

    internal static func apiMethodRequestComplete()
    {
        updateNetworkStatus(-1)
    }

    fileprivate static func updateNetworkStatus(_ inProgressCallChange: NSInteger) {
        let k = Kumulos.sharedInstance

        k.networkRequestsInProgress += inProgressCallChange

        #if os(iOS) || os(watchOS) || os(tvOS)
            DispatchQueue.main.async {
                UIApplication.shared.isNetworkActivityIndicatorVisible = (k.networkRequestsInProgress > 0)
            }
        #endif
    }
}

extension Kumulos: KSAPIOperationDelegate{

    func didComplete(_ operation: KSAPIOperation, results: KSResponse) {

        if let successBlock = operation.successBlock {
            successBlock?(results, operation)
        }else{
            self.delegate?.didComplete(self, operation: operation, method: operation.methodName, results: results)
        }
    }

    func didFail(_ operation: KSAPIOperation, error: NSError?) {

        if let failBlock = operation.failureBlock {
            failBlock?(error, operation)
        }else{
            self.delegate?.didFail(self, operation: operation, error: error)
        }
    }
}
