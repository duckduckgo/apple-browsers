//
//  AIChatMCPSessionTests.swift
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

import XCTest
@testable import AIChat

@MainActor
final class AIChatMCPSessionTests: XCTestCase {

    private let ownerTabID = "owner-tab"

    /// `initialize` alone is not enough — tools traffic waits for `notifications/initialized`.
    func testWhenInitializeIsAppliedThenTheSessionIsNotYetReady() {
        let store = AIChatMCPSessionStore()

        store.applyInitialize(forOwnerTabID: ownerTabID, protocolVersion: "2025-11-25", supportsElicitationForm: true)

        let session = store.session(forOwnerTabID: ownerTabID)
        XCTAssertEqual(session?.isInitialized, false)
        XCTAssertEqual(session?.protocolVersion, "2025-11-25")
        XCTAssertEqual(session?.supportsElicitationForm, true)
    }

    func testWhenInitializedNotificationArrivesThenTheSessionIsReady() {
        let store = AIChatMCPSessionStore()

        store.applyInitialize(forOwnerTabID: ownerTabID, protocolVersion: "2025-11-25", supportsElicitationForm: true)
        store.markInitialized(forOwnerTabID: ownerTabID)

        XCTAssertEqual(store.session(forOwnerTabID: ownerTabID)?.isInitialized, true)
    }

    /// A front end whose `initialize` timed out can still confirm readiness — refusing would
    /// strand it with no way to list tools.
    func testWhenOnlyTheInitializedNotificationArrivesThenTheSessionIsReadyWithoutElicitation() {
        let store = AIChatMCPSessionStore()

        store.markInitialized(forOwnerTabID: ownerTabID)

        let session = store.session(forOwnerTabID: ownerTabID)
        XCTAssertEqual(session?.isInitialized, true)
        XCTAssertEqual(session?.supportsElicitationForm, false)
    }

    /// Re-handshaking must not leave the previous readiness in place.
    func testWhenInitializeIsRepeatedThenReadinessIsCleared() {
        let store = AIChatMCPSessionStore()

        store.applyInitialize(forOwnerTabID: ownerTabID, protocolVersion: "2025-11-25", supportsElicitationForm: true)
        store.markInitialized(forOwnerTabID: ownerTabID)
        store.applyInitialize(forOwnerTabID: ownerTabID, protocolVersion: "2025-11-25", supportsElicitationForm: false)

        let session = store.session(forOwnerTabID: ownerTabID)
        XCTAssertEqual(session?.isInitialized, false)
        XCTAssertEqual(session?.supportsElicitationForm, false)
    }

    func testWhenSessionsAreKeyedByOwnerTabThenTheyDoNotLeakAcrossTabs() {
        let store = AIChatMCPSessionStore()

        store.markInitialized(forOwnerTabID: "tab-a")

        XCTAssertEqual(store.session(forOwnerTabID: "tab-a")?.isInitialized, true)
        XCTAssertNil(store.session(forOwnerTabID: "tab-b"))
    }

    func testWhenSessionIsRemovedThenItIsGone() {
        let store = AIChatMCPSessionStore()
        store.markInitialized(forOwnerTabID: ownerTabID)

        store.removeSession(forOwnerTabID: ownerTabID)

        XCTAssertNil(store.session(forOwnerTabID: ownerTabID))
    }

    func testWhenAllSessionsAreRemovedThenNoneRemain() {
        let store = AIChatMCPSessionStore()
        store.markInitialized(forOwnerTabID: "tab-a")
        store.markInitialized(forOwnerTabID: "tab-b")

        store.removeAllSessions()

        XCTAssertNil(store.session(forOwnerTabID: "tab-a"))
        XCTAssertNil(store.session(forOwnerTabID: "tab-b"))
    }
}
