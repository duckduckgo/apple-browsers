//
//  LocalModelEngineOverridePersistorTests.swift
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

import AIChat
import Combine
import Foundation
@_spi(Testing) import Persistence
import Testing

@Suite("Local model engine override")
struct LocalModelEngineOverridePersistorTests {

    @available(iOS 16, macOS 13, *)
    @Test("The debug override keeps its choice and forgets Automatic", .timeLimit(.minutes(1)))
    func overrideIsStored() {
        let store = InMemoryKeyValueStore()
        let notificationCenter = NotificationCenter()
        let persistor = LocalModelEngineOverridePersistor(keyValueStore: store, notificationCenter: notificationCenter)
        var updates = 0
        let cancellable = persistor.updates.sink { updates += 1 }

        persistor.current = .llama
        #expect(persistor.current == .llama)
        #expect(persistor.current.engineKind == .llama)

        persistor.current = .automatic
        #expect(store.object(forKey: LocalModelEngineOverridePersistor.key) == nil)
        #expect(persistor.current.engineKind == nil)
        #expect(updates == 2)
        cancellable.cancel()
    }
}
