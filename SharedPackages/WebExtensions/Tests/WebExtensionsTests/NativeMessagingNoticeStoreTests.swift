//
//  NativeMessagingNoticeStoreTests.swift
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
@testable import WebExtensions

@MainActor
final class NativeMessagingNoticeStoreTests: XCTestCase {
    private let keyValueStore = InMemoryThrowingKeyValueStore()

    func testWhenAnExtensionFirstTriesNativeMessagingThenItNeedsTheNotice() {
        let store = NativeMessagingNoticeStore(keyValueStore: keyValueStore)

        let isFirstAttempt = store.recordAttempt(for: "bitwarden")

        XCTAssertTrue(isFirstAttempt)
        XCTAssertTrue(store.needsNotice(for: "bitwarden"))
        XCTAssertFalse(store.needsNotice(for: "1password"))
    }

    func testWhenTheNoticeWasShownThenItIsNotNeededAgainAfterARelaunch() {
        let store = NativeMessagingNoticeStore(keyValueStore: keyValueStore)
        store.recordAttempt(for: "bitwarden")

        store.markNoticeShown(for: "bitwarden")

        let relaunched = NativeMessagingNoticeStore(keyValueStore: keyValueStore)
        XCTAssertFalse(relaunched.needsNotice(for: "bitwarden"))
        XCTAssertFalse(relaunched.recordAttempt(for: "bitwarden"))
    }

    func testWhenShownNoticesAreResetThenEveryExtensionThatTriedNeedsTheNoticeAgain() {
        let store = NativeMessagingNoticeStore(keyValueStore: keyValueStore)
        store.recordAttempt(for: "bitwarden")
        store.markNoticeShown(for: "bitwarden")
        store.recordAttempt(for: "1password")

        store.resetShownNotices()

        XCTAssertTrue(store.needsNotice(for: "bitwarden"))
        XCTAssertTrue(store.needsNotice(for: "1password"))
        XCTAssertFalse(store.needsNotice(for: "icloud"))
    }
}
