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
import UIKit

protocol AfterInactivityEffectiveOptionResolving {
    /// Returns the user selected or default option for page to open after idle time.
    func resolveEffectiveOption() -> AfterInactivityOption
}

final class AfterInactivityEffectiveOptionResolver: AfterInactivityEffectiveOptionResolving {

    private let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>
    private let isPad: Bool

    init(storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>,
         isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad) {
        self.storage = storage
        self.isPad = isPad
    }

    /// Returns the user's explicit preference when stored, otherwise defaults to
    /// `.newTab` on iPhone (both new and existing users) or `.lastUsedTab` on iPad.
    /// Users who manually selected "Last Used Tab" in Settings keep that choice.
    func resolveEffectiveOption() -> AfterInactivityOption {
        if let raw = try? storage.afterInactivityOption,
           let option = AfterInactivityOption(rawValue: raw) {
            return option
        } else if isPad {
            return .lastUsedTab
        } else {
            try? storage.set(AfterInactivityOption.newTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)
            try? storage.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)
            return .newTab
        }
    }
}
