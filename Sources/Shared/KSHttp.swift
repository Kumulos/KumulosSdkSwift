//
//  KSHttp.swift
//  KumulosSDK
//
//  Copyright © 2019 Kumulos. All rights reserved.
//

import Foundation

enum KSHttpError : Error {
    case responseCastingError
    case badStatusCode
}

typealias KSHttpSuccessBlock = (_ response:HTTPURLResponse?, _ decodedBody:Any?) -> Void
typealias KSHttpFailureBlock = (_ response:HTTPURLResponse?, _ error:Error?, _ decodedBody: Any?) -> Void

enum KSHttpDataFormat {
    case json
    case plist
    case rawData
}

enum KSHttpMethod : String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

internal class KSHttpClient {
    private let baseUrl : URL
    private let baseUrlComponents: URLComponents?
    private let urlSession : URLSession
    private var authHeader : String?
    private let requestFormat : KSHttpDataFormat
    private let responseFormat : KSHttpDataFormat

    // MARK: Initializers & Configs

    init(baseUrl: URL, requestFormat: KSHttpDataFormat, responseFormat: KSHttpDataFormat, additionalHeaders:[AnyHashable:Any]? = nil) {
        self.baseUrl = baseUrl
        self.baseUrlComponents = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false)
        self.requestFormat = requestFormat
        self.responseFormat = responseFormat

        let config = URLSessionConfiguration.ephemeral

        if requestFormat == .json {
            config.httpAdditionalHeaders = ["Accept": "application/json"]
        }

        if additionalHeaders != nil {
            config.httpAdditionalHeaders = additionalHeaders
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
        let fullPath = "\(self.baseUrlComponents?.path ?? "")\(path)"
        let url = URL(string: fullPath, relativeTo: self.baseUrl)

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
        case .rawData:
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
        case .rawData:
            guard let data = body as? Data else {
                print("Body not Data")
                return nil
            }
            return data
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
        case .rawData:
            decodedData = data
            break
        }

        return decodedData
    }

    fileprivate func sendRequest(request:URLRequest, onSuccess:@escaping KSHttpSuccessBlock, onFailure:@escaping KSHttpFailureBlock) -> URLSessionDataTask {
        let task = urlSession.dataTask(with: request) { (data, response, error) in
            guard let httpResponse = response as? HTTPURLResponse else {
                onFailure(nil, KSHttpError.responseCastingError, nil)
                return
            }

            if error != nil {
                onFailure(httpResponse, error, nil)
                return
            }

            var decodedBody : Any?

            if let body = data {
                decodedBody = self.decodeBody(body)
            }

            if httpResponse.statusCode > 299 {
                onFailure(httpResponse, KSHttpError.badStatusCode, decodedBody)
                return;
            }

            onSuccess(httpResponse, decodedBody)
        }

        task.resume()

        return task
    }

}

internal struct KSHttpUtil {
    static func urlEncode(_ url: String) -> String? {
        let unreserved = "-._~"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: unreserved)

        let encoded = url.addingPercentEncoding(withAllowedCharacters: allowed)

        return encoded
    }
}
