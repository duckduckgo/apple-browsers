//
//  BrokenSitePromptLimiterStore.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import BrokenSitePrompt
import Foundation
import Persistence

struct BrokenSitePromptSettings: StoringKeys {
    /// `migrateLegacyKey` carries the shipped values across the rename. The legacy keys contain dots,
    /// which `StorageKey` rejects because they break UserDefaults KVO observation.
    let lastToastShownDate = StorageKey<Date>(UserDefaultsKeys.brokenSitePromptLastToastShownDate,
                                              migrateLegacyKey: "brokenSitePrompt.last-broken-site-toast-shown-date")
    let toastDismissStreakCounter = StorageKey<Int>(UserDefaultsKeys.brokenSitePromptToastDismissStreakCounter,
                                                    migrateLegacyKey: "brokenSitePrompt.toast-dismiss-streak-counter")
}

final class BrokenSitePromptLimiterStore: BrokenSitePromptLimiterStoring {

    private let storage: KeyedStorage<BrokenSitePromptSettings>

    init(storage: KeyedStorage<BrokenSitePromptSettings>? = nil) {
        self.storage = storage ?? KeyedStorage(storage: UserDefaults.standard)
    }

    var lastToastShownDate: Date {
        get { storage.lastToastShownDate ?? .distantPast }
        set { storage.lastToastShownDate = newValue }
    }

    var toastDismissStreakCounter: Int {
        get { storage.toastDismissStreakCounter ?? 0 }
        set { storage.toastDismissStreakCounter = newValue }
    }
}
