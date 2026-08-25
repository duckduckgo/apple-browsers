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
import PrivacyConfig
import Common
import FoundationExtensions
import Subscription

protocol TabURLInterceptor {
    func allowsNavigatingTo(url: URL) -> Bool
}

final class TabURLInterceptorDefault: TabURLInterceptor {
    
    typealias CanPurchaseUpdater = () -> Bool
    private let canPurchase: CanPurchaseUpdater
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger,
         canPurchase: @escaping CanPurchaseUpdater
    ) {
        self.canPurchase = canPurchase
        self.featureFlagger = featureFlagger
    }

    static let interceptedURLs = SubscriptionPurchaseFlowPath.allCases.map(\.rawValue)
    
    func allowsNavigatingTo(url: URL) -> Bool {
        guard url.isPart(ofDomain: "duckduckgo.com") || (url.isPart(ofDomain: "duck.co") && featureFlagger.internalUserDecider.isInternalUser),
              let components = normalizeScheme(url.absoluteString),
              Self.interceptedURLs.contains(components.path) else {
            return true
        }

        return interceptSubscriptionURL(components)
    }

}

extension TabURLInterceptorDefault {
    
    private func normalizeScheme(_ rawUrl: String) -> URLComponents? {
        if !rawUrl.starts(with: URL.NavigationalScheme.https.separated()) &&
           !rawUrl.starts(with: URL.NavigationalScheme.http.separated()) &&
           rawUrl.contains("://") {
            return nil
        }
        let noScheme = rawUrl.dropping(prefix: URL.NavigationalScheme.https.separated()).dropping(prefix: URL.NavigationalScheme.http.separated())

        return URLComponents(string: "\(URL.NavigationalScheme.https.separated())\(noScheme)")
    }

    private func interceptSubscriptionURL(_ components: URLComponents) -> Bool {
        guard canPurchase() else {
            return true
        }

        NotificationCenter.default.post(
            name: .urlInterceptSubscription,
            object: nil,
            userInfo: [TabURLInterceptorParameter.interceptedURLComponents: components]
        )
        return false
    }
}

extension NSNotification.Name {
    static let urlInterceptSubscription: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.urlInterceptSubscription")
    static let urlInterceptAIChat: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.urlInterceptAIChat")
}

public enum TabURLInterceptorParameter {
    public static let interceptedURLComponents = "interceptedURLComponents"
    /// Set only by the front-end `openAIChat` message, never by the interceptor: the page that asked
    /// native to open Duck.ai, so its entry is attributed to that page rather than to a typed address.
    public static let aiChatRequestHost = "aiChatRequestHost"
}
