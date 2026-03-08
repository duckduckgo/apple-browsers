//
//  AfterInactivitySettingStorage.swift
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

/// Key namespace for after-inactivity user preference (New Tab vs Last Used Tab).
enum AfterInactivityStorageKeys: String, StorageKeyDescribing {
    case afterInactivityOption = "idle-return-after-inactivity-option"
    case idleReturnNewUser = "idle-return-new-user"
}

/// StoringKeys for after-inactivity setting.
struct AfterInactivitySettingKeys: StoringKeys {
    let afterInactivityOption = StorageKey<String>(AfterInactivityStorageKeys.afterInactivityOption)
    let idleReturnNewUser = StorageKey<Bool>(AfterInactivityStorageKeys.idleReturnNewUser)
}
