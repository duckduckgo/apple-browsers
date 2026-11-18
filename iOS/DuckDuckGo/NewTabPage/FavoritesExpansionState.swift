//
//  FavoritesExpansionState.swift
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

import Combine
import Core
import Foundation
import Persistence

/// Persists whether the user last chose to see all favorites.
protocol FavoritesExpansionStoring: AnyObject {
    var isExpanded: Bool { get set }
}

final class FavoritesExpansionStore: FavoritesExpansionStoring {
    private let keyValueStore: KeyValueStoring
    private let storageKey = "com_duckduckgo_ios_newTabPage_favorites_isExpanded"

    init(keyValueStore: KeyValueStoring = UserDefaults.app) {
        self.keyValueStore = keyValueStore
    }

    var isExpanded: Bool {
        get { keyValueStore.object(forKey: storageKey) as? Bool ?? false }
        set { keyValueStore.set(newValue, forKey: storageKey) }
    }
}

/// Expansion state shared by a tab's resting and focused favorites views.
final class FavoritesExpansionState: ObservableObject {
    @Published var isExpanded: Bool {
        didSet {
            guard isExpanded != oldValue else { return }
            store?.isExpanded = isExpanded
        }
    }

    private let store: FavoritesExpansionStoring?

    init(store: FavoritesExpansionStoring? = nil) {
        self.store = store
        isExpanded = store?.isExpanded ?? false
    }
}
