//
//  UrlBuilder.swift
//  KumulosSDK
//  Copyright © 2021 Kumulos. All rights reserved.
//

import Foundation

public enum Service : CaseIterable {
    case backend
    case crash
    case crm
    case ddl
    case events
    case iar
    case media
    case push
}

public typealias ServiceUrlMap = [Service:String]

class UrlBuilder {
    let baseUrlMap : ServiceUrlMap

    init(baseUrlMap:ServiceUrlMap) {
        for s in Service.allCases {
            if baseUrlMap[s] == nil {
                fatalError("baseUrlMap must contain an entry for all Service cases")
            }
        }

        self.baseUrlMap = baseUrlMap
    }

    func urlForService(_ service:Service) -> String {
        let baseUrl = baseUrlMap[service]!
        return baseUrl
    }

    static func defaultMapping() -> ServiceUrlMap {
        return [
            .backend : "https://api.kumulos.com",
            .crash : "https://crash.kumulos.com",
            .crm : "https://crm.kumulos.com",
            .ddl : "https://links.kumulos.com",
            .events : "https://events.kumulos.com",
            .iar : "https://iar.app.delivery",
            .media : "https://i.app.delivery",
            .push : "https://push.kumulos.com"
        ]
    }
}
