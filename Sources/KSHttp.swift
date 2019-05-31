//
//  KSHttp.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation

typealias KSHttpSuccessBlock = (_ response:HTTPURLResponse?, _ decodedBody:Any?) -> Void
typealias KSHttpFailureBlock = (_ response:HTTPURLResponse?, _ error:Error?) -> Void

enum KSHttpDataFormat {
    case json
    case plist
}

enum KSHttpMethod : String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

internal class KSHttpClient {
    private let baseUrl : URL
    private let urlSession : URLSession
    private var authHeader : String?
    private let requestFormat : KSHttpDataFormat
    private let responseFormat : KSHttpDataFormat

    // MARK: Initializers & Configs

    init(baseUrl: URL, requestFormat: KSHttpDataFormat, responseFormat: KSHttpDataFormat) {
        self.baseUrl = baseUrl
        self.requestFormat = requestFormat
        self.responseFormat = responseFormat

        let config = URLSessionConfiguration.ephemeral

        if requestFormat == .json {
            config.httpAdditionalHeaders = ["Accept": "application/json"]
        }

        self.urlSession = URLSession(configuration: config)
        self.authHeader = nil
    }

    func setBasicAuth(user:String, password:String) {
        let creds = "\(user):\(password)"
        let data = creds.data(using: .utf8)
        let base64Creds = data?.base64EncodedString()

        if let encoded = base64Creds {
            self.authHeader = "Basic \(encoded)"
        }
    }

    func invalidateSessionCancellingTasks(_ cancel:Bool) {
        if cancel {
            urlSession.invalidateAndCancel()
        }
        else {
            urlSession.finishTasksAndInvalidate()
        }
    }

    // MARK: HTTP Methods

    @discardableResult func sendRequest(_ method:KSHttpMethod, toPath:String, data:Any?, onSuccess:@escaping KSHttpSuccessBlock, onFailure:@escaping KSHttpFailureBlock) -> URLSessionDataTask {
        let request = self.newRequestToPath(toPath, method: method, body: data)

        return self.sendRequest(request: request, onSuccess: onSuccess, onFailure: onFailure)
    }

    // MARK: Helpers

    fileprivate func newRequestToPath(_ path:String, method:KSHttpMethod, body:Any?) -> URLRequest {
        let url = URL(string: path, relativeTo: self.baseUrl)

        var urlRequest = URLRequest(url: url!)
        urlRequest.httpMethod = method.rawValue

        if let auth = self.authHeader {
            urlRequest.addValue(auth, forHTTPHeaderField: "Authorization")
        }

        switch self.requestFormat {
        case .json:
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            break
        case .plist:
            break
        }

        if let bodyVal = body {
            let encodedBody = self.encodeBody(bodyVal)
            urlRequest.httpBody = encodedBody
        }

        return urlRequest
    }

    fileprivate func encodeBody(_ body:Any) -> Data? {
        switch self.requestFormat {
        case .json:
            guard JSONSerialization.isValidJSONObject(body) else {
                print("Cannot serialize body to JSON")
                return nil
            }

            return try? JSONSerialization.data(withJSONObject: body, options: .init(rawValue: 0))
        default:
            print("No body encoder defined for format")
            return nil
        }
    }

    fileprivate func decodeBody(_ data:Data) -> Any? {
        if data.isEmpty {
            return nil
        }

        var decodedData : Any?

        switch self.responseFormat {
        case .json:
            decodedData = try? JSONSerialization.jsonObject(with: data, options: .init(rawValue: 0))
            break
        case .plist:
            decodedData = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil)
            break
        }

        return decodedData
    }

    fileprivate func sendRequest(request:URLRequest, onSuccess:@escaping KSHttpSuccessBlock, onFailure:@escaping KSHttpFailureBlock) -> URLSessionDataTask {
        let task = urlSession.dataTask(with: request) { (data, response, error) in
            guard let httpResponse = response as? HTTPURLResponse else {
                //               TODO let castError = Error()
                onFailure(nil, nil)
                return
            }

            if error != nil {
                onFailure(httpResponse, error)
                return
            }

            var decodedBody : Any?

            if let body = data {
                decodedBody = self.decodeBody(body)
            }

            if httpResponse.statusCode > 299 {
                // TODO error
                onFailure(httpResponse, nil)
                return;
            }

            onSuccess(httpResponse, decodedBody)
        }

        task.resume()

        return task
    }

}
