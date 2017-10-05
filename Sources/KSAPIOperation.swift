//
//  KSAPIOperation.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation
import Alamofire

public typealias KSAPIOperationSuccessBlock = ((KSResponse, KSAPIOperation)->Void)?
public typealias KSAPIOperationFailureBlock = ((NSError?, KSAPIOperation)->Void)?

protocol KSAPIOperationDelegate: class {
    func didComplete(_ operation: KSAPIOperation, results: KSResponse)
    func didFail(_ operation: KSAPIOperation, error: NSError?)
}

open class KSAPIOperation: Operation {

    weak var delegate:KSAPIOperationDelegate?

    var kumulosParams: Dictionary<String, AnyObject>?
    var methodName: String

    init(methodName: String, params: Dictionary<String, AnyObject>?) {
        self.methodName = methodName
        self.kumulosParams = params

        super.init()
    }

    fileprivate func buildParameters() -> Dictionary<String, AnyObject> {

        var completeParameters = [String:AnyObject]()

        if kumulosParams != nil {
            completeParameters["params"] = kumulosParams as AnyObject?
        }

        completeParameters["sessionToken"] = Kumulos.sessionToken as AnyObject?
        completeParameters["deviceID"] = Kumulos.installId as AnyObject?
        completeParameters["installId"] = Kumulos.installId as AnyObject?

        return completeParameters
    }

    open override func cancel() {
        Kumulos.apiMethodRequestComplete()
    }

    var successBlock:KSAPIOperationSuccessBlock?
    var failureBlock:KSAPIOperationFailureBlock?

    /**
        Sets the success handler block for Kumulos API operations

        - Parameters:
            - success: A block object to be executed upon the completion of the operation. This block has no return value and takes two arguments: the completed operation and the results.

        Example of consuming the results:

        ```
        if let _ = response.payload as? Array<AnyObject> {
            // Handle a select action result
            print("It's an array of objects!")
        }

        if let _ = response.payload as? NSNumber {
            // Handle a create/delete/update/aggregate action result
            print("It's a number!")
        }
        ```
    */
    @discardableResult open func success(_ success:KSAPIOperationSuccessBlock) -> KSAPIOperation {
        successBlock = success
        return self
    }

    /**
        Sets the failure handler block for Kumulos API operations

        - Parameters:
            - failure: A block object to be executed upon the failure of the operation. This block has no return value and takes two arguments: the completed operation and the resulting error.
    */
    @discardableResult open func failure(_ failure:KSAPIOperationFailureBlock) -> KSAPIOperation {
        failureBlock = failure
        return self
    }

    override open func main() {
        let url = Kumulos.getUrlForApiMethod(methodName)
        let parameters = buildParameters()

        Kumulos.apiMethodRequestStart()


            Kumulos.sharedInstance.makeNetworkRequest(.post, url: url, parameters: parameters)
            .responsePropertyList
            { response in

                Kumulos.apiMethodRequestComplete()

                switch response.result {
                    case .success:
                        if let results = response.result.value as? Dictionary<String,AnyObject> {
                            //- Detect errors here, not in unpack.
                            let responseCode = results["responseCode"] as? NSNumber

                            if (KSResponseCode.success.rawValue == responseCode) {

                                self.updateSessionToken(results)

                                let kumulosResponse = self.unpackKumulosApiResponse(results)
                                self.delegate?.didComplete(self, results: kumulosResponse)
                                return
                            }

                            // error?
                            let responseMessage = results["responseMessage"] as? String
                            let userInfo: [AnyHashable: Any] = [NSLocalizedDescriptionKey :  responseMessage!]
                            let error = NSError(domain: "Kumulos", code: responseCode as! Int, userInfo: userInfo as? [String : Any])

                            self.delegate?.didFail(self, error: error)
                        }
                        else
                        {
                            self.onRequestError()
                        }
                    case .failure:
                        self.delegate?.didFail(self, error: nil)
                }

            }
    }

    fileprivate func updateSessionToken(_ response: Dictionary<String, AnyObject>) {
        if let sessionToken = response["sessionToken"] as? String{
            Kumulos.sessionToken = sessionToken
        }
    }

    fileprivate func unpackKumulosApiResponse(_ theResponse: Dictionary<String,AnyObject>) -> KSResponse {

        let response = KSResponse()

        if let payload = theResponse["payload"] {
            response.payload = payload
        }

        if let responseCode = theResponse["responseCode"] as? UInt32{
            response.responseCode = responseCode
        }

        if let responseMessage = theResponse["responseMessage"] as? String{
            response.responseMessage = responseMessage
        }

        if let timestamp = theResponse["timestamp"] as? NSNumber{
            response.timestamp = timestamp
        }

        if let requestProcessingTime = theResponse["requestProcessingTime"] as? Float{
            response.requestProcessingTime = requestProcessingTime
        }

        if let requestReceivedTime = theResponse["requestReceivedTime"] as? Float{
            response.requestReceivedTime = requestReceivedTime
        }

        return response
    }

    fileprivate func onRequestError() {
        let userInfo: [AnyHashable: Any] = [NSLocalizedDescriptionKey :  NSLocalizedString("Response Error", value: "Could not parse the Kumulos response", comment: ""),
                                                NSLocalizedFailureReasonErrorKey : NSLocalizedString("Response Error", value: "Could not parse the Kumulos response", comment: "")]
        let error = NSError(domain: "KumulosResponseErrorDomain", code: 0, userInfo: userInfo as? [String : Any])

        self.delegate?.didFail(self, error: error)
    }

}
