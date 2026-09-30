//
//  NewTabPageCustomizationStore.swift
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

import Core
import Foundation
import Persistence

protocol NewTabPageCustomizationPersisting {

    var isFavoritesSectionVisible: Bool { get set }
    var isMessagesSectionVisible: Bool { get set }
}

private enum NewTabPageCustomizationStorageKeys: String, StorageKeyDescribing {
    case isFavoritesSectionVisible = "com_duckduckgo_ios_newTabPage_favorites_isVisible"
    case isMessagesSectionVisible = "com_duckduckgo_ios_newTabPage_messages_isVisible"
}

private struct NewTabPageCustomizationKeys: StoringKeys {
    let isFavoritesSectionVisible = StorageKey<Bool>(NewTabPageCustomizationStorageKeys.isFavoritesSectionVisible)
    let isMessagesSectionVisible = StorageKey<Bool>(NewTabPageCustomizationStorageKeys.isMessagesSectionVisible)
}

struct NewTabPageCustomizationStore: NewTabPageCustomizationPersisting {

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.app) {
        self.keyValueStore = keyValueStore
    }

    private var storage: any KeyedStoring<NewTabPageCustomizationKeys> {
        keyValueStore.keyedStoring()
    }

    var isFavoritesSectionVisible: Bool {
        get { storage.isFavoritesSectionVisible ?? true }
        set { storage.isFavoritesSectionVisible = newValue }
    }

    var isMessagesSectionVisible: Bool {
        get { storage.isMessagesSectionVisible ?? true }
        set { storage.isMessagesSectionVisible = newValue }
    }
}
