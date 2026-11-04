//
//  TabEvictionSettings.swift
//  DuckDuckGo
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

import FeatureFlags_iOS
import Foundation
import PrivacyConfig

struct TabEvictionSettings {

    private enum Constants {
        static let defaultPhoneCapacity = 20
        static let defaultPadCapacity = 10
        static let phoneCapacityKey = "maxCapacityPhone"
        static let padCapacityKey = "maxCapacityPad"
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    func maximumCapacity(isPad: Bool) -> Int {
        let key = isPad ? Constants.padCapacityKey : Constants.phoneCapacityKey
        let defaultValue = isPad ? Constants.defaultPadCapacity : Constants.defaultPhoneCapacity
        guard let value = positiveNumber(forKey: key, subfeature: .tabLRUEviction),
              value.rounded(.towardZero) == value,
              value < Double(Int.max) else {
            return defaultValue
        }
        return Int(value)
    }

    private func positiveNumber(forKey key: String, subfeature: iOSBrowserConfigSubfeature) -> Double? {
        guard let json = privacyConfigurationManager.privacyConfig.settings(for: subfeature),
              let data = json.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dictionary[key],
              !(value is Bool),
              let number = value as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue > 0 else {
            return nil
        }
        return number.doubleValue
    }
}
