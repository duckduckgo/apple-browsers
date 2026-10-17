//
//  LastActiveTabStoreTests.swift
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
import Testing
import Persistence
@testable import DuckDuckGo

@MainActor
final class LastActiveTabStoreTests {

    private func makeStore() -> (LastActiveTabStore, UserDefaults) {
        let suiteName = "LastActiveTabStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = LastActiveTabStore(store: defaults)
        return (store, defaults)
    }

    @available(iOS 16, *)
    @Test("Returns nil when nothing has been recorded", .timeLimit(.minutes(1)))
    func returnsNilWhenEmpty() {
        let (store, _) = makeStore()
        #expect(store.lastActiveNonEmptyTabUID == nil)
    }

    @available(iOS 16, *)
    @Test("Round-trips a recorded UID", .timeLimit(.minutes(1)))
    func roundTripsRecordedUID() {
        let (store, _) = makeStore()
        store.recordActiveTab(uid: "tab-uid-1")
        #expect(store.lastActiveNonEmptyTabUID == "tab-uid-1")
    }

    @available(iOS 16, *)
    @Test("Latest write wins", .timeLimit(.minutes(1)))
    func latestWriteWins() {
        let (store, _) = makeStore()
        store.recordActiveTab(uid: "tab-uid-1")
        store.recordActiveTab(uid: "tab-uid-2")
        store.recordActiveTab(uid: "tab-uid-3")
        #expect(store.lastActiveNonEmptyTabUID == "tab-uid-3")
    }

    @available(iOS 16, *)
    @Test("State persists across new store instances on the same backing storage", .timeLimit(.minutes(1)))
    func persistsAcrossStoreInstances() {
        let (firstStore, defaults) = makeStore()
        firstStore.recordActiveTab(uid: "persisted-uid")

        let secondStore = LastActiveTabStore(store: defaults)
        #expect(secondStore.lastActiveNonEmptyTabUID == "persisted-uid")
    }
}
