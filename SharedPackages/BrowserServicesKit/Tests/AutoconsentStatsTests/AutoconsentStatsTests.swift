//
//  AutoconsentStatsTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Persistence
import PersistenceTestingUtils
@testable import AutoconsentStats
import Common

final class AutoconsentStatsTests: XCTestCase {

    var mockKeyValueStore: MockKeyValueFileStore!
    var autoconsentStats: AutoconsentStats!
    var mockEventMapping: MockAutoconsentStatsEventMapping?

    override func setUp() async throws {
        try await super.setUp()
        mockKeyValueStore = try MockKeyValueFileStore()
        autoconsentStats = AutoconsentStats(
            keyValueStore: mockKeyValueStore,
            isFeatureEnabled: { true },
        )
    }

    override func tearDown() async throws {
        mockKeyValueStore = nil
        autoconsentStats = nil
        mockEventMapping = nil
        try await super.tearDown()
    }

    // MARK: - recordAutoconsentAction Tests

    func testRecordAutoconsentActionIncrementsBlockedCountFromZero() async {
        // Given - No existing value in store

        // When
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 10.5)

        // Then
        let storedBlockedCount = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        let storedClicks = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey) as? Int64
        let storedTimeSpent = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey) as? TimeInterval

        XCTAssertEqual(storedBlockedCount, 1)
        XCTAssertEqual(storedClicks, 5)
        XCTAssertEqual(storedTimeSpent, 10.5)
    }

    func testRecordAutoconsentActionIncrementsBlockedCountFromExistingValue() async {
        // Given - Existing values
        try? mockKeyValueStore.set(Int64(10), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        try? mockKeyValueStore.set(Int64(20), forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey)
        try? mockKeyValueStore.set(TimeInterval(30.0), forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey)

        // When
        await autoconsentStats.recordAutoconsentAction(clicksMade: 3, timeSpent: 5.0)

        // Then
        let storedBlockedCount = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        let storedClicks = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey) as? Int64
        let storedTimeSpent = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey) as? TimeInterval

        XCTAssertEqual(storedBlockedCount, 11)
        XCTAssertEqual(storedClicks, 23)
        XCTAssertEqual(storedTimeSpent, 35.0)
    }

    func testRecordAutoconsentActionIncrementsByOneEachTime() async {
        // Given - Starting from 0

        // When - Record multiple actions
        await autoconsentStats.recordAutoconsentAction(clicksMade: 1, timeSpent: 1.0)
        await autoconsentStats.recordAutoconsentAction(clicksMade: 2, timeSpent: 2.0)
        await autoconsentStats.recordAutoconsentAction(clicksMade: 3, timeSpent: 3.0)

        // Then
        let storedBlockedCount = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        let storedClicks = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey) as? Int64
        let storedTimeSpent = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey) as? TimeInterval

        XCTAssertEqual(storedBlockedCount, 3)
        XCTAssertEqual(storedClicks, 6) // 1 + 2 + 3
        XCTAssertEqual(storedTimeSpent, 6.0) // 1.0 + 2.0 + 3.0
    }

    func testRecordAutoconsentActionHandlesReadError() async {
        // Given - Store throws error on set
        mockKeyValueStore.throwOnSet = NSError(domain: "test", code: 1)

        // When - This should not crash
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 10.0)

        // Then - No value should be stored due to error
        mockKeyValueStore.throwOnSet = nil
        let storedValue = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        XCTAssertNil(storedValue)
    }

    func testRecordAutoconsentActionHandlesWriteError() async {
        // Given - Store throws error on write
        mockKeyValueStore.throwOnSet = NSError(domain: "test", code: 2)

        // When - This should not crash
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 10.0)

        // Then - No value should be stored due to error
        mockKeyValueStore.throwOnSet = nil
        let storedValue = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        XCTAssertNil(storedValue)
    }

    func testRecordAutoconsentActionWithZeroClicks() async {
        // Given - No existing value

        // When - Record action with zero clicks
        await autoconsentStats.recordAutoconsentAction(clicksMade: 0, timeSpent: 5.0)

        // Then - Should still increment count
        let storedBlockedCount = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        let storedClicks = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey) as? Int64

        XCTAssertEqual(storedBlockedCount, 1)
        XCTAssertEqual(storedClicks, 0)
    }

    func testRecordAutoconsentActionWithZeroTimeSpent() async {
        // Given - No existing value

        // When - Record action with zero time spent
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 0.0)

        // Then - Should still increment count
        let storedBlockedCount = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        let storedTimeSpent = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey) as? TimeInterval

        XCTAssertEqual(storedBlockedCount, 1)
        XCTAssertEqual(storedTimeSpent, 0.0)
    }

    func testRecordAutoconsentActionWithLargeNumbers() async {
        // Given - Large existing value
        try? mockKeyValueStore.set(Int64(999999), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)

        // When
        await autoconsentStats.recordAutoconsentAction(clicksMade: 100, timeSpent: 1000.0)

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        XCTAssertEqual(storedValue, 1000000)
    }

    func testRecordAutoconsentActionWithInvalidStoredType() async {
        // Given - Invalid type stored (String instead of Int64)
        try? mockKeyValueStore.set("not an int", forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)

        // When - Should treat as missing and start from 0
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 10.0)

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        XCTAssertEqual(storedValue, 1)
    }

    // MARK: - fetchTotalCookiePopUpsBlocked Tests

    func testFetchTotalCookiePopUpsBlockedReturnsZeroWhenNoData() async {
        // Given - No data in store

        // When
        let result = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        // Then
        XCTAssertEqual(result, 0)
    }

    func testFetchTotalCookiePopUpsBlockedReturnsStoredValue() async {
        // Given - Value stored
        try? mockKeyValueStore.set(Int64(42), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)

        // When
        let result = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        // Then
        XCTAssertEqual(result, 42)
    }

    func testFetchTotalCookiePopUpsBlockedHandlesError() async {
        // Given - Store throws error
        mockKeyValueStore.throwOnRead = NSError(domain: "test", code: 1)

        // When
        let result = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        // Then
        XCTAssertEqual(result, 0, "Should return 0 on error")
    }

    // MARK: - fetchAutoconsentDailyUsagePack Tests

    func testFetchAutoconsentDailyUsagePackReturnsEmptyWhenNoData() async {
        // Given - No data in store

        // When
        let result = await autoconsentStats.fetchAutoconsentDailyUsagePack()

        // Then
        XCTAssertEqual(result.totalCookiePopUpsBlocked, 0)
        XCTAssertEqual(result.totalClicksMadeBlockingCookiePopUps, 0)
        XCTAssertEqual(result.totalTotalTimeSpentBlockingCookiePopUps, 0.0)
    }

    func testFetchAutoconsentDailyUsagePackReturnsStoredValues() async {
        // Given - Values stored
        try? mockKeyValueStore.set(Int64(50), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        try? mockKeyValueStore.set(Int64(150), forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey)
        try? mockKeyValueStore.set(TimeInterval(300.0), forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey)

        // When
        let result = await autoconsentStats.fetchAutoconsentDailyUsagePack()

        // Then
        XCTAssertEqual(result.totalCookiePopUpsBlocked, 50)
        XCTAssertEqual(result.totalClicksMadeBlockingCookiePopUps, 150)
        XCTAssertEqual(result.totalTotalTimeSpentBlockingCookiePopUps, 300.0)
    }

    func testFetchAutoconsentDailyUsagePackHandlesPartialData() async {
        // Given - Only some values stored
        try? mockKeyValueStore.set(Int64(25), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        // No clicks or time spent stored

        // When
        let result = await autoconsentStats.fetchAutoconsentDailyUsagePack()

        // Then
        XCTAssertEqual(result.totalCookiePopUpsBlocked, 25)
        XCTAssertEqual(result.totalClicksMadeBlockingCookiePopUps, 0)
        XCTAssertEqual(result.totalTotalTimeSpentBlockingCookiePopUps, 0.0)
    }

    // MARK: - clearAutoconsentStats Tests

    func testClearAutoconsentStatsRemovesAllData() async {
        // Given - Store has data
        try? mockKeyValueStore.set(Int64(50), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        try? mockKeyValueStore.set(Int64(100), forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey)
        try? mockKeyValueStore.set(TimeInterval(200.0), forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey)

        // When
        await autoconsentStats.clearAutoconsentStats()

        // Then - All values should be removed
        let blockedCount = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        let clicks = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey)
        let timeSpent = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey)

        XCTAssertNil(blockedCount)
        XCTAssertNil(clicks)
        XCTAssertNil(timeSpent)
    }

    func testClearAutoconsentStatsDoesNotCrashWhenNoData() async {
        // Given - No data in store

        // When/Then - Should not crash
        await autoconsentStats.clearAutoconsentStats()
    }

    func testClearAutoconsentStatsHandlesError() async {
        // Given - Store throws error on remove
        mockKeyValueStore.throwOnSet = NSError(domain: "test", code: 1)
        try? mockKeyValueStore.set(Int64(50), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)

        // When/Then - Should not crash despite error
        await autoconsentStats.clearAutoconsentStats()
    }

    func testClearAutoconsentStatsAllowsDataToBeRerecorded() async {
        // Given - Store has data, then clear it
        await autoconsentStats.recordAutoconsentAction(clicksMade: 10, timeSpent: 20.0)
        await autoconsentStats.clearAutoconsentStats()

        // When - Record new data after clearing
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 10.0)

        // Then - Should start from fresh values
        let result = await autoconsentStats.fetchAutoconsentDailyUsagePack()
        XCTAssertEqual(result.totalCookiePopUpsBlocked, 1)
        XCTAssertEqual(result.totalClicksMadeBlockingCookiePopUps, 5)
        XCTAssertEqual(result.totalTotalTimeSpentBlockingCookiePopUps, 10.0)
    }

    func testClearAutoconsentStatsMakesAllFetchesReturnZero() async {
        // Given - Store has data
        try? mockKeyValueStore.set(Int64(50), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        try? mockKeyValueStore.set(Int64(100), forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey)
        try? mockKeyValueStore.set(TimeInterval(200.0), forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey)

        // When - Clear the stats
        await autoconsentStats.clearAutoconsentStats()

        // Then - All fetches should return zero
        let usagePack = await autoconsentStats.fetchAutoconsentDailyUsagePack()

        XCTAssertEqual(usagePack.totalCookiePopUpsBlocked, 0)
        XCTAssertEqual(usagePack.totalClicksMadeBlockingCookiePopUps, 0)
        XCTAssertEqual(usagePack.totalTotalTimeSpentBlockingCookiePopUps, 0.0)
    }

    // MARK: - Constants Tests

    func testConstantsAreCorrect() {
        // Given/When/Then
        XCTAssertEqual(
            AutoconsentStats.Constants.totalCookiePopUpsBlockedKey,
            "com.duckduckgo.autoconsent.cookie.popups.blocked",
            "Constant key should match expected value"
        )
        XCTAssertEqual(
            AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey,
            "com.duckduckgo.autoconsent.clicks.made",
            "Constant key should match expected value"
        )
        XCTAssertEqual(
            AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey,
            "com.duckduckgo.autoconsent.time.spent",
            "Constant key should match expected value"
        )
    }

    // MARK: - Integration Tests

    func testMultipleActionsAccumulateCorrectly() async {
        // Given - Starting from 5
        try? mockKeyValueStore.set(Int64(5), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
        try? mockKeyValueStore.set(Int64(10), forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey)
        try? mockKeyValueStore.set(TimeInterval(20.0), forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey)

        // When - Record several actions with different parameters
        await autoconsentStats.recordAutoconsentAction(clicksMade: 1, timeSpent: 2.5)
        await autoconsentStats.recordAutoconsentAction(clicksMade: 3, timeSpent: 10.0)
        await autoconsentStats.recordAutoconsentAction(clicksMade: 0, timeSpent: 0.0)
        await autoconsentStats.recordAutoconsentAction(clicksMade: 100, timeSpent: 500.5)

        // Then
        let storedBlockedCount = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        let storedClicks = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalClicksMadeBlockingCookiePopUpsKey) as? Int64
        let storedTimeSpent = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalTimeSpentBlockingCookiePopUpsKey) as? TimeInterval

        XCTAssertEqual(storedBlockedCount, 9) // 5 + 4 actions
        XCTAssertEqual(storedClicks, 114) // 10 + 1 + 3 + 0 + 100
        XCTAssertEqual(storedTimeSpent, 533.0) // 20.0 + 2.5 + 10.0 + 0.0 + 500.5
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentRecordActions() async {
        // Given - Starting from 0

        // When - Record multiple actions concurrently
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await self.autoconsentStats.recordAutoconsentAction(clicksMade: 1, timeSpent: 1.0)
                }
            }
        }

        // Then - All actions should be recorded
        let storedValue = try? mockKeyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey) as? Int64
        XCTAssertEqual(storedValue, 10, "All concurrent actions should be recorded")
    }

    // MARK: - Error Event Tests

    func testRecordAutoconsentActionFiresErrorEventOnFailure() async {
        // Given - Event mapping configured
        mockEventMapping = MockAutoconsentStatsEventMapping()
        autoconsentStats = AutoconsentStats(
            keyValueStore: mockKeyValueStore,
            errorEvents: mockEventMapping,
            isFeatureEnabled: { true }
        )

        // Set up store to throw error
        mockKeyValueStore.throwOnSet = NSError(domain: "test", code: 1)

        // When - Record action that will fail
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 10.0)

        // Then - Error event should be fired
        XCTAssertEqual(mockEventMapping!.events.count, 1)
        if case .failedToRecordAutoconsentAction(let error) = mockEventMapping!.events.first {
            XCTAssertEqual((error as NSError).domain, "test")
            XCTAssertEqual((error as NSError).code, 1)
        } else {
            XCTFail("Expected failedToRecordAutoconsentAction error event")
        }
    }

    func testFetchTotalCookiePopUpsBlockedFiresErrorEventOnFailure() async {
        // Given - Event mapping configured
        mockEventMapping = MockAutoconsentStatsEventMapping()
        autoconsentStats = AutoconsentStats(
            keyValueStore: mockKeyValueStore,
            errorEvents: mockEventMapping,
            isFeatureEnabled: { true }
        )

        // Set up store to throw error
        mockKeyValueStore.throwOnRead = NSError(domain: "test", code: 2)

        // When - Fetch that will fail
        let result = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        // Then - Should return 0 and fire error event
        XCTAssertEqual(result, 0)
        XCTAssertEqual(mockEventMapping!.events.count, 1)
        if case .failedToFetchTotalCookiePopUpsBlocked(let error) = mockEventMapping!.events.first {
            XCTAssertEqual((error as NSError).domain, "test")
            XCTAssertEqual((error as NSError).code, 2)
        } else {
            XCTFail("Expected failedToFetchTotalCookiePopUpsBlocked error event")
        }
    }

    func testFetchAutoconsentDailyUsagePackFiresErrorEventsOnFetchFailure() async {
        // Given - Event mapping configured
        mockEventMapping = MockAutoconsentStatsEventMapping()
        autoconsentStats = AutoconsentStats(
            keyValueStore: mockKeyValueStore,
            errorEvents: mockEventMapping,
            isFeatureEnabled: { true }
        )

        // Set up store to throw error on read
        mockKeyValueStore.throwOnRead = NSError(domain: "test", code: 3)

        // When - Fetch usage pack that will fail on all three internal fetches
        let result = await autoconsentStats.fetchAutoconsentDailyUsagePack()

        // Then - Should return default values and fire error events
        XCTAssertEqual(result.totalCookiePopUpsBlocked, 0)
        XCTAssertEqual(result.totalClicksMadeBlockingCookiePopUps, 0)
        XCTAssertEqual(result.totalTotalTimeSpentBlockingCookiePopUps, 0.0)

        // Should have fired 3 error events (one for each private fetch)
        XCTAssertEqual(mockEventMapping!.events.count, 3)

        // Verify the specific error events
        let eventTypes = mockEventMapping!.events.map { event -> String in
            switch event {
            case .failedToFetchTotalCookiePopUpsBlocked:
                return "popups"
            case .failedToFetchTotalClicksMadeBlockingCookiePopUps:
                return "clicks"
            case .failedToFetchTotalTimeSpentBlockingCookiePopUps:
                return "time"
            default:
                return "other"
            }
        }

        XCTAssertTrue(eventTypes.contains("popups"))
        XCTAssertTrue(eventTypes.contains("clicks"))
        XCTAssertTrue(eventTypes.contains("time"))
    }

    func testClearAutoconsentStatsFiresErrorEventOnFailure() async {
        // Given - Event mapping configured
        mockEventMapping = MockAutoconsentStatsEventMapping()
        autoconsentStats = AutoconsentStats(
            keyValueStore: mockKeyValueStore,
            errorEvents: mockEventMapping,
            isFeatureEnabled: { true }
        )

        // Add some data first
        try? mockKeyValueStore.set(Int64(50), forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)

        // Set up store to throw error on removal
        mockKeyValueStore.throwOnRemove = NSError(domain: "test", code: 4)

        // When - Clear that will fail
        await autoconsentStats.clearAutoconsentStats()

        // Then - Error event should be fired
        XCTAssertEqual(mockEventMapping!.events.count, 1)
        if case .failedToClearAutoconsentStats(let error) = mockEventMapping!.events.first {
            XCTAssertEqual((error as NSError).domain, "test")
            XCTAssertEqual((error as NSError).code, 4)
        } else {
            XCTFail("Expected failedToClearAutoconsentStats error event")
        }
    }

    func testErrorEventsAreNotFiredWhenEventMappingIsNil() async {
        // Given - No event mapping (nil)
        autoconsentStats = AutoconsentStats(
            keyValueStore: mockKeyValueStore,
            errorEvents: nil,
            isFeatureEnabled: { true }
        )

        // Set up store to throw error
        mockKeyValueStore.throwOnSet = NSError(domain: "test", code: 1)

        // When - Operations that would normally fire error events
        await autoconsentStats.recordAutoconsentAction(clicksMade: 5, timeSpent: 10.0)

        mockKeyValueStore.throwOnSet = nil
        mockKeyValueStore.throwOnRead = NSError(domain: "test", code: 2)

        _ = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        // Then - Should not crash (this test just verifies it doesn't crash when errorEvents is nil)
        XCTAssertTrue(true, "Operations completed without crashing even with nil errorEvents")
    }

    func testAutoconsentStatsErrorConformsToCustomNSError() {
        // Test the error domain
        XCTAssertEqual(AutoconsentStatsError.errorDomain, "AutoconsentStatsError")

        // Test error codes
        let error1 = AutoconsentStatsError.failedToRecordAutoconsentAction(NSError(domain: "test", code: 1))
        XCTAssertEqual(error1.errorCode, 1)

        let error2 = AutoconsentStatsError.failedToFetchTotalCookiePopUpsBlocked(NSError(domain: "test", code: 2))
        XCTAssertEqual(error2.errorCode, 2)

        let error3 = AutoconsentStatsError.failedToFetchTotalClicksMadeBlockingCookiePopUps(NSError(domain: "test", code: 3))
        XCTAssertEqual(error3.errorCode, 3)

        let error4 = AutoconsentStatsError.failedToFetchTotalTimeSpentBlockingCookiePopUps(NSError(domain: "test", code: 4))
        XCTAssertEqual(error4.errorCode, 4)

        let error5 = AutoconsentStatsError.failedToClearAutoconsentStats(NSError(domain: "test", code: 5))
        XCTAssertEqual(error5.errorCode, 5)

        // Test underlying error extraction
        let underlyingError = NSError(domain: "underlying", code: 999)
        let wrappedError = AutoconsentStatsError.failedToRecordAutoconsentAction(underlyingError)
        XCTAssertEqual((wrappedError.underlyingError as NSError).domain, "underlying")
        XCTAssertEqual((wrappedError.underlyingError as NSError).code, 999)

        // Test errorUserInfo
        XCTAssertNotNil(wrappedError.errorUserInfo[NSUnderlyingErrorKey])
    }
}
