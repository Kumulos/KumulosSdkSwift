//
//  Kumulos+Deeplinks.swift
//  KumulosSDK
//
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

public struct DeepLinkContent {
    public let title: String?
    public let description: String?
}

public struct DeepLink {
    public let url: URL
    public let content: DeepLinkContent
    public let data: [AnyHashable:Any?]

    init?(for url: URL, from jsonData:Data) {
        guard let response = try? JSONSerialization.jsonObject(with: jsonData) as? [AnyHashable:Any],
              let linkData = response["linkData"] as? [AnyHashable:Any?],
              let content = response["content"] as? [AnyHashable:Any?] else {
            return nil
        }

        self.url = url
        self.content = DeepLinkContent(title: content["title"] as? String, description: content["description"] as? String)
        self.data = linkData
    }
}

public enum DeepLinkResolution {
    case lookupFailed(_ url: URL)
    case linkNotFound(_ url: URL)
    case linkExpired(_ url:URL)
    case linkLimitExceeded(_ url:URL)
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
            self.handleDeepLinkUrl(url, wasDeferred: true)
        }

        KeyValPersistenceHelper.set(true, forKey: DeepLinkHelper.deferredLinkCheckedKey)
    }

    fileprivate func urlShouldBeHandled(_ url: URL) -> Bool {
        guard let host = url.host else {
            return false
        }

        return host.hasSuffix("lnk.click") || host == config.deepLinkCname?.host
    }

    fileprivate func handleDeepLinkUrl(_ url: URL, wasDeferred: Bool = false) {
        let slug = KSHttpUtil.urlEncode(url.path.trimmingCharacters(in: ["/"]))

        let path = "/v1/deeplinks/\(slug ?? "")?wasDeferred=\(wasDeferred ? 1 : 0)"

        httpClient.sendRequest(.GET, toPath: path, data: nil, onSuccess:  { (res, data) in
            switch res?.statusCode {
            case 200:
                guard let jsonData = data as? Data,
                      let link = DeepLink(for: url, from: jsonData) else {
                    self.invokeDeepLinkHandler(.lookupFailed(url))
                    return
                }

                self.invokeDeepLinkHandler(.linkMatched(link))

                let linkProps = ["url": url.absoluteString, "wasDeferred": wasDeferred] as [String : Any]
                Kumulos.getInstance().analyticsHelper.trackEvent(eventType: KumulosEvent.DEEP_LINK_MATCHED.rawValue, properties: linkProps, immediateFlush: false)
                break
            default:
                self.invokeDeepLinkHandler(.lookupFailed(url))
                break
            }
        }, onFailure: { (res, err) in
            switch res?.statusCode {
            case 404:
                self.invokeDeepLinkHandler(.linkNotFound(url))
                break
            case 410:
                self.invokeDeepLinkHandler(.linkExpired(url))
                break
            case 429:
                self.invokeDeepLinkHandler(.linkLimitExceeded(url))
                break
            default:
                self.invokeDeepLinkHandler(.lookupFailed(url))
                break
            }
        })
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
