//
//  NewTabPageBackgroundStore.swift
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

struct NewTabPageBackgroundSettings: Equatable {
    var isProcedural: Bool
    var seed: UInt64
}

private enum NewTabPageBackgroundStorageKey: String, StorageKeyDescribing {
    case isProcedural = "com_duckduckgo_ios_newTabPage_background_isProcedural"
    case seed = "com_duckduckgo_ios_newTabPage_background_seed"
}

private struct NewTabPageBackgroundKeys: StoringKeys {
    let isProcedural = StorageKey<Bool>(NewTabPageBackgroundStorageKey.isProcedural)
    let seed = StorageKey<String>(NewTabPageBackgroundStorageKey.seed)
}

struct NewTabPageBackgroundStore {
    private static let didChange = Notification.Name("NewTabPageBackgroundStore.didChange")
    private let keyValueStore: KeyValueStoring
    private let makeSeed: () -> UInt64

    init(keyValueStore: KeyValueStoring = UserDefaults.app,
         makeSeed: @escaping () -> UInt64 = { UInt64.random(in: .min ... .max) }) {
        self.keyValueStore = keyValueStore
        self.makeSeed = makeSeed
    }

    private var storage: any KeyedStoring<NewTabPageBackgroundKeys> {
        keyValueStore.keyedStoring()
    }

    var settings: NewTabPageBackgroundSettings {
        get {
            let seed: UInt64
            if let savedSeed = storage.seed.flatMap(UInt64.init) {
                seed = savedSeed
            } else {
                seed = makeSeed()
                storage.seed = String(seed)
            }
            return NewTabPageBackgroundSettings(isProcedural: storage.isProcedural ?? true, seed: seed)
        }
        nonmutating set {
            guard settings != newValue else { return }
            storage.seed = String(newValue.seed)
            storage.isProcedural = newValue.isProcedural
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    var publisher: AnyPublisher<NewTabPageBackgroundSettings, Never> {
        Deferred {
            NotificationCenter.default.publisher(for: Self.didChange)
                .map { _ in self.settings }
                .prepend(self.settings)
                .removeDuplicates()
        }
        .eraseToAnyPublisher()
    }
}
