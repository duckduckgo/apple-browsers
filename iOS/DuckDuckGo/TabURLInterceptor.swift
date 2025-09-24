//
//  TabURLInterceptor.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import BrowserServicesKit
import Common
import Subscription
import AIChat

enum InterceptedURLType: String {
    case privacyPro
    case aiChat
}

struct InterceptedURLInfo {
    let id: InterceptedURLType
    let path: String
}

protocol TabURLInterceptor {
    func allowsNavigatingTo(url: URL) -> Bool
}

final class TabURLInterceptorDefault: TabURLInterceptor {
    
    typealias CanPurchaseUpdater = () -> Bool
    private let canPurchase: CanPurchaseUpdater
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger, canPurchase: @escaping CanPurchaseUpdater) {
        self.canPurchase = canPurchase
        self.featureFlagger = featureFlagger
    }

    static let interceptedURLs: [InterceptedURLInfo] = [
        InterceptedURLInfo(id: .privacyPro, path: "/pro")
    ]
    
    func allowsNavigatingTo(url: URL) -> Bool {
        if url.isDuckAIURL {
            return handleURLInterception(interceptedURLType: .aiChat)
        }

        guard url.isPart(ofDomain: "duckduckgo.com") || (url.isPart(ofDomain: "duck.co") && featureFlagger.internalUserDecider.isInternalUser),
              let components = normalizeScheme(url.absoluteString),
              let matchingURL = urlToIntercept(path: components.path) else {
            return true
        }

        return handleURLInterception(interceptedURLType: matchingURL.id, interceptedURLComponents: components)
    }

}

extension TabURLInterceptorDefault {
    
    private func urlToIntercept(path: String) -> InterceptedURLInfo? {
        let results = Self.interceptedURLs.filter { $0.path == path }
        return results.first
    }
    
    private func normalizeScheme(_ rawUrl: String) -> URLComponents? {
        if !rawUrl.starts(with: URL.URLProtocol.https.scheme) &&
           !rawUrl.starts(with: URL.URLProtocol.http.scheme) &&
           rawUrl.contains("://") {
            return nil
        }
        let noScheme = rawUrl.dropping(prefix: URL.URLProtocol.https.scheme).dropping(prefix: URL.URLProtocol.http.scheme)
        
        return URLComponents(string: "\(URL.URLProtocol.https.scheme)\(noScheme)")
    }

    private func handleURLInterception(interceptedURLType: InterceptedURLType, interceptedURLComponents: URLComponents? = nil) -> Bool {
        switch interceptedURLType {
            // Opens the Privacy Pro Subscription Purchase page (if user can purchase)
        case .privacyPro:
            if canPurchase() {
                // We pass `interceptedURLComponents` to properly resolve final purchase URL
                // and to capture `origin` query parameter as it is needed for the Pixel to track subscription attributions
                var userInfo: [AnyHashable: Any]?

                if let components = interceptedURLComponents {
                    userInfo = [TabURLInterceptorParameter.interceptedURLComponents: interceptedURLComponents as Any]
                }

                NotificationCenter.default.post(
                    name: .urlInterceptSubscription,
                    object: nil,
                    userInfo: userInfo
                )
                return false
            }
        case .aiChat:
            NotificationCenter.default.post(
                name: .urlInterceptAIChat,
                object: nil,
                userInfo: nil
            )
            return false
        }
        return true
    }
}

extension NSNotification.Name {
    static let urlInterceptSubscription: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.urlInterceptSubscription")
    static let urlInterceptAIChat: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.urlInterceptAIChat")
}

public enum TabURLInterceptorParameter {
    public static let interceptedURLComponents = "interceptedURLComponents"
}
