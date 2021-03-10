//
//  PendingNotification.swift
//  KumulosSDK
//
//  Created by Vladislav Voicehovics on 09/03/2021.
//  Copyright © 2021 Kumulos. All rights reserved.
//

import Foundation

internal struct PendingNotification: Codable {
    var id: Int
    var deliveredAt: Date
    var identifier: String
    
    init(id: Int, deliveredAt: Date, identifier: String) {
        self.id = id
        self.deliveredAt = deliveredAt
        self.identifier = identifier
    }
}
