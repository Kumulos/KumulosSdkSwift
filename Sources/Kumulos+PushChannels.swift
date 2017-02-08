//
//  Kumulos+PushChannels.swift
//  KumulosSDK
//
//  Created by Andy on 07/02/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation
import Alamofire

public typealias PushChannelSubscriptionSuccessBlock = (()->Void)?
public typealias PushChannelSubscriptionFailureBlock = ((Error?)->Void)?

public class KumulosPushChannelSubscriptionOperation {
    var successBlock:PushChannelSubscriptionSuccessBlock?
    var failureBlock:PushChannelSubscriptionFailureBlock?
    
    open func success(_ success:PushChannelSubscriptionSuccessBlock) -> KumulosPushChannelSubscriptionOperation {
        successBlock = success
        return self
    }
    
    open func failure(_ failure:PushChannelSubscriptionFailureBlock) -> KumulosPushChannelSubscriptionOperation {
        failureBlock = failure
        return self
    }
}

public typealias PushChannelSuccessBlock = (([PushChannel])->Void)?
public typealias PushChannelFailureBlock = ((Error?)->Void)?

public class KumulosPushChannelOperation {
    var successBlock:PushChannelSuccessBlock?
    var failureBlock:PushChannelFailureBlock?
    
    open func success(_ success:PushChannelSuccessBlock) -> KumulosPushChannelOperation {
        successBlock = success
        return self
    }
    
    open func failure(_ failure:PushChannelFailureBlock) -> KumulosPushChannelOperation {
        failureBlock = failure
        return self
    }
}

public class KumulosPushChannels {
   
    fileprivate(set) var sdkInstance: Kumulos
    
    public init(sdkInstance: Kumulos)     {
        self.sdkInstance = sdkInstance;
    }
    
    public func listChannels() -> KumulosPushChannelOperation {
        let operation = KumulosPushChannelOperation()
        let url =  "\(sdkInstance.basePushUrl)app-installs/\(Kumulos.installId)/channels"
        
        _ = sdkInstance.makeNetworkRequest(.get, url: url, parameters: [:])
            .validate(statusCode: 200..<300)
            .validate(contentType: ["application/json"])
            .responseJSON { response in
                switch response.result {
                case .success:
                    if let successBlock = operation.successBlock {
                        successBlock?(self.readChannelsFromResponse(jsonResponse: (response.result.value as! [[String : AnyObject]])))
                    }
                case .failure(let error):
                    if let failureBlock = operation.failureBlock {
                        failureBlock?(error)
                    }
                }
        }
        return operation
    }
    
    private func readChannelsFromResponse(jsonResponse: [[String : AnyObject]]) -> [PushChannel] {
        var channels = [PushChannel]();
        
        for item in jsonResponse {
            let channel = PushChannel()
            channel.name = item["name"] as! String
            channel.uuid = item["uuid"] as! String
            channel.isSubscribed = item["subscribed"] as! Bool
            
            if let meta = item["meta"] as? Dictionary<String, AnyObject> {
                channel.meta = meta
            }
            
            channels.append(channel);
        }
        
        
        return channels;
    }
    
    public func subscribe(uuids: [String]) -> KumulosPushChannelSubscriptionOperation {
        let parameters = [
            "uuids": uuids
        ];
        
        return makeSubscriptionNetworkCall(.post, parameters: parameters as [String:AnyObject])
    }
    
    public func unsubscribe(uuids: [String]) -> KumulosPushChannelSubscriptionOperation {
        let parameters = [
            "uuids": uuids
        ];
        
        return makeSubscriptionNetworkCall(.delete, parameters: parameters as [String:AnyObject])
    }
    
    public func setSubscriptions(uuids: [String]) -> KumulosPushChannelSubscriptionOperation {
        let parameters = [
            "uuids": uuids
        ];
        
        return makeSubscriptionNetworkCall(.put, parameters: parameters as [String:AnyObject]);
    }

    private func makeSubscriptionNetworkCall(_ method: Alamofire.HTTPMethod, parameters: [String:AnyObject])
        -> KumulosPushChannelSubscriptionOperation
    {
        let url =  "\(sdkInstance.basePushUrl)/app-installs/\(Kumulos.installId)/channels/subscriptions"
        
        return makeNetworkCall(method: method, url: url, parameters: parameters)
    }
    
    private func makeNetworkCall(method: Alamofire.HTTPMethod, url: URLConvertible, parameters: [String : AnyObject]) -> KumulosPushChannelSubscriptionOperation{
        
        let operation = KumulosPushChannelSubscriptionOperation()
        
        _ = sdkInstance.makeNetworkRequest(.post, url: url, parameters: parameters as [String : AnyObject])
            .validate(statusCode: 200..<300)
            .responseData { response in
                switch response.result {
                case .success:
                    if let successBlock = operation.successBlock {
                        successBlock?()
                    }
                case .failure(let error):
                    if let failureBlock = operation.failureBlock {
                        failureBlock?(error)
                    }
                }
        }
        return operation
    }
}

