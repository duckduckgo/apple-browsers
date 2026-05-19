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
import Core
import Persistence
import PrivacyConfig
import UIKit

protocol AfterInactivityEffectiveOptionResolving {
    /// Returns the user selected or default option for page to open after idle time.
    func resolveEffectiveOption() -> AfterInactivityOption
}

final class AfterInactivityEffectiveOptionResolver: AfterInactivityEffectiveOptionResolving {

    private let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>
    private let featureFlagger: FeatureFlagger
    private let isPad: Bool

    init(storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>,
         featureFlagger: FeatureFlagger,
         isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad) {
        self.storage = storage
        self.featureFlagger = featureFlagger
        self.isPad = isPad
    }

    /// Returns the user's explicit preference when stored.
    ///
    /// On iPhone with no stored preference:
    /// - **New users** (`idleReturnNewUser == true`): New Tab, persisted so it sticks.
    /// - **`defaultExistingIPhoneUsersToNewTabAfterIdle` on**: New Tab for existing users, **not** persisted (volatile — reverts to LUT if flag is turned off).
    /// - **Flag off + existing user**: Last Used Tab, **not** persisted.
    ///
    /// iPad and all other cases default to Last Used Tab without persisting.
    /// Users who manually selected an option in Settings always keep that choice.
    func resolveEffectiveOption() -> AfterInactivityOption {
        if let raw = try? storage.afterInactivityOption,
           let option = AfterInactivityOption(rawValue: raw) {
            return option
        } else if !isPad, (try? storage.idleReturnNewUser) == true {
            persistImplicitNewTabDefaultForIPhone()
            return .newTab
        } else if !isPad, featureFlagger.isFeatureOn(.defaultExistingIPhoneUsersToNewTabAfterIdle) {
            return .newTab
        } else {
            return .lastUsedTab
        }
    }

    private func persistImplicitNewTabDefaultForIPhone() {
        try? storage.set(AfterInactivityOption.newTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)
        try? storage.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)
    }
}
