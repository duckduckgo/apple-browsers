//
//  ChromeWebStoreUpdateStateStore.swift
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
import os.log

/// The discovery timing that survives browser relaunches. The coordinator owns the live copy.
struct ChromeWebStoreUpdateState: Codable, Equatable, Sendable {
    var lastCompletedBatch: Date?
    var retryNotBefore: Date?
}

/// Keeps persistence on the same actor as the package's other key-value storage users.
@MainActor
final class ChromeWebStoreUpdateStateStore {
    private static let key = "web-extension-update-discovery"
    private let keyValueStore: any ThrowingKeyValueStoring

    init(keyValueStore: any ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func load() -> ChromeWebStoreUpdateState {
        do {
            guard let data = try keyValueStore.object(forKey: Self.key) as? Data else { return .init() }
            return try JSONDecoder().decode(ChromeWebStoreUpdateState.self, from: data)
        } catch {
            Logger.webExtensions.error("Extension update discovery: could not restore timing state")
            return .init()
        }
    }

    func save(_ state: ChromeWebStoreUpdateState) {
        do {
            try keyValueStore.set(JSONEncoder().encode(state), forKey: Self.key)
        } catch {
            Logger.webExtensions.error("Extension update discovery: could not save timing state")
        }
    }
}
