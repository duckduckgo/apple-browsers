//
//  UserDefaults+showInMenuBar.swift
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
    private var showInMenuBarKey: String {
        "networkProtectionSettingShowInMenuBar"
    }

    static let showInMenuBarDefaultValue = true

    @objc
    dynamic var networkProtectionSettingShowInMenuBar: Bool {
        get {
            value(forKey: showInMenuBarKey) as? Bool ?? Self.showInMenuBarDefaultValue
        }

        set {
            guard newValue != networkProtectionSettingShowInMenuBar else {
                return
            }

            set(newValue, forKey: showInMenuBarKey)
        }
    }

    var networkProtectionSettingShowInMenuBarPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.networkProtectionSettingShowInMenuBar).eraseToAnyPublisher()
    }

    func resetNetworkProtectionSettingShowInMenuBar() {
        removeObject(forKey: showInMenuBarKey)
    }
}
