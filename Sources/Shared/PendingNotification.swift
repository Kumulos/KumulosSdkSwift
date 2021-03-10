//
//  PendingNotification.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 09/03/2021.
//  Copyright © 2021 Kumulos. All rights reserved.
//

import Foundation

public struct PendingNotification: Codable, Equatable {
    public var id: Int
    public var deliveredAt: Date
    
    public init(id: Int, deliveredAt: Date) {
        self.id = id
        self.deliveredAt = deliveredAt
    }
    
    public static func == (lhs: PendingNotification, rhs: PendingNotification) -> Bool {
        return lhs.id == rhs.id
    }
}
