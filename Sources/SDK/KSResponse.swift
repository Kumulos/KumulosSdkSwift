//
//  KSResponse.swift
//  Copyright © 2016 Kumulos. All rights reserved.
//

import Foundation

open class KSResponse: NSObject {
    internal(set) open var payload: AnyObject?
    internal(set) open var requestProcessingTime: Float?
    internal(set) open var requestReceivedTime: Float?
    internal(set) open var responseCode: UInt32?
    internal(set) open var responseMessage: String?
    internal(set) open var timestamp: NSNumber?
}
