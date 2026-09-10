//
//  DuckAiUsageWarningDismissalStoreTests.swift
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

final class DuckAiUsageWarningDismissalStoreTests: XCTestCase {

    private let resetsAt = Date(timeIntervalSince1970: 1_755_018_000)
    private var keyValueStore: InMemoryThrowingStore!
    private var sut: DuckAiUsageWarningDismissalStore!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryThrowingStore()
        sut = DuckAiUsageWarningDismissalStore(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Dismissal

    func testWhenNothingWasStoredThenThereIsNoDismissal() {
        XCTAssertNil(sut.dismissal())
    }

    func testDismissalRoundTrips() {
        sut.setDismissal(DuckAiUsageWarningDismissal(noticeID: "approaching", resetsAt: resetsAt))

        let stored = sut.dismissal()
        XCTAssertEqual(stored?.noticeID, "approaching")
        XCTAssertEqual(stored?.resetsAtEpochSeconds, Int(resetsAt.timeIntervalSince1970))
    }

    func testSettingNilClearsTheStoredDismissal() {
        sut.setDismissal(DuckAiUsageWarningDismissal(noticeID: "approaching", resetsAt: resetsAt))

        sut.setDismissal(nil)

        XCTAssertNil(sut.dismissal())
    }

    /// A record we can't read is treated as "not dismissed" — showing the message again is the safe
    /// failure, and it self-heals on the next dismissal.
    func testWhenTheStoredValueIsUnreadableThenThereIsNoDismissal() {
        try? keyValueStore.set(Data("not json".utf8), forKey: "aichat.usage-warning.dismissal")

        XCTAssertNil(sut.dismissal())
    }

    /// `resetsAt` is persisted as whole seconds so a `Codable` round trip can't drift it out of
    /// equality with the notice it has to match.
    func testResetTimestampSurvivesTheRoundTripWithSubSecondPrecision() {
        let fractional = Date(timeIntervalSince1970: 1_755_018_000.4)
        sut.setDismissal(DuckAiUsageWarningDismissal(noticeID: "approaching", resetsAt: fractional))

        XCTAssertTrue(sut.dismissal()?.applies(to: notice(id: .approaching, resetsAt: fractional)) ?? false)
    }

    func testADismissalAppliesOnlyToItsOwnNoticeAndResetPeriod() {
        let dismissal = DuckAiUsageWarningDismissal(notice: notice(id: .approaching, resetsAt: resetsAt))

        XCTAssertTrue(dismissal.applies(to: notice(id: .approaching, resetsAt: resetsAt)))
        XCTAssertFalse(dismissal.applies(to: notice(id: .dailyReached, resetsAt: resetsAt)))
        XCTAssertFalse(dismissal.applies(to: notice(id: .approaching,
                                                   resetsAt: resetsAt.addingTimeInterval(3600))))
    }

    // MARK: - Acted-on snapshot

    func testActedSnapshotRoundTripsAndIsStoredSeparately() {
        sut.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: "dailyReached", signature: "snapshot-1"))

        XCTAssertEqual(sut.actedSnapshot()?.signature, "snapshot-1")
        XCTAssertNil(sut.dismissal())
    }

    func testSettingNilClearsTheActedSnapshot() {
        sut.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: "dailyReached", signature: "snapshot-1"))

        sut.setActedSnapshot(nil)

        XCTAssertNil(sut.actedSnapshot())
    }

    func testAnActedSnapshotAppliesOnlyToItsOwnNoticeAndPayload() {
        let acted = DuckAiUsageWarningActedSnapshot(noticeID: "dailyReached", signature: "snapshot-1")

        XCTAssertTrue(acted.applies(to: notice(id: .dailyReached, resetsAt: resetsAt), signature: "snapshot-1"))
        XCTAssertFalse(acted.applies(to: notice(id: .dailyReached, resetsAt: resetsAt), signature: "snapshot-2"))
        XCTAssertFalse(acted.applies(to: notice(id: .weeklyReached, resetsAt: resetsAt), signature: "snapshot-1"))
        XCTAssertFalse(acted.applies(to: notice(id: .dailyReached, resetsAt: resetsAt), signature: nil))
    }

    // MARK: - Helpers

    private func notice(id: DuckAiUsageNotice.ID, resetsAt: Date) -> DuckAiUsageNotice {
        DuckAiUsageNotice(id: id,
                          window: .daily,
                          percentUsed: id == .approaching ? 75 : 100,
                          resetsAt: resetsAt,
                          reached: id != .approaching,
                          dismissible: id == .approaching)
    }
}

/// A local stub rather than `PersistenceTestingUtils`: only this file needs one, and keeping the
/// dependency out of the test target matches the other native-storage tests.
private final class InMemoryThrowingStore: ThrowingKeyValueStoring {

    private var values: [String: Any] = [:]

    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}
