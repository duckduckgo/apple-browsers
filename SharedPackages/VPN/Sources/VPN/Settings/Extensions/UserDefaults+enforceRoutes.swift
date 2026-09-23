//
//  UserDefaults+enforceRoutes.swift
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
    private var enforceRoutesKey: String {
        "vpnSettingEnforceRoutes"
    }

    public static let enforceRoutesDefaultValue = true

    @objc
    dynamic var vpnSettingEnforceRoutes: Bool {
        get {
            value(forKey: enforceRoutesKey) as? Bool ?? Self.enforceRoutesDefaultValue
        }

        set {
            set(newValue, forKey: enforceRoutesKey)
        }
    }

    var vpnSettingEnforceRoutesPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.vpnSettingEnforceRoutes).eraseToAnyPublisher()
    }

    func resetVPNSettingEnforceRoutes() {
        removeObject(forKey: enforceRoutesKey)
    }
}
