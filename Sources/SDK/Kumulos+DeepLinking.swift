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
    var anyContinuationHandled : Bool

    init(_ config: KSConfig, urlBuilder:UrlBuilder) {
        self.config = config
        httpClient = KSHttpClient(
            baseUrl: URL(string: urlBuilder.urlForService(.ddl))!,
            requestFormat: .rawData,
            responseFormat: .rawData,
            additionalHeaders: [
                "Content-Type": "application/json",
                "Accept": "appliction/json"
            ]
        )
        httpClient.setBasicAuth(user: config.apiKey, password: config.secretKey)
        self.anyContinuationHandled = false
    }

    func checkForNonContinuationLinkMatch() {
        if (checkForDeferredLinkOnClipboard()) {
            return
        }

        NotificationCenter.default.addObserver(self, selector: #selector(self.appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc func appBecameActive() {
        NotificationCenter.default.removeObserver(self)

        if (self.anyContinuationHandled) {
            return
        }

        self.checkForWebToAppBannerTap()
    }

    fileprivate func checkForDeferredLinkOnClipboard() -> Bool {
        var handled = false;

        if let checked = KeyValPersistenceHelper.object(forKey: DeepLinkHelper.deferredLinkCheckedKey) as? Bool, checked == true {
            return handled
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
            handled = true
        }

        KeyValPersistenceHelper.set(true, forKey: DeepLinkHelper.deferredLinkCheckedKey)

        return handled
    }

    fileprivate func checkForWebToAppBannerTap() {
        let fp = DeepLinkFingerprinter()

        fp.getFingerprintComponents { components in
            DispatchQueue.global().async {
                self.handleFingerprintComponents(components: components)
            }
        }
    }

    fileprivate func urlShouldBeHandled(_ url: URL) -> Bool {
        guard let host = url.host else {
            return false
        }

        return host.hasSuffix("lnk.click") || host == config.deepLinkCname?.host
    }

    fileprivate func handleDeepLinkUrl(_ url: URL, wasDeferred: Bool = false) {
        let slug = KSHttpUtil.urlEncode(url.path.trimmingCharacters(in: ["/"]))

        var path = "/v1/deeplinks/\(slug ?? "")?wasDeferred=\(wasDeferred ? 1 : 0)"
        if let query = url.query {
            path = path + "&" + query
        }
        
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
        }, onFailure: { (res, err, data) in
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

    fileprivate func handleFingerprintComponents(components: [String:String]) {
        guard let componentJson = try? JSONSerialization.data(withJSONObject: components, options: JSONSerialization.WritingOptions.init(rawValue: 0)),
              let encodedComponents = KSHttpUtil.urlEncode(componentJson.base64EncodedString()) else {
            return
        }

        let path = "/v1/deeplinks/_taps?fingerprint=\(encodedComponents)"

        httpClient.sendRequest(.GET, toPath: path, data: nil, onSuccess:  { (res, data) in
            switch res?.statusCode {
            case 200:
                guard let jsonData = data as? Data,
                      let response = try? JSONSerialization.jsonObject(with: jsonData) as? [AnyHashable:Any],
                      let urlString = response["linkUrl"] as? String,
                      let url = URL(string: urlString),
                      let link = DeepLink(for: url, from: jsonData) else {
                    // Fingerprint matches that fail to parse correctly can't know the URL so
                    // don't invoke any error handler.
                    return
                }

                self.invokeDeepLinkHandler(.linkMatched(link))

                let linkProps = ["url": url.absoluteString, "wasDeferred": false] as [String : Any]
                Kumulos.getInstance().analyticsHelper.trackEvent(eventType: KumulosEvent.DEEP_LINK_MATCHED.rawValue, properties: linkProps, immediateFlush: false)
                break
            default:
                // Noop
                break
            }
        }, onFailure: { (res, err, data) in
            guard let jsonData = data as? Data,
                  let response = try? JSONSerialization.jsonObject(with: jsonData) as? [AnyHashable:Any],
                  let urlString = response["linkUrl"] as? String,
                  let url = URL(string: urlString) else {
                return
            }

            switch res?.statusCode {
            case 410:
                self.invokeDeepLinkHandler(.linkExpired(url))
                break
            case 429:
                self.invokeDeepLinkHandler(.linkLimitExceeded(url))
                break
            default:
                // Noop
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

        anyContinuationHandled = true;

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
