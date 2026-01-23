//
//  UserDefaultsKeys.swift
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

/// Central repository for UserDefaults key string constants used throughout the macOS app.
///
/// Define raw key strings here, then reference them in StoringKeys structs in feature files.
/// For legacy UserDefaultsWrapper keys use `StorageKey(.legacyKeyName)` (deprecated).
///
/// Usage:
///     // Define new key String as in a suitable domain, e.g. `UserDefaultsKeys`:
///     enum UserDefaultsKeys: String {
///         // … existing values …
///
///         // My new key for… something
///         // https://asana.com/0/xyz/abc
///         case myNewKey = "my.new.key"
///     }
///
///     // Define the feature-related setting keys bound to value types in a StoringKeys-conforming struct:
///     struct MySettings: StoringKeys {
///         var myNewSetting = StorageKey<String>(.myNewKey)
///         
///         // Bridge from legacy UserDefaults.Key:
///         var legacySetting = StorageKey<Bool>(.gpcEnabled)
///     }
///
///     // Dependency injection pattern:
///     class MyService {
///         private let storage: any KeyedStoring<MySettings>
///         
///         init(storage: (any KeyedStoring<MySettings>)? = nil) {
///             self.storage = if let storage { storage } else { UserDefaults.standard.keyedStoring() }
///         }
///         
///         func updateSettings() {
///             storage.myNewSetting = "value"
///             let current = storage.legacySetting ?? false
///         }
///     }
/// 
///     // Testing:
///     let myService = MyService(storage: InMemoryKeyValueStoring().keyedStoring())
///     
enum UserDefaultsKeys: String, StorageKeyDescribing {

    // MARK: - AIChatDebugURLSettings
    case aiChatDebugURLSettings = "customURL"

    // MARK: - Fire Dialog Settings

    case fireDialogSelectedClearingOption = "fire-dialog_selectedClearingOption"
    case fireDialogIncludeTabsAndWindows = "fire-dialog_includeTabsAndWindowsState"
    case fireDialogIncludeHistory = "fire-dialog_includeHistoryState"
    case fireDialogIncludeCookiesAndSiteData = "fire-dialog_includeCookiesAndSiteDataState"
    case fireDialogIncludeChatHistory = "fire-dialog_includeChatHistoryState"

    // MARK: - Sync Diagnosis Settings

    case syncManuallyDisabled = "com.duckduckgo.app.key.debug.SyncManuallyDisabled"
    case syncWasDisabledUnexpectedlyPixelFired = "com.duckduckgo.app.key.debug.SyncWasDisabledUnexpectedlyPixelFired"

    // MARK: - BaseURLDebugSettings

    case debugCustomBaseURL = "debug_customBaseURL"
    case debugCustomDuckAIBaseURL = "debug_customDuckAIBaseURL"

    // MARK: - Add more app-wide keys here as they are migrated from UserDefaultsWrapper

}

// MARK: - StorageKey Extensions

extension StorageKey {

    /// Initialize StorageKey from UserDefaultsKeys enum
    ///
    /// Preferred pattern for new keys:
    ///
    ///     struct MySettings: StoringKeys {
    ///         var fireDialog = StorageKey<Bool>(.fireDialogIncludeHistory)
    ///     }
    ///
    init(
        _ key: UserDefaultsKeys,
        migrateLegacyKey: String? = nil,
        assertionHandler: (_ message: String) -> Void = { message in
            assertionFailure(message)
        }
    ) {
        self.init(key as (any StorageKeyDescribing), migrateLegacyKey: migrateLegacyKey, assertionHandler: assertionHandler)
    }

    /// Initialize StorageKey from legacy UserDefaults.Key enum
    ///
    /// Allows gradual migration from UserDefaultsWrapper:
    ///
    ///     struct MySettings: StoringKeys {
    ///         var gpc = StorageKey<Bool>(.gpcEnabled)
    ///         var theme = StorageKey<String>(.themeName)
    ///     }
    ///
    @available(*, deprecated, message: "Define key constants in UserDefaultsKeys instead")
    init(_ key: UserDefaults.Key) {
        self.init(key as any StorageKeyDescribing, assertionHandler: { _ in })
    }
}
