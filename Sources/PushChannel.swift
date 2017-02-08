//
//  PushChannel.swift
//  KumulosSDK
//
//  Created by Andy on 07/02/2017.
//  Copyright © 2017 Kumulos. All rights reserved.
//

import Foundation

open class PushChannel: NSObject {
    internal(set) open var name: String? = nil
    internal(set) open var uuid: String = ""
    internal(set) open var meta: Dictionary<String, AnyObject>? = nil
    internal(set) open var isSubscribed: Bool = false
}
