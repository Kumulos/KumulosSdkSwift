//
//  KumulosPushChannels.swift
//  KumulosSDK
//
//  Created by Andy on 07/02/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation
import Alamofire

public typealias PushChannelSubscriptionSuccessBlock = (()->Void)?
public typealias PushChannelSubscriptionFailureBlock = ((Error?)->Void)?

public class KumulosPushChannelSubscriptionRequest {
    var successBlock:PushChannelSubscriptionSuccessBlock?
    var failureBlock:PushChannelSubscriptionFailureBlock?
    
    open func success(_ success:PushChannelSubscriptionSuccessBlock) -> KumulosPushChannelSubscriptionRequest {
        successBlock = success
        return self
    }
    
    open func failure(_ failure:PushChannelSubscriptionFailureBlock) -> KumulosPushChannelSubscriptionRequest {
        failureBlock = failure
        return self
    }
}

public typealias PushChannelSuccessBlock = (([PushChannel])->Void)?
public typealias PushChannelFailureBlock = ((Error?)->Void)?

public class KumulosPushChannelRequest {
    var successBlock:PushChannelSuccessBlock?
    var failureBlock:PushChannelFailureBlock?
    
    open func success(_ success:PushChannelSuccessBlock) -> KumulosPushChannelRequest {
        successBlock = success
        return self
    }
    
    open func failure(_ failure:PushChannelFailureBlock) -> KumulosPushChannelRequest {
        failureBlock = failure
        return self
    }
}

public class KumulosPushChannels {
   
    fileprivate(set) var sdkInstance: Kumulos
    
    public init(sdkInstance: Kumulos)     {
        self.sdkInstance = sdkInstance;
    }
    
    public func listChannels() -> KumulosPushChannelRequest {
        let request = KumulosPushChannelRequest()
        let url =  "\(sdkInstance.basePushUrl)app-installs/\(Kumulos.installId)/channels"
        
        sdkInstance.makeNetworkRequest(.get, url: url, parameters: [:])
        .validate(statusCode: 200..<300)
        .validate(contentType: ["application/json"])
        .responseJSON { response in
            switch response.result {
                case .success:
                    if let successBlock = request.successBlock {
                        successBlock?(self.readChannelsFromResponse(jsonResponse: (response.result.value as! [[String : AnyObject]])))
                    }
                case .failure(let error):
                    if let failureBlock = request.failureBlock {
                        failureBlock?(error)
                    }
            }
        }
        return request
    }
    
    public func createChannel(uuid: String, subscribe: Bool, name: String? = nil, meta: [String:AnyObject]? = nil) -> KumulosPushChannelRequest {
        return doCreateChannel(uuid: uuid, subscribe: subscribe, name: name, showInPortal: false, meta: meta)
    }
    
    
    public func createChannel(uuid: String, subscribe: Bool, name: String, showInPortal: Bool, meta: [String:AnyObject]? = nil) -> KumulosPushChannelRequest {
        return doCreateChannel(uuid: uuid, subscribe: subscribe, name: name, showInPortal: showInPortal, meta: meta)
    }
    
    
    private func doCreateChannel(uuid: String, subscribe: Bool, name: String? = nil, showInPortal: Bool, meta: [String:AnyObject]? = nil) -> KumulosPushChannelRequest
    {
        let request = KumulosPushChannelRequest()
        let url =  "\(sdkInstance.basePushUrl)channels"
        
        var parameters = [
            "uuid": uuid,
            "showInPortal": showInPortal
        ] as [String: Any];

        if (name != nil) {
            parameters["name"] = name
        }
        
        if (meta != nil) {
            parameters["meta"] = meta
        }
        
        if (subscribe == true) {
            parameters["installId"] = Kumulos.installId
        }
        
        sdkInstance.makeJsonNetworkRequest(.post, url: url, parameters: parameters as [String : AnyObject])
        .validate(statusCode: 200..<300)
        .validate(contentType: ["application/json"])
        .responseJSON { response in
            switch response.result {
                case .success:
                    if let successBlock = request.successBlock {
                        successBlock?([self.getChannelFromPayload(payload: (response.result.value as! [String : AnyObject]))])
                    }
                case .failure(let error):
                    if let failureBlock = request.failureBlock {
                        failureBlock?(error)
                    }
            }
        }
        return request

    }
    
    private func readChannelsFromResponse(jsonResponse: [[String : AnyObject]]) -> [PushChannel] {
        var channels = [PushChannel]();
        
        for item in jsonResponse {
            channels.append(getChannelFromPayload(payload: item))
        }
        
        return channels
    }
    
    private func getChannelFromPayload(payload: [String:AnyObject]) -> PushChannel {
        let channel = PushChannel()
                
        channel.uuid = payload["uuid"] as! String
        channel.isSubscribed = payload["subscribed"] as! Bool
        
        if let name = payload["name"] as? String {
            channel.name = name
        }
        
        if let meta = payload["meta"] as? Dictionary<String, AnyObject> {
            channel.meta = meta
        }
        
        return channel
    }
    
    public func subscribe(uuids: [String]) -> KumulosPushChannelSubscriptionRequest {
        let parameters = [
            "uuids": uuids
        ];
        
        return makeSubscriptionNetworkCall(.post, parameters: parameters as [String:AnyObject])
    }
    
    public func unsubscribe(uuids: [String]) -> KumulosPushChannelSubscriptionRequest {
        let parameters = [
            "uuids": uuids
        ];
        
        return makeSubscriptionNetworkCall(.delete, parameters: parameters as [String:AnyObject])
    }
    
    public func setSubscriptions(uuids: [String]) -> KumulosPushChannelSubscriptionRequest {
        let parameters = [
            "uuids": uuids
        ];
        
        return makeSubscriptionNetworkCall(.put, parameters: parameters as [String:AnyObject]);
    }

    private func makeSubscriptionNetworkCall(_ method: Alamofire.HTTPMethod, parameters: [String:AnyObject])
        -> KumulosPushChannelSubscriptionRequest
    {
        let url =  "\(sdkInstance.basePushUrl)/app-installs/\(Kumulos.installId)/channels/subscriptions"
        
        return makeNetworkCall(method: method, url: url, parameters: parameters)
    }
    
    private func makeNetworkCall(method: Alamofire.HTTPMethod, url: URLConvertible, parameters: [String : AnyObject]) -> KumulosPushChannelSubscriptionRequest{
        
        let request = KumulosPushChannelSubscriptionRequest()
        
        sdkInstance.makeNetworkRequest(.post, url: url, parameters: parameters as [String : AnyObject])
        .validate(statusCode: 200..<300)
        .responseData { response in
            switch response.result {
                case .success:
                    if let successBlock = request.successBlock {
                        successBlock?()
                    }
                case .failure(let error):
                    if let failureBlock = request.failureBlock {
                        failureBlock?(error)
                    }
            }
        }
        return request
    }
}
