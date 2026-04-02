//
//  AutoplaySettings.swift
//  DuckDuckGo
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

enum AutoplayStorageKeys: String, StorageKeyDescribing {
    case autoplayBlockingMode = "com-duckduckgo-ios-autoplayBlockingMode"
}

struct AutoplaySettingKeys: StoringKeys {
    let autoplayBlockingMode = StorageKey<AutoplayBlockingMode>(
        AutoplayStorageKeys.autoplayBlockingMode
    )
}

protocol AutoplaySettings {
    var currentAutoplayBlockingMode: AutoplayBlockingMode { get nonmutating set }
}

struct DefaultAutoplaySettings: AutoplaySettings {

    private let storage: any KeyedStoring<AutoplaySettingKeys>

    init(storage: (any KeyedStoring<AutoplaySettingKeys>)? = nil) {
        self.storage = if let storage { storage } else { UserDefaults.app.keyedStoring() }
    }

    var currentAutoplayBlockingMode: AutoplayBlockingMode {
        get { storage.autoplayBlockingMode ?? .blockAudio }
        nonmutating set { storage.autoplayBlockingMode = newValue }
    }
}
