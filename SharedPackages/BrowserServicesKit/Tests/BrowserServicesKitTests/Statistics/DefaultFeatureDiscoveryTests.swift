//
//  DefaultFeatureDiscoveryTests.swift
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
@testable import BrowserServicesKit
import PersistenceTestingUtils
import BrowserServicesKitTestsUtils

final class DefaultFeatureDiscoveryTests: XCTestCase {

    var featureDiscovery: DefaultFeatureDiscovery!
    var mockStorage: MockKeyValueStore!
    var mockNotificationCenter: NotificationCenter!
    var mockDateProvider: MockCurrentDateProvider!

    override func setUp() {
        super.setUp()
        mockStorage = MockKeyValueStore()
        mockNotificationCenter = NotificationCenter()
        mockDateProvider = MockCurrentDateProvider()
        featureDiscovery = DefaultFeatureDiscovery(
            wasUsedBeforeStorage: mockStorage,
            notificationCenter: mockNotificationCenter,
            dateProvider: mockDateProvider
        )
    }

    override func tearDown() {
        featureDiscovery = nil
        mockNotificationCenter = nil
        mockStorage = nil
        mockDateProvider = nil
        super.tearDown()
    }

    func testSetWasUsedBefore() {
        featureDiscovery.setWasUsedBefore(.aiChat)
        XCTAssertTrue(mockStorage.object(forKey: WasUsedBeforeFeature.aiChat.storageKey) as? Bool ?? false)
    }

    func testWasUsedBeforeWhenSet() {
        mockStorage.set(true, forKey: WasUsedBeforeFeature.duckPlayer.storageKey)
        XCTAssertTrue(featureDiscovery.wasUsedBefore(.duckPlayer))
    }

    func testWasUsedBeforeWhenNotSet() {
        XCTAssertFalse(featureDiscovery.wasUsedBefore(.vpn))
    }

    func testAddToParamsWhenUsedBefore() {
        mockStorage.set(true, forKey: WasUsedBeforeFeature.privacyDashboard.storageKey)
        let params = featureDiscovery.addToParams(["key": "value"], forFeature: .privacyDashboard)
        XCTAssertEqual(params["was_used_before"], "1")
    }

    func testAddToParamsWhenNotUsedBefore() {
        let params = featureDiscovery.addToParams(["key": "value"], forFeature: .privacyDashboard)
        XCTAssertEqual(params["was_used_before"], "0")
    }

    func testNotificationPostedWhenSetWasUsedBefore() {
        let expectation = self.expectation(description: "Notification should be posted")

        let observer = mockNotificationCenter.addObserver(forName: .featureDiscoverySetWasUsedBefore, object: nil, queue: nil) { _ in
            expectation.fulfill()
        }

        featureDiscovery.setWasUsedBefore(.aiChat)

        waitForExpectations(timeout: 1, handler: nil)
        mockNotificationCenter.removeObserver(observer)
    }

    func testSetWasUsedBeforeStoresTimestamp() {
        mockDateProvider.currentDate = Date()
        featureDiscovery.setWasUsedBefore(.aiChat)

        let storedDate = mockStorage.object(forKey: WasUsedBeforeFeature.aiChat.lastUsedTimestampStorageKey) as? Date
        XCTAssertNotNil(storedDate)
    }

    func testSetWasUsedBeforeStoresStartOfDay() {
        let current = Date()
        mockDateProvider.currentDate = current

        featureDiscovery.setWasUsedBefore(.aiChat)

        let storedDate = mockStorage.object(forKey: WasUsedBeforeFeature.aiChat.lastUsedTimestampStorageKey) as? Date
        let expectedStartOfDay = current.startOfDay

        XCTAssertEqual(storedDate, expectedStartOfDay)
    }

    func testDaysSinceLastUsedWhenNeverUsed() {
        let daysSince = featureDiscovery.daysSinceLastUsed(.vpn)
        XCTAssertNil(daysSince)
    }

    func testDaysSinceLastUsedWhenUsedDaysAgo() {
        let startDate = Date(timeIntervalSince1970: 1000000)
        mockDateProvider.currentDate = startDate
        featureDiscovery.setWasUsedBefore(.privacyDashboard)

        // Move forward 5 days
        mockDateProvider.currentDate = startDate.addingTimeInterval(5 * 24 * 60 * 60)

        let daysSince = featureDiscovery.daysSinceLastUsed(.privacyDashboard)
        XCTAssertEqual(daysSince, 5)
    }

    func testMultipleCallsToSetWasUsedBeforeUpdatesTimestamp() {
        let firstDate = Date(timeIntervalSince1970: 1000000)
        mockDateProvider.currentDate = firstDate
        featureDiscovery.setWasUsedBefore(.vpn)

        let firstStoredDate = mockStorage.object(forKey: WasUsedBeforeFeature.vpn.lastUsedTimestampStorageKey) as? Date

        // Move forward a day
        let secondDate = firstDate.addingTimeInterval(.days(1))
        mockDateProvider.currentDate = secondDate
        featureDiscovery.setWasUsedBefore(.vpn)

        let secondStoredDate = mockStorage.object(forKey: WasUsedBeforeFeature.vpn.lastUsedTimestampStorageKey) as? Date

        XCTAssertNotEqual(firstStoredDate, secondStoredDate)
        XCTAssertEqual(secondStoredDate, secondDate.startOfDay)
    }

}
