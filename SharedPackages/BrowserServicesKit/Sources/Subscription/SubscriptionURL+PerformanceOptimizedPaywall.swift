//
//  SubscriptionURL+PerformanceOptimizedPaywall.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

extension SubscriptionURL {

    /// The paywall entry points that `performanceOptimizedPaywalls` serves from a pre-rendered page.
    ///
    /// The page is rendered ahead of time, so the decisions it used to make on load — which feature to
    /// emphasise, whether to offer a trial, whether to list Personal Information Removal — have to be
    /// stated in the URL before it opens.
    public enum PerformanceOptimizedPaywallEntryPoint: String, CaseIterable {
        case vpn
        case duckai

        /// Resolves the entry point a `featurePage` query item stands for, or `nil` when the pre-rendered
        /// pages don't cover it (`winback`, say) and today's client-rendered paywall should be kept.
        init?(featurePage: String?) {
            guard let featurePage else {
                self = .vpn
                return
            }
            guard let entryPoint = Self(rawValue: featurePage) else { return nil }
            self = entryPoint
        }
    }

    /// Paths of the pre-rendered paywall pages.
    ///
    /// Remote config supplies these, so the frontend can move the pages without an app release. The
    /// values in ``default`` are the fallback for when config carries no path.
    public struct PerformanceOptimizedPaywallPaths: Equatable {

        public static let `default` = PerformanceOptimizedPaywallPaths(vpn: "/subscriptions/new/mobile/vpn",
                                                                      duckai: "/subscriptions/new/mobile/duckai")

        public let vpn: String
        public let duckai: String

        public init(vpn: String, duckai: String) {
            self.vpn = vpn
            self.duckai = duckai
        }

        public func path(for entryPoint: PerformanceOptimizedPaywallEntryPoint) -> String {
            switch entryPoint {
            case .vpn: vpn
            case .duckai: duckai
            }
        }
    }

    /// Rewrites a first-paywall URL onto its pre-rendered page.
    ///
    /// Reads the entry point off the URL's `featurePage` query item, swaps in that page's path and states
    /// `trial` and — when Personal Information Removal is missing from the offering — `pir`. Every other
    /// query item, `origin` included, is carried over untouched. `featurePage` is dropped: the path now
    /// carries the emphasis.
    ///
    /// - Returns: The rewritten URL, or `nil` when the pre-rendered pages don't cover this URL and the
    ///   caller should keep the one it has.
    public static func performanceOptimizedPaywallURL(basedOn url: URL,
                                                      paths: PerformanceOptimizedPaywallPaths = .default,
                                                      isTrialEligible: Bool,
                                                      isPersonalInformationRemovalAvailable: Bool) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let queryItems = components.queryItems ?? []
        let featurePage = queryItems.first { $0.name == QueryParameter.featurePage }?.value

        guard let entryPoint = PerformanceOptimizedPaywallEntryPoint(featurePage: featurePage) else { return nil }

        components.path = paths.path(for: entryPoint)

        var rewrittenQueryItems = queryItems.filter { $0.name != QueryParameter.featurePage }
        rewrittenQueryItems.append(URLQueryItem(name: QueryParameter.trial, value: String(isTrialEligible)))
        if !isPersonalInformationRemovalAvailable {
            rewrittenQueryItems.append(URLQueryItem(name: QueryParameter.personalInformationRemoval, value: "false"))
        }
        components.queryItems = rewrittenQueryItems

        return components.url
    }
}
