//
//  NewTabPageOmnibarModeProvider.swift
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

import NewTabPage
import Persistence
import AppKit

final class NewTabPageOmnibarModeProvider: NewTabPageOmnibarModeProviding {

    private enum Key: String {
        case newTabPageOmnibarMode
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = NSApp.delegateTyped.keyValueStore) {
        self.keyValueStore = keyValueStore
    }

    var mode: NewTabPageDataModel.OmnibarMode {
        get {
            guard let rawValue = try? keyValueStore.object(forKey: Key.newTabPageOmnibarMode.rawValue) as? String,
                  let mode = NewTabPageDataModel.OmnibarMode(rawValue: rawValue) else {
                return .search
            }
            return mode
        }
        set {
            try? keyValueStore.set(newValue.rawValue, forKey: Key.newTabPageOmnibarMode.rawValue)
        }
    }

}
