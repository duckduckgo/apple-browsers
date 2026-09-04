//
//  UserDefaults+endpointPortOverride.swift
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

import Combine
import Foundation

extension UserDefaults {
    private var endpointPortOverrideKey: String {
        "networkProtectionSettingEndpointPortOverrideRawValue"
    }

    @objc
    dynamic var networkProtectionSettingEndpointPortOverrideRawValue: NSNumber? {
        get {
            value(forKey: endpointPortOverrideKey) as? NSNumber
        }

        set {
            set(newValue, forKey: endpointPortOverrideKey)
        }
    }

    private func endpointPortOverrideFromRawValue(_ rawValue: NSNumber?) -> UInt16? {
        guard let intValue = rawValue?.intValue, (1...65535).contains(intValue) else {
            return nil
        }

        return UInt16(intValue)
    }

    var networkProtectionSettingEndpointPortOverride: UInt16? {
        get {
            endpointPortOverrideFromRawValue(networkProtectionSettingEndpointPortOverrideRawValue)
        }

        set {
            if let newValue {
                networkProtectionSettingEndpointPortOverrideRawValue = NSNumber(value: newValue)
            } else {
                networkProtectionSettingEndpointPortOverrideRawValue = nil
            }
        }
    }

    var networkProtectionSettingEndpointPortOverridePublisher: AnyPublisher<UInt16?, Never> {
        let endpointPortOverrideFromRawValue = self.endpointPortOverrideFromRawValue

        return publisher(for: \.networkProtectionSettingEndpointPortOverrideRawValue).map { rawValue in
            endpointPortOverrideFromRawValue(rawValue)
        }.eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingEndpointPortOverride() {
        networkProtectionSettingEndpointPortOverrideRawValue = nil
    }
}
