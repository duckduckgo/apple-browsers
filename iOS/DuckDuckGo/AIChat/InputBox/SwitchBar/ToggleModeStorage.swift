//
//  ToggleModeStorage.swift
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

/// Persists the last-used omnibar toggle mode (Search / Duck.ai) so it can be
/// restored on the next session when the user's default-mode preference is "Last Used".
protocol ToggleModeStoring {
    func save(_ mode: TextEntryMode)
    func restore() -> TextEntryMode?
}

final class ToggleModeStorage: ToggleModeStoring {

    private let store: KeyValueStoring
    private let key = "SwitchBarHandler.toggleState"

    init(store: KeyValueStoring = UserDefaults.standard) {
        self.store = store
    }

    func save(_ mode: TextEntryMode) {
        store.set(mode.rawValue, forKey: key)
    }

    func restore() -> TextEntryMode? {
        guard let rawValue = store.object(forKey: key) as? String else { return nil }
        return TextEntryMode(rawValue: rawValue)
    }
}
