//
//  ChromeWebStoreUpdateStateStoreTests.swift
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
@_spi(Testing) import Persistence
import XCTest
@testable import WebExtensions

@MainActor
final class ChromeWebStoreUpdateStateStoreTests: XCTestCase {
    func testTimingStateSurvivesStoreRecreation() {
        let storage = InMemoryThrowingKeyValueStore()
        let state = ChromeWebStoreUpdateState(lastCompletedBatch: Date(timeIntervalSince1970: 1000),
                                             retryNotBefore: Date(timeIntervalSince1970: 2000))
        ChromeWebStoreUpdateStateStore(keyValueStore: storage).save(state)
        XCTAssertEqual(ChromeWebStoreUpdateStateStore(keyValueStore: storage).load(), state)
        XCTAssertEqual(storage.underlyingDict.count, 1)
    }

    func testAbsentAndCorruptStateFailOpen() {
        let storage = InMemoryThrowingKeyValueStore()
        let store = ChromeWebStoreUpdateStateStore(keyValueStore: storage)
        XCTAssertEqual(store.load(), .init())
        store.save(.init(lastCompletedBatch: Date(), retryNotBefore: nil))
        for key in storage.underlyingDict.keys {
            storage.underlyingDict[key] = Data("invalid JSON".utf8)
        }
        XCTAssertEqual(store.load(), .init())
    }

    func testReadAndWriteFailuresDoNotCrashOrOverwriteState() {
        let storage = InMemoryThrowingKeyValueStore()
        let store = ChromeWebStoreUpdateStateStore(keyValueStore: storage)
        let previous = ChromeWebStoreUpdateState(lastCompletedBatch: Date(timeIntervalSince1970: 1000), retryNotBefore: nil)
        store.save(previous)
        storage.shouldThrowOnGet = true
        XCTAssertEqual(store.load(), .init())
        storage.shouldThrowOnGet = false
        storage.shouldThrowOnSet = true
        store.save(.init(lastCompletedBatch: Date(timeIntervalSince1970: 2000), retryNotBefore: nil))
        XCTAssertEqual(store.load(), previous)
    }
}
