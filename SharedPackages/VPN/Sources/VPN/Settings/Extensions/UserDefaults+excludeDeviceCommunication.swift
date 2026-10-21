//
//  UserDefaults+excludeDeviceCommunication.swift
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
    private var excludeDeviceCommunicationKey: String {
        "networkProtectionSettingExcludeDeviceCommunication"
    }

    #if os(macOS)
    static let excludeDeviceCommunicationDefaultValue = false
    #else
    static let excludeDeviceCommunicationDefaultValue = true
    #endif

    @objc
    dynamic var networkProtectionSettingExcludeDeviceCommunication: Bool {
        get {
            value(forKey: excludeDeviceCommunicationKey) as? Bool ?? Self.excludeDeviceCommunicationDefaultValue
        }

        set {
            set(newValue, forKey: excludeDeviceCommunicationKey)
        }
    }

    var networkProtectionSettingExcludeDeviceCommunicationPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.networkProtectionSettingExcludeDeviceCommunication).eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingExcludeDeviceCommunication() {
        removeObject(forKey: excludeDeviceCommunicationKey)
    }
}
