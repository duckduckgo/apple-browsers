//
//  AfterInactivityEffectiveOptionResolver.swift
//  DuckDuckGo
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
import Persistence

/// Single source of truth for "effective" after-inactivity option: stored value if present,
/// otherwise new user → New Tab, returning user → Last Used Tab (from `idleReturnNewUser` in storage).
/// One API: returns the option and saves the new-user default (NTP + clear flag) when needed.
/// Used by Settings (when reading the picker) and IdleReturnEligibilityManager.
protocol AfterInactivityEffectiveOptionResolving {
    func resolveEffectiveOption() -> AfterInactivityOption
}

final class AfterInactivityEffectiveOptionResolver: AfterInactivityEffectiveOptionResolving {

    private let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>

    init(storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>) {
        self.storage = storage
    }

    /// Returns the effective option and, when it is .newTab for a new user with no stored value,
    /// persists that choice and clears `idleReturnNewUser`. Caller can call e.g. objectWillChange.send() after reading if needed.
    func resolveEffectiveOption() -> AfterInactivityOption {
        if let raw = try? storage.value(for: \AfterInactivitySettingKeys.afterInactivityOption),
           let option = AfterInactivityOption(rawValue: raw) {
            return option
        } else if (try? storage.value(for: \AfterInactivitySettingKeys.idleReturnNewUser)) == true {
            try? storage.set(AfterInactivityOption.newTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)
            try? storage.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)
            return .newTab
        } else {
            return .lastUsedTab
        }
    }
}
