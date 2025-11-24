//
//  StoreSubscriptionConfiguration.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine

/// Constants relating to `StoreSubscriptionConfiguration`
enum StoreSubscriptionConstants {
    /// The Free Trial identifer included as part of a Subscription identifier, used to indicate that the subscription includes a free trial.
    static let freeTrialIdentifer = "freetrial"
    static let proTierIdentifier = "pro"
}

protocol StoreSubscriptionConfiguration {
    var allSubscriptionIdentifiers: [String] { get }
    func subscriptionIdentifiers(for country: String) -> [String]
    func subscriptionIdentifiers(for region: SubscriptionRegion) -> [String]
}

final class DefaultStoreSubscriptionConfiguration: StoreSubscriptionConfiguration {

    private let subscriptions: [StoreSubscriptionDefinition]

    convenience init() {
        self.init(subscriptionDefinitions: [
            // Production shared for iOS and macOS
            .init(name: "DuckDuckGo Private Browser",
                  appIdentifier: "com.duckduckgo.mobile.ios",
                  environment: .production,
                  identifiersByRegion: [.usa: ["ddg.privacy.pro.monthly.renews.us.freetrial",
                                               "ddg.privacy.pro.yearly.renews.us.freetrial",
                                               "ddg.subscription.monthly.renews.us.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                               "ddg.subscription.yearly.renews.us.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"],
                                        .restOfWorld: ["ddg.privacy.pro.monthly.renews.row.freetrial",
                                                       "ddg.privacy.pro.yearly.renews.row.freetrial",
                                                       "ddg.subscription.monthly.renews.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                                       "ddg.subscription.yearly.renews.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"]]),
            // iOS debug Alpha build
            .init(name: "DuckDuckGo Alpha",
                  appIdentifier: "com.duckduckgo.mobile.ios.alpha",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["ios.subscription.1month.freetrial.dev",
                                               "ios.subscription.1year.freetrial.dev",
                                               "ios.subscription.1month.freetrial.dev.\(StoreSubscriptionConstants.proTierIdentifier)",
                                               "ios.subscription.1year.freetrial.dev.\(StoreSubscriptionConstants.proTierIdentifier)"],
                                        .restOfWorld: ["ios.subscription.1month.row.freetrial.dev",
                                                       "ios.subscription.1year.row.freetrial.dev",
                                                       "ios.subscription.1month.row.freetrial.dev.\(StoreSubscriptionConstants.proTierIdentifier)",
                                                       "ios.subscription.1year.row.freetrial.dev.\(StoreSubscriptionConstants.proTierIdentifier)"]]),
            // macOS debug build
            .init(name: "IAP debug - DDG for macOS",
                  appIdentifier: "com.duckduckgo.macos.browser.debug",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["subscription.1month.freetrial",
                                               "subscription.1year.freetrial",
                                               "subscription.1month.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                               "subscription.1year.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"],
                                        .restOfWorld: ["subscription.1month.row.freetrial",
                                                       "subscription.1year.row.freetrial",
                                                       "subscription.1month.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                                       "subscription.1year.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"]]),
            // macOS review build
            .init(name: "IAP review - DDG for macOS",
                  appIdentifier: "com.duckduckgo.macos.browser.review",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["review.subscription.1month.freetrial",
                                               "review.subscription.1year.freetrial",
                                               "review.subscription.1month.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                               "review.subscription.1year.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"],
                                        .restOfWorld: ["review.subscription.1month.row.freetrial",
                                                       "review.subscription.1year.row.freetrial",
                                                       "review.subscription.1month.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                                       "review.subscription.1year.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"]]),

            // macOS TestFlight build
            .init(name: "DuckDuckGo Sandbox Review",
                  appIdentifier: "com.duckduckgo.mobile.ios.review",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["tf.sandbox.subscription.1month.freetrial",
                                               "tf.sandbox.subscription.1year.freetrial",
                                               "tf.sandbox.subscription.1month.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                               "tf.sandbox.subscription.1year.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"],
                                        .restOfWorld: ["tf.sandbox.subscription.1month.row.freetrial",
                                                       "tf.sandbox.subscription.1year.row.freetrial",
                                                       "tf.sandbox.subscription.1month.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)",
                                                       "tf.sandbox.subscription.1year.row.freetrial.\(StoreSubscriptionConstants.proTierIdentifier)"]])
        ])
    }

    init(subscriptionDefinitions: [StoreSubscriptionDefinition]) {
        self.subscriptions = subscriptionDefinitions
    }

    var allSubscriptionIdentifiers: [String] {
        subscriptions.reduce([], { $0 + $1.allIdentifiers() })
    }

    func subscriptionIdentifiers(for country: String) -> [String] {
        subscriptions.reduce([], { $0 + $1.identifiers(for: country) })
    }

    func subscriptionIdentifiers(for region: SubscriptionRegion) -> [String] {
        subscriptions.reduce([], { $0 + $1.identifiers(for: region) })
    }
}

struct StoreSubscriptionDefinition {
    var name: String
    var appIdentifier: String
    var environment: SubscriptionEnvironment.ServiceEnvironment
    var identifiersByRegion: [SubscriptionRegion: [String]]

    func allIdentifiers() -> [String] {
        identifiersByRegion.values.flatMap { $0 }
    }

    func identifiers(for country: String) -> [String] {
        identifiersByRegion.filter { region, _ in region.contains(country) }.flatMap { _, identifiers in identifiers }
    }

    func identifiers(for region: SubscriptionRegion) -> [String] {
        identifiersByRegion[region] ?? []
    }
}

public enum SubscriptionRegion: CaseIterable {
    case usa
    case restOfWorld

    /// Country codes as used by StoreKit, in the ISO 3166-1 Alpha-3 country code representation
    /// For .restOfWorld definiton see https://app.asana.com/0/1208524871249522/1208571752166956/f
    var countryCodes: Set<String> {
        switch self {
        case .usa:
            return Set(["USA"])
        case .restOfWorld:
            return Set(["CAN", "GBR", "AUT", "DEU", "NLD", "POL", "SWE",
                        "BEL", "BGR", "HRV ", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "GRC", "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "PRT",
                        "ROU", "SVK", "SVN", "ESP"])
        }
    }

    func contains(_ country: String) -> Bool {
        countryCodes.contains(country.uppercased())
    }

    static func matchingRegion(for countryCode: String) -> Self? {
        Self.allCases.first { $0.countryCodes.contains(countryCode) }
    }
}
