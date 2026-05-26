//
//  OSUpgradeCapabilityOverride.swift
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

import Foundation
import Persistence

enum OSUpgradeCapabilityOverride: String, CaseIterable {
    case `default`
    case forceCapable
    case forceIncapable

    var title: String {
        switch self {
        case .default: return "Default (use hardware check)"
        case .forceCapable: return "Force capable (canUpgradeOS = true)"
        case .forceIncapable: return "Force incapable (canUpgradeOS = false)"
        }
    }
}

/// Debug-menu only. The stored value is honored only under `#if DEBUG`; production
/// code should rely on `SupportedOSChecker` directly.
struct OSUpgradeCapabilityOverridePersistor {

    enum Key: String {
        case override = "rmf.os-upgrade-capability.override"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var current: OSUpgradeCapabilityOverride {
        get {
            guard let raw = keyValueStore.object(forKey: Key.override.rawValue) as? String,
                  let value = OSUpgradeCapabilityOverride(rawValue: raw) else {
                return .default
            }
            return value
        }
        nonmutating set {
            if newValue == .default {
                keyValueStore.removeObject(forKey: Key.override.rawValue)
            } else {
                keyValueStore.set(newValue.rawValue, forKey: Key.override.rawValue)
            }
        }
    }

    /// Resolves `canUpgradeOS` against the stored override. In release builds the
    /// override is ignored and `defaultValue` is returned unchanged — the debug
    /// menu is the only writer, but this guarantees release behavior even if the
    /// key somehow ends up set.
    func canUpgradeOS(default defaultValue: Bool) -> Bool {
        #if DEBUG
        switch current {
        case .default: return defaultValue
        case .forceCapable: return true
        case .forceIncapable: return false
        }
        #else
        return defaultValue
        #endif
    }
}
