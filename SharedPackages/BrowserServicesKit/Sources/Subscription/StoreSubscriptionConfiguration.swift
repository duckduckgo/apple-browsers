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
                  identifiersByRegion: [.usa: ["ddg.privacy.pro.monthly.renews.us",
                                               "ddg.privacy.pro.yearly.renews.us",
                                               "ddg.privacy.pro.monthly.renews.us.\(StoreSubscriptionConstants.freeTrialIdentifer)",
                                               "ddg.privacy.pro.yearly.renews.us.\(StoreSubscriptionConstants.freeTrialIdentifer)"],
                                        .restOfWorld: ["ddg.privacy.pro.monthly.renews.row",
                                                       "ddg.privacy.pro.yearly.renews.row",
                                                       "ddg.privacy.pro.monthly.renews.row.\(StoreSubscriptionConstants.freeTrialIdentifer)",
                                                       "ddg.privacy.pro.yearly.renews.row.\(StoreSubscriptionConstants.freeTrialIdentifer)"]]),
            // iOS debug Alpha build
            .init(name: "DuckDuckGo Alpha",
                  appIdentifier: "com.duckduckgo.mobile.ios.alpha",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["ios.subscription.1month",
                                               "ios.subscription.1year",
                                               "ios.subscription.1month.\(StoreSubscriptionConstants.freeTrialIdentifer).dev",
                                               "ios.subscription.1year.\(StoreSubscriptionConstants.freeTrialIdentifer).dev"],
                                        .restOfWorld: ["ios.subscription.1month.row",
                                                       "ios.subscription.1year.row",
                                                       "ios.subscription.1month.row.\(StoreSubscriptionConstants.freeTrialIdentifer).dev",
                                                       "ios.subscription.1year.row.\(StoreSubscriptionConstants.freeTrialIdentifer).dev"]]),
            // macOS debug build
            .init(name: "IAP debug - DDG for macOS",
                  appIdentifier: "com.duckduckgo.macos.browser.debug",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["subscription.1month",
                                               "subscription.1year"],
                                        .restOfWorld: ["subscription.1month.row",
                                                       "subscription.1year.row"]]),
            // macOS review build
            .init(name: "IAP review - DDG for macOS",
                  appIdentifier: "com.duckduckgo.macos.browser.review",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["review.subscription.1month",
                                               "review.subscription.1year"],
                                        .restOfWorld: ["review.subscription.1month.row",
                                                       "review.subscription.1year.row"]]),

            // macOS TestFlight build
            .init(name: "DuckDuckGo Sandbox Review",
                  appIdentifier: "com.duckduckgo.mobile.ios.review",
                  environment: .staging,
                  identifiersByRegion: [.usa: ["tf.sandbox.subscription.1month",
                                               "tf.sandbox.subscription.1year"],
                                        .restOfWorld: ["tf.sandbox.subscription.1month.row",
                                                       "tf.sandbox.subscription.1year.row"]])
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
