//
//  UserDefaults+orphanProxyDetection.swift
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
    private var orphanProxyDetectionEnabledKey: String {
        "networkProtectionSettingOrphanProxyDetectionEnabled"
    }

    /// The behavior before the orphan-proxy kill switch existed: detection ran unconditionally.
    public static let orphanProxyDetectionEnabledDefaultValue = true

    @objc
    dynamic var networkProtectionSettingOrphanProxyDetectionEnabled: Bool {
        get {
            value(forKey: orphanProxyDetectionEnabledKey) as? Bool ?? Self.orphanProxyDetectionEnabledDefaultValue
        }

        set {
            set(newValue, forKey: orphanProxyDetectionEnabledKey)
        }
    }

    var networkProtectionSettingOrphanProxyDetectionEnabledPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.networkProtectionSettingOrphanProxyDetectionEnabled).eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingOrphanProxyDetectionEnabled() {
        removeObject(forKey: orphanProxyDetectionEnabledKey)
    }
}
