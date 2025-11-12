//
//  BlackFridayCampaignProvider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Provides utilities to query the Black Friday campaign feature.
public protocol BlackFridayCampaignProviding {
    /// Indicates whether the campaign is currently enabled.
    var isCampaignEnabled: Bool { get }

    /// Returns the discount percent that should be displayed to users.
    var discountPercent: Int { get }
}

/// Default implementation of `BlackFridayCampaignProviding`.
public struct DefaultBlackFridayCampaignProvider: BlackFridayCampaignProviding {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let isFeatureEnabled: () -> Bool
    private let fallbackDiscountPercent: Int

    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                isFeatureEnabled: @escaping () -> Bool,
                fallbackDiscountPercent: Int = 40) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.isFeatureEnabled = isFeatureEnabled
        self.fallbackDiscountPercent = fallbackDiscountPercent
    }

    public var isCampaignEnabled: Bool {
        isFeatureEnabled()
    }

    public var discountPercent: Int {
        guard let settingsString = privacyConfigurationManager.privacyConfig.settings(for: PrivacyProSubfeature.blackFridayCampaign),
              let settingsData = settingsString.data(using: .utf8),
              let settings = try? JSONDecoder().decode(Settings.self, from: settingsData),
              let discount = settings.discountPercent else {
            return fallbackDiscountPercent
        }
        return discount
    }

    private struct Settings: Decodable {
        let discountPercent: Int?

        private enum CodingKeys: String, CodingKey {
            case discountPercent
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let intValue = try? container.decode(Int.self, forKey: .discountPercent) {
                discountPercent = intValue
            } else if let stringValue = try? container.decode(String.self, forKey: .discountPercent),
                      let intValue = Int(stringValue) {
                discountPercent = intValue
            } else if let doubleValue = try? container.decode(Double.self, forKey: .discountPercent) {
                discountPercent = Int(doubleValue.rounded())
            } else {
                discountPercent = nil
            }
        }
    }
}
