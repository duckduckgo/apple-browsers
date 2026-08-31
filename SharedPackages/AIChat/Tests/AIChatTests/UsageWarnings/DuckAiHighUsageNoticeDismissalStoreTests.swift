//
//  DuckAiHighUsageNoticeDismissalStoreTests.swift
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

import Persistence
import XCTest
@testable import AIChat

final class DuckAiHighUsageNoticeDismissalStoreTests: XCTestCase {

    private var keyValueStore: InMemoryThrowingStore!
    private var sut: DuckAiHighUsageNoticeDismissalStore!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryThrowingStore()
        sut = DuckAiHighUsageNoticeDismissalStore(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }

    func testWhenNothingWasStoredThenNothingIsDismissed() {
        XCTAssertFalse(sut.isDismissed(modelId: "claude-opus-4-8"))
    }

    func testDismissalRoundTrips() {
        sut.setDismissed(modelId: "claude-opus-4-8")

        XCTAssertTrue(sut.isDismissed(modelId: "claude-opus-4-8"))
    }

    func testModelsAreDismissedIndependently() {
        sut.setDismissed(modelId: "claude-opus-4-8")

        XCTAssertFalse(sut.isDismissed(modelId: "some-future-model"))
    }

    /// The notice is one-time per model, so a second dismissal must not drop the first.
    func testDismissingASecondModelKeepsTheFirst() {
        sut.setDismissed(modelId: "claude-opus-4-8")
        sut.setDismissed(modelId: "some-future-model")

        XCTAssertTrue(sut.isDismissed(modelId: "claude-opus-4-8"))
        XCTAssertTrue(sut.isDismissed(modelId: "some-future-model"))
    }

    func testDismissingTheSameModelTwiceIsNotRecordedTwice() {
        sut.setDismissed(modelId: "claude-opus-4-8")
        sut.setDismissed(modelId: "claude-opus-4-8")

        let stored = try? keyValueStore.object(forKey: "aichat.high-usage-notice.dismissed-models") as? [String]
        XCTAssertEqual(stored, ["claude-opus-4-8"])
    }

    func testWhenDismissalsAreClearedThenEveryModelIsShownAgain() {
        sut.setDismissed(modelId: "claude-opus-4-8")
        sut.setDismissed(modelId: "some-future-model")

        sut.clearDismissals()

        XCTAssertFalse(sut.isDismissed(modelId: "claude-opus-4-8"))
        XCTAssertFalse(sut.isDismissed(modelId: "some-future-model"))
    }

    /// Unreadable reads as "not dismissed": showing the notice again is the safe failure.
    func testWhenTheStoredValueIsUnreadableThenNothingIsDismissed() {
        try? keyValueStore.set("not a list", forKey: "aichat.high-usage-notice.dismissed-models")

        XCTAssertFalse(sut.isDismissed(modelId: "claude-opus-4-8"))
    }
}

/// A local stub, matching `DuckAiUsageWarningDismissalStoreTests`.
private final class InMemoryThrowingStore: ThrowingKeyValueStoring {

    private var values: [String: Any] = [:]

    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}
