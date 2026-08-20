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

import PersistenceTestingUtils
import XCTest
@testable import AIChat

final class DuckAiUsageWarningDismissalStoreTests: XCTestCase {

    private let resetsAt = Date(timeIntervalSince1970: 1_755_018_000)
    private var keyValueStore: MockThrowingKeyValueStore!
    private var sut: DuckAiUsageWarningDismissalStore!

    override func setUp() {
        super.setUp()
        keyValueStore = MockThrowingKeyValueStore()
        sut = DuckAiUsageWarningDismissalStore(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }

    func testWhenNothingWasStoredThenThereIsNoDismissal() {
        XCTAssertNil(sut.dismissal(for: .daily))
        XCTAssertNil(sut.dismissal(for: .weekly))
    }

    func testDismissalRoundTrips() {
        sut.setDismissal(DuckAiUsageWarningDismissal(resetsAt: resetsAt, threshold: 75), for: .weekly)

        let stored = sut.dismissal(for: .weekly)
        XCTAssertEqual(stored?.threshold, 75)
        XCTAssertTrue(stored?.applies(to: resetsAt) ?? false)
    }

    func testWindowsAreStoredIndependently() {
        sut.setDismissal(DuckAiUsageWarningDismissal(resetsAt: resetsAt, threshold: 50), for: .daily)

        XCTAssertNotNil(sut.dismissal(for: .daily))
        XCTAssertNil(sut.dismissal(for: .weekly))
    }

    func testSettingNilClearsTheStoredDismissal() {
        sut.setDismissal(DuckAiUsageWarningDismissal(resetsAt: resetsAt, threshold: 50), for: .daily)

        sut.setDismissal(nil, for: .daily)

        XCTAssertNil(sut.dismissal(for: .daily))
    }

    /// A record we can't read is treated as "not dismissed" — showing the message again is the safe
    /// failure, and it self-heals on the next dismissal.
    func testWhenTheStoredValueIsUnreadableThenThereIsNoDismissal() {
        try? keyValueStore.set(Data("not json".utf8), forKey: "aichat.usage-warning.dismissal.daily")

        XCTAssertNil(sut.dismissal(for: .daily))
    }

    /// `resetsAt` is persisted as whole seconds so a `Codable` round trip can't drift it out of equality
    /// with the snapshot it has to match.
    func testResetTimestampSurvivesTheRoundTripWithSubSecondPrecision() {
        let fractional = Date(timeIntervalSince1970: 1_755_018_000.4)
        sut.setDismissal(DuckAiUsageWarningDismissal(resetsAt: fractional, threshold: 50), for: .daily)

        XCTAssertTrue(sut.dismissal(for: .daily)?.applies(to: fractional) ?? false)
    }
}
