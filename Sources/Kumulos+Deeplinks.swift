//
//  Kumulos+Deeplinks.swift
//  KumulosSDK
//
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

public struct DeepLinkContent {
    public let title: String?
    public let message: String?
}

public struct DeepLink {
    public let url: String
    public let content: DeepLinkContent
    public let data: [AnyHashable:Any?]

    init?(for url: String, from jsonData:Data) {
        guard let response = try? JSONSerialization.jsonObject(with: jsonData) as? [AnyHashable:Any],
              let linkData = response["linkData"] as? [AnyHashable:Any?],
              let content = response["content"] as? [AnyHashable:Any?] else {
            return nil
        }

        self.url = url
        self.content = DeepLinkContent(title: content["title"] as? String, message: content["message"] as? String)
        self.data = linkData
    }
}

public enum DeepLinkResolution {
    case lookupFailed
    case linkNotFound(_ url: String)
    case linkExpired(_ url:String)
    case linkLimitExceeded(_ url:String)
    case linkMatched(_ data:DeepLink)
}

public typealias DeepLinkHandler = (DeepLinkResolution) -> Void

class DeepLinkHelper {
    fileprivate static let deferredLinkCheckedKey = "KUMULOS_DDL_CHECKED"

    let config : KSConfig
    let httpClient: KSHttpClient

    init(_ config: KSConfig) {
        self.config = config
        httpClient = KSHttpClient(
            baseUrl: URL(string: "https://links.kumulos.com")!,
            requestFormat: .rawData,
            responseFormat: .rawData,
            additionalHeaders: [
                "Content-Type": "application/json",
                "Accept": "appliction/json"
            ]
        )
        httpClient.setBasicAuth(user: config.apiKey, password: config.secretKey)
    }

    func checkForDeferredLink() {
        if let checked = KeyValPersistenceHelper.object(forKey: DeepLinkHelper.deferredLinkCheckedKey) as? Bool, checked == true {
            return
        }

        var shouldCheck = false
        if #available(iOS 10.0, *) {
            shouldCheck = UIPasteboard.general.hasURLs
        } else {
            shouldCheck = true
        }

        if shouldCheck, let url = UIPasteboard.general.url, urlShouldBeHandled(url) {
            UIPasteboard.general.urls = UIPasteboard.general.urls?.filter({$0 != url})
            self.handleDeepLinkUrl(url)
        }

        KeyValPersistenceHelper.set(true, forKey: DeepLinkHelper.deferredLinkCheckedKey)
    }

    fileprivate func urlShouldBeHandled(_ url: URL) -> Bool {
        guard let host = url.host else {
            return false
        }

        return host.hasSuffix("lnk.click") || host == config.deepLinkCname?.host
    }

    fileprivate func handleDeepLinkUrl(_ url: URL) {
        let slug = KSHttpUtil.urlEncode(url.path.trimmingCharacters(in: ["/"]))

        httpClient.sendRequest(.GET, toPath: "/v1/deeplinks/\(slug ?? "")", data: nil) { (res, data) in
            switch res?.statusCode {
            case 200:
                guard let jsonData = data as? Data,
                      let link = DeepLink(for: url.absoluteString, from: jsonData) else {
                    self.invokeDeepLinkHandler(.lookupFailed)
                    return
                }

                self.invokeDeepLinkHandler(.linkMatched(link))
                break
            default:
                self.invokeDeepLinkHandler(.lookupFailed)
                break
            }
        } onFailure: { (res, err) in
            switch res?.statusCode {
            case 404:
                self.invokeDeepLinkHandler(.linkNotFound(url.absoluteString))
                break
            case 410:
                self.invokeDeepLinkHandler(.linkExpired(url.absoluteString))
                break
            case 429:
                self.invokeDeepLinkHandler(.linkLimitExceeded(url.absoluteString))
                break
            default:
                self.invokeDeepLinkHandler(.lookupFailed)
                break
            }
        }
    }

    fileprivate func invokeDeepLinkHandler(_ resolution: DeepLinkResolution) {
        DispatchQueue.main.async {
            self.config.deepLinkHandler?(resolution)
        }
    }

    @discardableResult
    fileprivate func handleContinuation(for userActivity: NSUserActivity) -> Bool {
        if config.deepLinkHandler == nil {
            print("Kumulos deep link handler not configured, aborting...")
            return false
        }

        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL,
            urlShouldBeHandled(url) else {
            return false
        }

        self.handleDeepLinkUrl(url)
        return true
    }

}

public extension Kumulos {
    static func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return getInstance().deepLinkHelper?.handleContinuation(for: userActivity) ?? false
    }

    @available(iOS 13.0, *)
    static func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        getInstance().deepLinkHelper?.handleContinuation(for: userActivity)
    }
}
