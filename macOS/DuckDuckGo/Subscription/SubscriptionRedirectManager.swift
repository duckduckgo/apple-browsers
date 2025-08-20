//
//  SubscriptionRedirectManager.swift
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

import AppKit
import BrowserServicesKit
import Common
import Foundation
import Subscription

protocol SubscriptionRedirectManager: AnyObject {
    func redirectURL(for url: URL) -> URL?
}

final class PrivacyProSubscriptionRedirectManager: SubscriptionRedirectManager {

    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let baseURL: URL
    private let tld: TLD
    private let featureFlagger: FeatureFlagger

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         baseURL: URL,
         tld: TLD = Application.appDelegate.tld,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.subscriptionManager = subscriptionManager
        self.baseURL = baseURL
        self.tld = tld
        self.featureFlagger = featureFlagger
    }

    func redirectURL(for url: URL) -> URL? {
        guard url.isPart(ofDomain: "duckduckgo.com") ||
              (url.isPart(ofDomain: "duck.co") && featureFlagger.internalUserDecider.isInternalUser)
        else { return nil }

        if url.pathComponents == URL.privacyPro.pathComponents {
            let shouldHidePrivacyProDueToNoProducts = subscriptionManager.currentEnvironment.purchasePlatform == .appStore && subscriptionManager.canPurchase == false
            let isPurchasePageRedirectActive = !shouldHidePrivacyProDueToNoProducts

            // Redirect the `/pro` URL to `/subscriptions` URL. If there are any query items in the original URL it appends to the `/subscriptions` URL.
            if isPurchasePageRedirectActive,
               let redirectURLComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                return subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: tld)
            }
        }

        return nil
    }
}
