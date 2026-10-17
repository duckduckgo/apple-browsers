//
//  UserDefaults+excludeCellularServices.swift
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
    private var excludeCellularServicesKey: String {
        "networkProtectionSettingExcludeCellularServices"
    }

    static let excludeCellularServicesDefaultValue = false

    @objc
    dynamic var networkProtectionSettingExcludeCellularServices: Bool {
        get {
            value(forKey: excludeCellularServicesKey) as? Bool ?? Self.excludeCellularServicesDefaultValue
        }

        set {
            set(newValue, forKey: excludeCellularServicesKey)
        }
    }

    var networkProtectionSettingExcludeCellularServicesPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.networkProtectionSettingExcludeCellularServices).eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingExcludeCellularServices() {
        removeObject(forKey: excludeCellularServicesKey)
    }
}
