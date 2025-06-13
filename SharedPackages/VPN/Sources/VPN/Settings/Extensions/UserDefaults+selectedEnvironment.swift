//
//  UserDefaults+selectedEnvironment.swift
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

import Combine
import Foundation

extension UserDefaults {
    private var selectedEnvironmentKey: String {
        "networkProtectionSettingSelectedEnvironmentRawValue"
    }

    @objc
    dynamic var networkProtectionSettingSelectedEnvironmentRawValue: String {
        get {
            value(forKey: selectedEnvironmentKey) as? String ?? VPNSettings.SelectedEnvironment.default.rawValue
        }

        set {
            set(newValue, forKey: selectedEnvironmentKey)
        }
    }

    var networkProtectionSettingSelectedEnvironment: VPNSettings.SelectedEnvironment {
        get {
            VPNSettings.SelectedEnvironment(rawValue: networkProtectionSettingSelectedEnvironmentRawValue) ?? .default
        }

        set {
             networkProtectionSettingSelectedEnvironmentRawValue = newValue.rawValue
        }
    }

    var networkProtectionSettingSelectedEnvironmentPublisher: AnyPublisher<VPNSettings.SelectedEnvironment, Never> {
        publisher(for: \.networkProtectionSettingSelectedEnvironmentRawValue).map { value in
            VPNSettings.SelectedEnvironment(rawValue: value) ?? .default
        }.eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingSelectedEnvironment() {
        networkProtectionSettingSelectedEnvironment = .default
    }
}
