//
//  BrowserToolPermissionStoreTests.swift
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

@_spi(Testing) import Persistence
import XCTest
@testable import AIChat

/// Stored Always/Never decisions, in the layout Windows persists.
@MainActor
final class BrowserToolPermissionStoreTests: XCTestCase {

    private static let storageKey = "ai-chat_browser-tool-permissions"

    private var backing: InMemoryKeyValueStore!
    private var store: BrowserToolPermissionStore!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = BrowserToolPermissionStore(storage: backing.keyedStoring())
    }

    override func tearDown() {
        store = nil
        backing = nil
        super.tearDown()
    }

    func testWhenNothingIsStoredThenEveryToolAsks() {
        XCTAssertEqual(store.state(forToolNamed: "alpha"), .ask)
        XCTAssertEqual(store.storedDecisions, [:])
    }

    func testWhenAllowIsStoredThenItIsReadBack() {
        store.setState(.allow, forToolNamed: "alpha")

        XCTAssertEqual(store.state(forToolNamed: "alpha"), .allow)
        XCTAssertEqual(store.storedDecisions, ["alpha": .allow])
    }

    func testWhenDenyIsStoredThenItIsReadBack() {
        store.setState(.deny, forToolNamed: "alpha")

        XCTAssertEqual(store.state(forToolNamed: "alpha"), .deny)
    }

    func testWhenAskIsStoredThenTheDecisionIsForgotten() {
        store.setState(.allow, forToolNamed: "alpha")
        store.setState(.deny, forToolNamed: "beta")

        store.setState(.ask, forToolNamed: "alpha")

        XCTAssertEqual(store.state(forToolNamed: "alpha"), .ask)
        XCTAssertEqual(store.storedDecisions, ["beta": .deny])
    }

    func testWhenTheLastDecisionIsForgottenThenTheKeyIsRemoved() {
        store.setState(.allow, forToolNamed: "alpha")

        store.setState(.ask, forToolNamed: "alpha")

        XCTAssertNil(backing.object(forKey: Self.storageKey))
    }

    func testWhenClearAllThenEveryToolAsksAgainAndTheKeyIsRemoved() {
        store.setState(.allow, forToolNamed: "alpha")
        store.setState(.deny, forToolNamed: "beta")

        store.clearAll()

        XCTAssertEqual(store.state(forToolNamed: "alpha"), .ask)
        XCTAssertEqual(store.state(forToolNamed: "beta"), .ask)
        XCTAssertNil(backing.object(forKey: Self.storageKey))
    }

    /// Same on-disk shape as Windows, under a dot-free key.
    func testWhenDecisionsAreStoredThenTheyPersistAsAToolNameToAllowOrDenyMap() {
        store.setState(.allow, forToolNamed: "alpha")
        store.setState(.deny, forToolNamed: "beta")

        XCTAssertEqual(backing.object(forKey: Self.storageKey) as? [String: String], ["alpha": "allow", "beta": "deny"])
    }

    /// A value we do not recognise can only ever cause an extra prompt, never grant access.
    func testWhenAStoredValueIsUnrecognisedThenTheToolAsks() {
        backing.set(["alpha": "yes-please", "beta": "deny"], forKey: Self.storageKey)

        XCTAssertEqual(store.state(forToolNamed: "alpha"), .ask)
        XCTAssertEqual(store.storedDecisions, ["beta": .deny])
    }

    /// Two stores over one backing see each other's writes — the app and the debug menu share one.
    func testWhenAnotherStoreWritesThenTheDecisionIsVisible() {
        let other = BrowserToolPermissionStore(storage: backing.keyedStoring())

        other.setState(.allow, forToolNamed: "alpha")

        XCTAssertEqual(store.state(forToolNamed: "alpha"), .allow)
    }
}
