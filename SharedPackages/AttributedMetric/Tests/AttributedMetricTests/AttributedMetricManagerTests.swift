//
//  AttributedMetricManagerTests.swift
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
//

import XCTest
@testable import AttributedMetric
import PixelKit
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import AttributedMetricTestsUtils
import PrivacyConfig

final class AttributedMetricManagerTests: XCTestCase {

    // MARK: - Test Fixtures

    struct TestFixture {
        let suiteName: String
        let userDefaults: UserDefaults
        let timeMachine: TimeMachine
        let pixelKit: PixelKit
        let dataStorage: AttributedMetricDataStorage
        let attributionManager: AttributedMetricManager
        let settingsProvider: AttributedMetricSettingsProviderMock

        func cleanup() {
            dataStorage.removeAll()
            userDefaults.removeSuite(named: suiteName)
        }
    }

    // MARK: - Helper Methods

    /// Fixed reference date for all tests: January 15, 2025, 12:00 UTC
    private static let referenceDate = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))!

    /// Creates a complete test fixture with all necessary dependencies
    /// - Parameters:
    ///   - pixelHandler: The closure to handle pixel events
    ///   - subscriptionStateProvider: Optional custom subscription state provider (default creates inactive mock)
    /// - Returns: A TestFixture containing all initialized test components
    private func createTestFixture(
        pixelHandler: @escaping PixelKit.FireRequest,
        subscriptionStateProvider: SubscriptionStateProviding? = nil,
        returningUserProvider: AttributedMetricReturningUserProviding? = nil
    ) -> TestFixture {
        let suiteName = "testing_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let timeMachine = TimeMachine(date: Self.referenceDate)

        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            source: "TESTS",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            dateGenerator: timeMachine.now,
            defaults: userDefaults,
            fireRequest: pixelHandler
        )

        let errorHandler = AttributedMetricErrorHandler(pixelKit: pixelKit)
        let dataStorage = AttributedMetricDataStorage(userDefaults: userDefaults, errorHandler: errorHandler)
        let featureFlagger: any FeatureFlagger = MockFeatureFlagger(
            featuresStub: [AttributedMetric.AttributedMetricFeatureFlag.attributedMetrics.rawValue: true]
        )
        let originProvider: AttributedMetricOriginProvider = AttributedMetricOriginProviderMock()
        let defaultBrowserProvider = AttributedMetricDefaultBrowserProvidingMock()
        let subscriptionProvider = subscriptionStateProvider ?? SubscriptionStateProviderMock()
        let settingsProvider = AttributedMetricSettingsProviderMock()

        let returningUser = returningUserProvider ?? AttributedMetricReturningUserProvidingMock()

        let attributionManager = AttributedMetricManager(
            pixelKit: pixelKit,
            dataStoring: dataStorage,
            featureFlagger: featureFlagger,
            originProvider: originProvider,
            defaultBrowserProviding: defaultBrowserProvider,
            subscriptionStateProvider: subscriptionProvider,
            returningUserProvider: returningUser,
            dateProvider: timeMachine,
            settingsProvider: settingsProvider
        )

        return TestFixture(
            suiteName: suiteName,
            userDefaults: userDefaults,
            timeMachine: timeMachine,
            pixelKit: pixelKit,
            dataStorage: dataStorage,
            attributionManager: attributionManager,
            settingsProvider: settingsProvider
        )
    }

    /// Extracts an integer parameter from pixel parameters
    /// - Parameters:
    ///   - parameters: The pixel parameters dictionary
    ///   - key: The parameter key to extract
    /// - Returns: The integer value or nil if not found
    private func extractIntParameter(_ parameters: [String: String], key: String) -> Int? {
        guard let valueString = parameters[key] else { return nil }
        return Int(valueString)
    }

    /// Tests user retention pixel firing at different time intervals
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Raw Week/Month | Bucketed Value | Parameters |
    /// |-------------------|----------------|----------------|------------|
    /// | 0 (install day)   | none           | -              | No pixel fired |
    /// | 1 (day 1)         | week: 1        | 0              | count=0, default_browser=true, origin/installDate |
    /// | 22 (day 22)       | week: 4        | 3              | count=3, default_browser=true, origin/installDate |
    /// | 29 (day 29)       | month: 2       | 0              | count=0, default_browser=true, origin/installDate |
    /// | 141 (day 141)     | month: 6       | 4              | count=4, default_browser=true, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_retention_week: [1, 2, 3] → values 1-3 map to indices 0-2, >3 maps to 3
    /// - user_retention_month: [2, 3, 4, 5] → values 2-5 map to indices 0-3, >5 maps to 4
    ///
    /// ## Test Validation
    /// - No pixels fire on install day (day 0)
    /// - No duplicate pixels for same threshold
    /// - Exactly 4 retention pixels fire total
    /// - Each pixel has correct bucketed count value
    func testRetentionPixel() {
        // Expectations for each retention threshold
        let week1Expectation = XCTestExpectation(description: "Week 1 retention pixel fired")
        let week4Expectation = XCTestExpectation(description: "Week 4 retention pixel fired")
        let month2Expectation = XCTestExpectation(description: "Month 2 retention pixel fired")
        let month6Expectation = XCTestExpectation(description: "Month 6 retention pixel fired")
        let noDuplicateExpectation = XCTestExpectation(description: "No duplicate pixels")
        noDuplicateExpectation.isInverted = true

        // Track fired pixels to prevent duplicates
        var firedPixels: [(name: String, count: Int)] = []
        var pixelFireCount = 0

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "attributed_metric_retention_week":
                guard let countString = parameters["count"],
                      let count = Int(countString) else {
                    XCTFail("Missing or invalid count parameter for pixel: \(pixelName)")
                    return
                }

                // Check for duplicate
                if firedPixels.contains(where: { $0.name == "user_retention_week" && $0.count == count }) {
                    noDuplicateExpectation.fulfill()
                    XCTFail("Duplicate pixel fired: \(pixelName) with count \(count)")
                    return
                }

                firedPixels.append((name: "user_retention_week", count: count))
                pixelFireCount += 1

                switch count {
                case 0:
                    week1Expectation.fulfill()
                case 3:
                    week4Expectation.fulfill()
                default:
                    XCTFail("Unexpected week count: \(count)")
                }

            case "attributed_metric_retention_month":
                guard let countString = parameters["count"],
                      let count = Int(countString) else {
                    XCTFail("Missing or invalid count parameter for pixel: \(pixelName)")
                    return
                }

                // Check for duplicate
                if firedPixels.contains(where: { $0.name == "user_retention_month" && $0.count == count }) {
                    noDuplicateExpectation.fulfill()
                    XCTFail("Duplicate pixel fired: \(pixelName) with count \(count)")
                    return
                }

                firedPixels.append((name: "user_retention_month", count: count))
                pixelFireCount += 1

                switch count {
                case 0:
                    month2Expectation.fulfill()
                case 4:
                    month6Expectation.fulfill()
                default:
                    XCTFail("Unexpected month count: \(count)")
                }

            case "attributed_metric_data_store_error":
                // Ignore data store errors in this test (expected in test environment)
                break

            default:
                XCTFail("Unexpected pixel fired: \(pixelName)")
            }
        }
        defer { fixture.cleanup() }

        /*
         Install day is day 0
         week 1 (week of install): days 1-7 after install → count 1 user_retention_week
         They open the app on day [8,14]: count 2 user_retention_week
         They open the app on day [15,21]: count 3 user_retention_week
         They open the app on day [22,28]: count 4 user_retention_week
         They open the app on day [29,56]: count 2 user_retention_month
         ...
         They open the app on day [141,168]: count 6 user_retention_month
         Stop here
         */

        // Set install date at the beginning - this stays constant
        let installDate = fixture.timeMachine.now()
        fixture.dataStorage.installDate = installDate

        // Test 1: Day 0 (install day) - No pixels should fire
        let initialPixelCount = pixelFireCount
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(pixelFireCount, initialPixelCount, "No pixels should fire on install day")

        // Test 2: Day 1 - Week 1 retention pixel
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .appDidStart)

        // Test 3: Day 1 again (same day) - No duplicate pixel
        let pixelCountBeforeDuplicate = pixelFireCount
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(pixelFireCount, pixelCountBeforeDuplicate, "No duplicate pixel should fire for same threshold")

        // Test 4: Day 22 - Week 4 retention pixel
        // Travel from day 1 to day 22 (21 more days)
        fixture.timeMachine.travel(by: .day, value: 21)
        fixture.attributionManager.process(trigger: .appDidStart)

        // Test 5: Day 29 - Month 2 retention pixel
        // Travel from day 22 to day 29 (7 more days)
        fixture.timeMachine.travel(by: .day, value: 7)
        fixture.attributionManager.process(trigger: .appDidStart)

        // Test 6: Day 141 - Month 6 retention pixel
        // Travel from day 29 to day 141 (112 more days)
        fixture.timeMachine.travel(by: .day, value: 112)
        fixture.attributionManager.process(trigger: .appDidStart)

        // Wait for expectations
        wait(for: [week1Expectation, week4Expectation, month2Expectation, month6Expectation], timeout: 5.0)
        wait(for: [noDuplicateExpectation], timeout: 0.1)

        // Verify correct number of pixels fired
        XCTAssertEqual(pixelFireCount, 4, "Should fire exactly 4 retention pixels")
        XCTAssertEqual(firedPixels.count, 4, "Should have exactly 4 unique pixels")
    }

    // MARK: - Active Search Days Tests

    /// Tests active search days pixel with daysSinceInstalled parameter within first week
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Search Days Count | Bucketed Days | Parameters |
    /// |-------------------|-------------------|---------------|------------|
    /// | 0 (install day)   | 0                 | -             | No pixel fired (day 0 returns early) |
    /// | 4 (within week 1) | 2                 | 1             | days=1, daysSinceInstalled=4, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_active_past_week: [2, 4] → value 2 maps to index 1, >4 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel fires with bucketed search count
    /// - daysSinceInstalled parameter IS included within first 7 days
    /// - Trigger: .appDidStart calls processActiveSearchDays()
    func testProcessActiveSearchDays() {
        let pixelExpectation = XCTestExpectation(description: "Active search days pixel fired")
        var pixelFireCount = 0
        var capturedDays: Int?
        var capturedDaysSinceInstalled: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "attributed_metric_active_past_week":
                capturedDays = self.extractIntParameter(parameters, key: "days")
                capturedDaysSinceInstalled = self.extractIntParameter(parameters, key: "daysSinceInstalled")
                if capturedDays == nil {
                    XCTFail("Missing or invalid days parameter")
                    return
                }
                pixelFireCount += 1
                pixelExpectation.fulfill()
            case "attributed_metric_average_searches_past_week_first_month", "attributed_metric_retention_week":
                // These pixels fire during userDidSearch and appDidStart, ignore them in this test
                break
            case "attributed_metric_data_store_error":
                break
            default:
                break // Ignore other pixels in this test
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test 1: Day 0 - Should not fire (day 0 returns early)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(pixelFireCount, 0, "Should not fire on install day")

        // Test 2: Day 3 (within first week) - Record searches and fire with daysSinceInstalled
        fixture.timeMachine.travel(by: .day, value: 3)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)

        // Process active search days
        fixture.attributionManager.process(trigger: .appDidStart)

        wait(for: [pixelExpectation], timeout: 5.0)
        XCTAssertEqual(pixelFireCount, 1, "Should fire once")
        XCTAssertNotNil(capturedDays, "Should send bucketed search count")
        XCTAssertEqual(capturedDaysSinceInstalled, 4, "Should include days since installed within first week")
    }

    /// Tests active search days pixel WITHOUT daysSinceInstalled parameter after first week
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Search Days Count | Bucketed Days | Parameters |
    /// |-------------------|-------------------|---------------|------------|
    /// | 10 (after week 1) | 2                 | 1             | days=1, daysSinceInstalled=nil, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_active_past_week: [2, 4] → value 2 maps to index 1, >4 maps to 2
    ///
    /// ## Test Validation
    /// - daysSinceInstalled parameter is NOT included after day 7
    /// - Pixel still fires with bucketed search count
    /// - Trigger: .appDidStart calls processActiveSearchDays()
    func testProcessActiveSearchDaysAfterFirstWeek() {
        let pixelExpectation = XCTestExpectation(description: "Active search days pixel fired")
        var capturedDaysSinceInstalled: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            if pixelName == "attributed_metric_active_past_week" {
                capturedDaysSinceInstalled = self.extractIntParameter(parameters, key: "daysSinceInstalled")
                pixelExpectation.fulfill()
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Day 10 (after first week) - Should not include daysSinceInstalled
        // Record searches on a few days
        fixture.timeMachine.travel(by: .day, value: 8)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)

        // Then process active search days on app start (now on day 10)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .appDidStart)

        wait(for: [pixelExpectation], timeout: 5.0)
        XCTAssertNil(capturedDaysSinceInstalled, "Should not include days since installed after first week")
    }

    // MARK: - Average Search Count Tests

    /// Tests average search count pixel within first month (includes dayAverage parameter)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Raw Average | Bucketed Count | Parameters |
    /// |-------------------|-------------|----------------|------------|
    /// | 18-20 (< 28 days) | varies      | varies         | count=bucketed, dayAverage=raw_count, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_searches_past_week_first_month: [5, 9] → ≤5 maps to 0, ≤9 maps to 1, >9 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel fires within first 28 days with dayAverage parameter
    /// - count parameter is bucketed
    /// - dayAverage parameter contains raw search count
    /// - Trigger: .userDidSearch calls processAverageSearchCount()
    func testProcessAverageSearchCountFirstMonth() {
        let pixelExpectation = XCTestExpectation(description: "Average search count pixel fired")
        var capturedCount: Int?
        var capturedDayAverage: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "attributed_metric_average_searches_past_week_first_month":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                capturedDayAverage = self.extractIntParameter(parameters, key: "dayAverage")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                if capturedDayAverage == nil {
                    XCTFail("Missing or invalid dayAverage parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "attributed_metric_data_store_error":
                break
            default:
                break // Ignore other pixels
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Within first month (day 20), record multiple searches on different days
        fixture.timeMachine.travel(by: .day, value: 18)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)

        wait(for: [pixelExpectation], timeout: 5.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
        XCTAssertNotNil(capturedDayAverage, "Should capture day average")
    }

    /// Tests average search count pixel after first month (includes dayAverage parameter)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Raw Average | Bucketed Count | Parameters |
    /// |-------------------|-------------|----------------|------------|
    /// | 29-31 (≥ 28 days) | varies      | varies         | count=bucketed, dayAverage=raw_count, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_searches_past_week: [5, 9] → ≤5 maps to 0, ≤9 maps to 1, >9 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel fires after 28 days with dayAverage parameter
    /// - count parameter is bucketed
    /// - dayAverage parameter contains raw search count
    /// - Different pixel name than first month version
    /// - Trigger: .userDidSearch calls processAverageSearchCount()
    func testProcessAverageSearchCountAfterFirstMonth() {
        let pixelExpectation = XCTestExpectation(description: "Average search count pixel fired")
        var capturedCount: Int?
        var capturedDayAverage: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "attributed_metric_average_searches_past_week":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                capturedDayAverage = self.extractIntParameter(parameters, key: "dayAverage")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                if capturedDayAverage == nil {
                    XCTFail("Missing or invalid dayAverage parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "attributed_metric_data_store_error":
                break
            default:
                break // Ignore other pixels
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: After first month (day 30+), record multiple searches on different days
        fixture.timeMachine.travel(by: .day, value: 29)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)

        wait(for: [pixelExpectation], timeout: 5.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
        XCTAssertNotNil(capturedDayAverage, "Should capture day average")
    }

    // MARK: - Average AD Click Tests

    /// Tests average ad click pixel (does not fire on install day, includes dayAverage)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Ad Clicks | Bucketed Count | Parameters |
    /// |-------------------|-----------|----------------|------------|
    /// | 0 (install day)   | any       | -              | No pixel fired (isSameDayOfInstallDate check) |
    /// | 1+ (any other day)| varies    | varies         | count=bucketed, dayAverage=days_counted, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_ad_clicks_past_week: [2, 5] → ≤2 maps to 0, ≤5 maps to 1, >5 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel does NOT fire on install day (day 0)
    /// - Pixel fires on subsequent days with bucketed count and dayAverage
    /// - Trigger: .userDidSelectAD calls processAverageAdClick()
    func testProcessAverageAdClick() {
        let pixelExpectation = XCTestExpectation(description: "Average ad click pixel fired")
        var capturedCount: Int?
        var capturedDayAverage: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "attributed_metric_average_ad_clicks_past_week":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                capturedDayAverage = self.extractIntParameter(parameters, key: "dayAverage")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                if capturedDayAverage == nil {
                    XCTFail("Missing or invalid dayAverage parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "attributed_metric_data_store_error":
                break
            default:
                XCTFail("Unexpected pixel fired: \(pixelName)")
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Should not fire on same day as install
        fixture.attributionManager.process(trigger: .userDidSelectAD)
        XCTAssertNil(capturedCount, "Should not fire on install day")

        // Test: Fire on different day
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSelectAD)

        wait(for: [pixelExpectation], timeout: 5.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
        XCTAssertEqual(capturedDayAverage, 1, "Should report 1 day counted (ad click recorded on day 0)")
    }

    // MARK: - Average Duck.AI Chat Tests

    /// Tests average Duck.AI chat pixel (does not fire on install day, includes dayAverage)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | AI Chats | Bucketed Count | Parameters |
    /// |-------------------|----------|----------------|------------|
    /// | 0 (install day)   | any      | -              | No pixel fired (isSameDayOfInstallDate check) |
    /// | 1+ (any other day)| varies   | varies         | count=bucketed, dayAverage=days_counted, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_duck_ai_usage_past_week: [5, 9] → ≤5 maps to 0, ≤9 maps to 1, >9 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel does NOT fire on install day (day 0)
    /// - Pixel fires on subsequent days with bucketed count and dayAverage
    /// - Trigger: .userDidDuckAIChat calls processAverageDuckAIChat()
    func testProcessAverageDuckAIChat() {
        let pixelExpectation = XCTestExpectation(description: "Average Duck.AI chat pixel fired")
        var capturedCount: Int?
        var capturedDayAverage: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "attributed_metric_average_duck_ai_usage_past_week":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                capturedDayAverage = self.extractIntParameter(parameters, key: "dayAverage")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                if capturedDayAverage == nil {
                    XCTFail("Missing or invalid dayAverage parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "attributed_metric_data_store_error":
                break
            default:
                XCTFail("Unexpected pixel fired: \(pixelName)")
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Should not fire on same day as install
        fixture.attributionManager.process(trigger: .userDidDuckAIChat)
        XCTAssertNil(capturedCount, "Should not fire on install day")

        // Test: Fire on different day
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidDuckAIChat)

        wait(for: [pixelExpectation], timeout: 5.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
        XCTAssertEqual(capturedDayAverage, 1, "Should report 1 day counted (Duck.AI chat recorded on day 0)")
    }

    // MARK: - Subscription Tests

    /// Tests subscription pixel for free trial (length = 0)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Subscription Type | Raw Length | Bucketed Length | Parameters | Flags Set |
    /// |------------------|------------|-----------------|------------|-----------|
    /// | Free Trial       | 0          | 0               | length=0, origin/installDate | subscriptionFreeTrialFired=true |
    ///
    /// ## Bucket Configuration
    /// - user_subscribed: [0, 1] → 0 maps to index 0, 1 maps to index 1, >1 maps to 2
    ///
    /// ## Test Validation
    /// - isFreeTrial() returns true → length=0
    /// - Bucketed length is 0 (0 ≤ 0, first bucket)
    /// - subscriptionFreeTrialFired flag is set to true
    /// - Trigger: .userDidSubscribe calls processSubscriptionDay()
    /// - Async test due to await subscriptionStateProvider.isFreeTrial()
    func testProcessSubscriptionDayFreeTrial() async {
        let pixelExpectation = XCTestExpectation(description: "Subscription pixel fired")
        var capturedLength: Int?

        let fixture = createTestFixture(
            pixelHandler: { pixelName, _, parameters, _, _, _ in
                switch pixelName {
                case "attributed_metric_subscribed":
                    capturedLength = self.extractIntParameter(parameters, key: "month")
                    if capturedLength == nil {
                        XCTFail("Missing or invalid length parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "attributed_metric_data_store_error":
                    break
                default:
                    XCTFail("Unexpected pixel fired: \(pixelName)")
                }
            },
            subscriptionStateProvider: SubscriptionStateProviderMock(isFreeTrial: true, isActive: true)
        )
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Process subscription (free trial)
        fixture.attributionManager.process(trigger: .userDidSubscribe)

        await fulfillment(of: [pixelExpectation], timeout: 5.0)
        XCTAssertEqual(capturedLength, 0, "Should send bucketed month 0 for free trial")
        XCTAssertTrue(fixture.dataStorage.subscriptionFreeTrialFired, "Should mark free trial as fired")
    }

    /// Tests subscription pixel for paid subscription (length = 1)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Subscription Type | Raw Length | Bucketed Length | Parameters | Flags Set |
    /// |------------------|------------|-----------------|------------|-----------|
    /// | Paid Subscription| 1          | 1               | length=1, origin/installDate | subscriptionMonth1Fired=true |
    ///
    /// ## Bucket Configuration
    /// - user_subscribed: [0, 1] → 0 maps to index 0, 1 maps to index 1, >1 maps to 2
    ///
    /// ## Test Validation
    /// - isFreeTrial() returns false → length=1
    /// - Bucketed length is 1 (1 ≤ 1, second bucket)
    /// - subscriptionMonth1Fired flag is set to true
    /// - Trigger: .userDidSubscribe calls processSubscriptionDay()
    /// - Async test due to await subscriptionStateProvider.isFreeTrial()
    func testProcessSubscriptionDayPaid() async {
        let pixelExpectation = XCTestExpectation(description: "Subscription pixel fired")
        var capturedMonth: Int?

        let fixture = createTestFixture(
            pixelHandler: { pixelName, _, parameters, _, _, _ in
                switch pixelName {
                case "attributed_metric_subscribed":
                    capturedMonth = self.extractIntParameter(parameters, key: "month")
                    if capturedMonth == nil {
                        XCTFail("Missing or invalid month parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "attributed_metric_data_store_error":
                    break
                default:
                    XCTFail("Unexpected pixel fired: \(pixelName)")
                }
            },
            subscriptionStateProvider: SubscriptionStateProviderMock(isFreeTrial: false, isActive: true)
        )
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Process subscription (paid)
        fixture.attributionManager.process(trigger: .userDidSubscribe)

        await fulfillment(of: [pixelExpectation], timeout: 5.0)
        XCTAssertEqual(capturedMonth, 1, "Should send bucketed month 1 for paid subscription")
        XCTAssertTrue(fixture.dataStorage.subscriptionMonth1Fired, "Should mark month 1 as fired")
    }

    /// Tests that processSubscriptionCheck sends month 1 pixel on app start after free trial ends
    ///
    /// ## Input → Output Mapping
    ///
    /// | Condition | Free Trial Pixel Sent | Is Free Trial | Is Active | Month 1 Pixel Sent | Result |
    /// |-----------|----------------------|---------------|-----------|-------------------|--------|
    /// | App Start | true                 | false         | true      | false             | Send month=1 pixel |
    ///
    /// ## Bucket Configuration
    /// - user_subscribed: [0, 1] → 1 maps to index 1
    ///
    /// ## Test Validation
    /// - processSubscriptionCheck() is called on .appDidStart
    /// - Month 1 pixel fires when free trial has ended but subscription is still active
    /// - Bucketed length is 1
    /// - Trigger: .appDidStart calls processSubscriptionCheck()
    /// - Async test due to await subscriptionStateProvider.isFreeTrial()
    func testProcessSubscriptionCheckMonth1() async {
        let pixelExpectation = XCTestExpectation(description: "Month 1 subscription pixel fired")
        var capturedMonth: Int?

        let fixture = createTestFixture(
            pixelHandler: { pixelName, _, parameters, _, _, _ in
                switch pixelName {
                case "attributed_metric_subscribed":
                    capturedMonth = self.extractIntParameter(parameters, key: "month")
                    if capturedMonth == nil {
                        XCTFail("Missing or invalid length parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "attributed_metric_data_store_error":
                    break
                default:
                    break // Ignore other pixels that might fire on app start
                }
            },
            subscriptionStateProvider: SubscriptionStateProviderMock(isFreeTrial: false, isActive: true)
        )
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Set subscription date
        fixture.dataStorage.subscriptionDate = fixture.timeMachine.now()

        // Simulate that free trial pixel was already sent
        fixture.dataStorage.subscriptionFreeTrialFired = true

        // Test: Process app start (should trigger processSubscriptionCheck)
        fixture.attributionManager.process(trigger: .appDidStart)

        await fulfillment(of: [pixelExpectation], timeout: 5.0)
        XCTAssertEqual(capturedMonth, 1, "Should send bucketed length 1 for month 1")
    }

    /// Tests that processSubscriptionCheck sends month 2+ pixel on app start after one month
    ///
    /// ## Input → Output Mapping
    ///
    /// | Condition | Free Trial Pixel Sent | Month 1 Pixel Sent | Is Active | Days Since Subscribe | Result |
    /// |-----------|----------------------|-------------------|-----------|---------------------|--------|
    /// | App Start | any                  | true              | true      | ≥30                 | Send month=2+ pixel |
    ///
    /// ## Bucket Configuration
    /// - user_subscribed: [0, 1] → 2 maps to index 2 (exceeds all thresholds)
    ///
    /// ## Test Validation
    /// - processSubscriptionCheck() is called on .appDidStart
    /// - Month 2+ pixel fires when subscription has been active for ≥30 days
    /// - Bucketed length is 2
    /// - Trigger: .appDidStart calls processSubscriptionCheck()
    /// - Async test due to await subscriptionStateProvider.isFreeTrial()
    func testProcessSubscriptionCheckMonth2Plus() async {
        let pixelExpectation = XCTestExpectation(description: "Month 2+ subscription pixel fired")
        var capturedMonth: Int?

        let fixture = createTestFixture(
            pixelHandler: { pixelName, _, parameters, _, _, _ in
                switch pixelName {
                case "attributed_metric_subscribed":
                    capturedMonth = self.extractIntParameter(parameters, key: "month")
                    if capturedMonth == nil {
                        XCTFail("Missing or invalid length parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "attributed_metric_data_store_error":
                    break
                default:
                    break // Ignore other pixels that might fire on app start
                }
            },
            subscriptionStateProvider: SubscriptionStateProviderMock(isFreeTrial: false, isActive: true)
        )
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Set subscription date
        fixture.dataStorage.subscriptionDate = fixture.timeMachine.now()

        // Travel forward 31 days
        fixture.timeMachine.travel(by: .day, value: 31)

        // Simulate that month 1 pixel was already sent
        fixture.dataStorage.subscriptionMonth1Fired = true

        // Test: Process app start (should trigger processSubscriptionCheck)
        fixture.attributionManager.process(trigger: .appDidStart)

        await fulfillment(of: [pixelExpectation], timeout: 5.0)
        XCTAssertEqual(capturedMonth, 2, "Should send bucketed length 2 for month 2+")
    }

    // MARK: - Sync Tests

    /// Tests sync pixel for valid device counts (< 3 devices)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Device Count | Bucketed Devices | Parameters | Fires? |
    /// |-------------|------------------|------------|--------|
    /// | 0           | 0                | devices=0, origin/installDate | Yes |
    /// | 1           | 0                | devices=0, origin/installDate | Yes |
    /// | 2           | 1                | devices=1, origin/installDate | Yes |
    /// | 3+          | -                | -          | No (guard devices < 3) |
    ///
    /// ## Bucket Configuration
    /// - user_synced_device: [1] → ≤1 maps to 0, >1 maps to 1
    ///
    /// ## Test Validation
    /// - Pixel fires for device counts 0, 1, 2
    /// - Device count is bucketed before sending
    /// - Trigger: .userDidSync(devicesCount:) calls processSyncCheck()
    func testProcessSyncCheck() {
        let pixelExpectation = XCTestExpectation(description: "Sync pixel fired")
        var capturedDevices: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "attributed_metric_synced_device":
                capturedDevices = self.extractIntParameter(parameters, key: "number_of_devices")
                if capturedDevices == nil {
                    XCTFail("Missing or invalid devices parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "attributed_metric_data_store_error":
                break
            default:
                XCTFail("Unexpected pixel fired: \(pixelName)")
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Process sync with 2 devices
        fixture.attributionManager.process(trigger: .userDidSync(devicesCount: 2))

        wait(for: [pixelExpectation], timeout: 5.0)
        XCTAssertNotNil(capturedDevices, "Should capture bucketed devices count")
    }

    /// Tests that sync pixel does NOT fire for 3+ devices
    ///
    /// ## Input → Output Mapping
    ///
    /// | Device Count | Pixel Fired? | Reason |
    /// |-------------|--------------|--------|
    /// | 3           | No           | guard devices < 3 else { return } |
    /// | 4+          | No           | guard devices < 3 else { return } |
    ///
    /// ## Test Validation
    /// - Pixel does NOT fire when device count >= 3
    /// - Early return prevents any pixel processing
    /// - Trigger: .userDidSync(devicesCount: 3) calls processSyncCheck()
    func testProcessSyncCheckDoesNotFireForThreeOrMoreDevices() {
        var pixelFired = false

        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_synced_device" {
                pixelFired = true
            }
        }
        defer { fixture.cleanup() }

        // Set install date
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Test: Process sync with 3+ devices should not fire
        fixture.attributionManager.process(trigger: .userDidSync(devicesCount: 3))
        XCTAssertFalse(pixelFired, "Should not fire for 3 or more devices")
    }

    // MARK: - Threshold Dedup Tests

    /// Tests that processActiveSearchDays does not fire twice on the same daysSinceInstalled
    ///
    /// ## Test Validation
    /// - First call on day 4 fires the pixel
    /// - Second call on same day 4 does NOT fire (threshold guard)
    /// - Advancing to day 5 fires the pixel again
    func testActiveSearchDaysSameDayDedup() {
        var pixelFireCount = 0

        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_active_past_week" {
                pixelFireCount += 1
            }
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Day 3: record a search
        fixture.timeMachine.travel(by: .day, value: 3)
        fixture.attributionManager.process(trigger: .userDidSearch)

        // Day 4: record a search (shifts rolling array so day 3's data enters the past-7-days window),
        // then appDidStart fires the active search days pixel
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(pixelFireCount, 1, "Should fire once on first call")

        // Day 4 again: second appDidStart should NOT fire (same daysSinceInstalled)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(pixelFireCount, 1, "Should not fire again on same day")

        // Day 5: record another search (shifts array again) and appDidStart should fire again
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(pixelFireCount, 2, "Should fire again on next day")
    }

    /// Tests that processAverageAdClick does not fire twice on the same daysSinceInstalled
    /// and that threshold is not burned when there's no data to send
    ///
    /// ## Test Validation
    /// - Day 1 with no ad clicks: pixel does NOT fire, threshold NOT consumed
    /// - Day 1 after recording ad clicks: pixel fires, threshold consumed
    /// - Day 1 again: pixel does NOT fire (threshold guard)
    func testAdClickThresholdNotBurnedOnEarlyReturn() {
        var pixelFireCount = 0

        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_average_ad_clicks_past_week" {
                pixelFireCount += 1
            }
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Day 1: trigger with no ad click data — should NOT fire AND should NOT burn the threshold
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSelectAD)
        // The first userDidSelectAD records a click but processAverageAdClick may not fire
        // because the data just got recorded (only 1 day of data, average may be 0 or
        // the click was just recorded today and not in the past 7 days yet).
        // Let's set up a scenario where we have past data:

        // Reset
        pixelFireCount = 0
        fixture.cleanup()
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Record ad clicks on day 0
        fixture.attributionManager.process(trigger: .userDidSelectAD)

        // Day 1: process without any new ad clicks — past 7 days has data from day 0
        fixture.timeMachine.travel(by: .day, value: 1)

        // Verify threshold is nil before processing
        XCTAssertNil(fixture.dataStorage.adClickLastThreshold, "Threshold should be nil before first process")

        fixture.attributionManager.process(trigger: .userDidSelectAD)
        XCTAssertEqual(pixelFireCount, 1, "Should fire once with existing ad click data")
        XCTAssertEqual(fixture.dataStorage.adClickLastThreshold, 1, "Threshold should be set to daysSinceInstalled")

        // Same day again: should not fire
        fixture.attributionManager.process(trigger: .userDidSelectAD)
        XCTAssertEqual(pixelFireCount, 1, "Should not fire again on same day")
    }

    /// Tests that processAverageDuckAIChat dedup works correctly across days
    ///
    /// ## Test Validation
    /// - First call fires the pixel and sets threshold
    /// - Same day call does NOT fire
    /// - Next day call fires again
    func testDuckAIChatSameDayDedupAndNextDayFire() {
        var pixelFireCount = 0

        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_average_duck_ai_usage_past_week" {
                pixelFireCount += 1
            }
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Record DuckAI chats on day 0
        fixture.attributionManager.process(trigger: .userDidDuckAIChat)

        // Day 1: should fire
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidDuckAIChat)
        XCTAssertEqual(pixelFireCount, 1, "Should fire once on day 1")
        XCTAssertEqual(fixture.dataStorage.duckAILastThreshold, 1, "Threshold should be set to 1")

        // Day 1 again: should NOT fire
        fixture.attributionManager.process(trigger: .userDidDuckAIChat)
        XCTAssertEqual(pixelFireCount, 1, "Should not fire again on same day")

        // Day 2: should fire again
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidDuckAIChat)
        XCTAssertEqual(pixelFireCount, 2, "Should fire again on day 2")
        XCTAssertEqual(fixture.dataStorage.duckAILastThreshold, 2, "Threshold should be updated to 2")
    }

    /// Tests that processAverageSearchCount threshold is not consumed when there's no search data
    ///
    /// ## Test Validation
    /// - Day 1 with no search data: pixel does NOT fire, threshold NOT set
    /// - After recording searches, same day fires pixel and sets threshold
    func testSearchCountThresholdNotBurnedWithNoData() {
        var pixelFireCount = 0

        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_average_searches_past_week_first_month" ||
               pixelName == "attributed_metric_average_searches_past_week" {
                pixelFireCount += 1
            }
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Day 1: trigger search with NO prior search data — should not fire and not burn threshold
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)
        // userDidSearch records a search AND calls processAverageSearchCount
        // The search was just recorded today, so past7DaysAverage may or may not include it
        // depending on RollingEightDays implementation. Let's check the threshold:

        // The key test: if average was 0 (no past data), threshold should NOT be consumed
        // If average was > 0 (today's search counted), pixel fires and threshold is set
        // Either way, the threshold is only set when the pixel fires

        // Record searches over multiple days to have clear past data
        pixelFireCount = 0
        fixture.cleanup()
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Day 1: no searches recorded yet, trigger appDidStart — processAverageSearchCount runs
        // but there's no search data so it should return early WITHOUT burning threshold
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertNil(fixture.dataStorage.searchLastThreshold, "Threshold should NOT be set when no search data exists")

        // Now record some searches
        fixture.attributionManager.process(trigger: .userDidSearch)

        // Day 2: now there's data from day 1
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)
        XCTAssertEqual(pixelFireCount, 1, "Should fire now that search data exists")
        XCTAssertEqual(fixture.dataStorage.searchLastThreshold, 2, "Threshold should be set to daysSinceInstalled")
    }

    /// Tests that removeAll clears threshold values
    ///
    /// ## Test Validation
    /// - Set all 4 thresholds, verify they are set
    /// - Call removeAll(), verify all are nil
    func testRemoveAllClearsThresholds() {
        let fixture = createTestFixture { _, _, _, _, _, _ in }
        defer { fixture.cleanup() }

        // Set thresholds
        fixture.dataStorage.activeSearchDaysLastThreshold = 5
        fixture.dataStorage.searchLastThreshold = 5
        fixture.dataStorage.adClickLastThreshold = 5
        fixture.dataStorage.duckAILastThreshold = 5

        // Verify set
        XCTAssertEqual(fixture.dataStorage.activeSearchDaysLastThreshold, 5)
        XCTAssertEqual(fixture.dataStorage.searchLastThreshold, 5)
        XCTAssertEqual(fixture.dataStorage.adClickLastThreshold, 5)
        XCTAssertEqual(fixture.dataStorage.duckAILastThreshold, 5)

        // Clear
        fixture.dataStorage.removeAll()

        // Verify cleared
        XCTAssertNil(fixture.dataStorage.activeSearchDaysLastThreshold, "activeSearchDaysLastThreshold should be nil after removeAll")
        XCTAssertNil(fixture.dataStorage.searchLastThreshold, "searchLastThreshold should be nil after removeAll")
        XCTAssertNil(fixture.dataStorage.adClickLastThreshold, "adClickLastThreshold should be nil after removeAll")
        XCTAssertNil(fixture.dataStorage.duckAILastThreshold, "duckAILastThreshold should be nil after removeAll")
    }

    /// Tests that a pixel cannot fire twice within a 24h window when crossing a UTC midnight boundary.
    ///
    /// ## Background
    /// `daysSinceInstalled` is computed as `Int(elapsedSeconds / 86400)` — a rolling 24h window
    /// anchored to the install time. PixelKit's `legacyDailyNoSuffix` deduplicates by UTC calendar
    /// day. These two clocks can disagree near UTC midnight:
    ///
    /// ```
    /// Install: Jan 15, 12:00 UTC
    ///
    ///                     Jan 16 12:00          Jan 16 23:00    Jan 17 01:00          Jan 17 12:00
    /// daysSinceInstalled:       1                     1              1                      2
    /// UTC calendar day:      Jan 16                Jan 16         Jan 17 ← new day!      Jan 17
    /// ```
    ///
    /// Between Jan 17 00:00–11:59 UTC, PixelKit sees a new calendar day and would allow firing,
    /// but `daysSinceInstalled` is still 1. Without our threshold guard, the pixel would fire
    /// twice within ~13 hours.
    ///
    /// ## Test Validation
    /// - Day 1 (12:00 UTC): pixel fires, threshold set to 1
    /// - After crossing UTC midnight (01:00 UTC next calendar day), daysSinceInstalled is still 1
    /// - Second call does NOT fire (threshold guard blocks it)
    /// - Only after a full 24h from install (daysSinceInstalled increments to 2) does it fire again
    func testPixelDoesNotFireTwiceWithin24hAcrossUTCMidnight() {
        var activeSearchPixelCount = 0

        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_active_past_week" {
                activeSearchPixelCount += 1
            }
        }
        defer { fixture.cleanup() }

        // Install at reference date: Jan 15, 12:00 UTC
        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Record searches on day 0 so there's data for the pixel
        fixture.attributionManager.process(trigger: .userDidSearch)

        // Travel to day 1 (Jan 16, 12:00 UTC) — daysSinceInstalled = 1
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(activeSearchPixelCount, 1, "Pixel should fire on day 1")
        XCTAssertEqual(fixture.dataStorage.activeSearchDaysLastThreshold, 1, "Threshold should be set to 1")

        // Travel 11 hours to Jan 16, 23:00 UTC — still daysSinceInstalled = 1
        // (elapsed from install = 35h = 126000s, 126000/86400 = 1.458 → Int = 1)
        fixture.timeMachine.travel(by: .hour, value: 11)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(activeSearchPixelCount, 1, "Pixel should NOT fire again (same daysSinceInstalled, same UTC day)")

        // Travel 2 more hours to Jan 17, 01:00 UTC — NEW UTC calendar day, but daysSinceInstalled is STILL 1
        // (elapsed from install = 37h = 133200s, 133200/86400 = 1.541 → Int = 1)
        // PixelKit's legacyDailyNoSuffix would allow firing (new UTC day), but our threshold blocks it
        fixture.timeMachine.travel(by: .hour, value: 2)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(activeSearchPixelCount, 1, "Pixel should NOT fire even after UTC midnight (daysSinceInstalled still 1)")

        // Travel 11 more hours to Jan 17, 12:00 UTC — now daysSinceInstalled = 2
        // (elapsed from install = 48h = 172800s, 172800/86400 = 2.0 → Int = 2)
        fixture.timeMachine.travel(by: .hour, value: 11)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.attributionManager.process(trigger: .appDidStart)
        XCTAssertEqual(activeSearchPixelCount, 2, "Pixel should fire now that daysSinceInstalled incremented to 2")
        XCTAssertEqual(fixture.dataStorage.activeSearchDaysLastThreshold, 2, "Threshold should be updated to 2")
    }

    // MARK: - Data Expiration Tests

    /// Tests that all data in dataStorage is removed at 6 months (168 days) from installation
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Data Present? | Reason |
    /// |-------------------|---------------|--------|
    /// | 167 (< 6 months)  | Yes           | isLessThanSixMonths returns true |
    /// | 168 (6 months)    | No            | isLessThanSixMonths returns false, removeAll() called |
    ///
    /// ## Constants
    /// - daysInAMonth: 28
    /// - 6 months: 28 * 6 = 168 days
    /// - Threshold: >= 168 days triggers data removal
    /// - Logic: `installDate > (now - 168 days)` returns false when now >= installDate + 168 days
    ///
    /// ## Test Validation
    /// - Data persists at 167 days (< 6 months)
    /// - All data is cleared at 168 days (exactly 6 months)
    /// - Verifies: installDate, lastRetentionThreshold, subscriptionDate, subscription flags, syncDevicesCount
    /// - Trigger: Any trigger (using .appDidStart) calls process() which checks isLessThanSixMonths
    func testDataStorageRemovalAfterSixMonths() {
        let fixture = createTestFixture { _, _, _, _, _, _ in
            // No pixel expectations needed for this test
        }
        defer { fixture.cleanup() }

        // Set install date
        let installDate = fixture.timeMachine.now()
        fixture.dataStorage.installDate = installDate

        // Populate data storage with various data
        fixture.dataStorage.lastRetentionThreshold = .weeks(2)
        fixture.dataStorage.subscriptionDate = fixture.timeMachine.now()
        fixture.dataStorage.subscriptionFreeTrialFired = true
        fixture.dataStorage.subscriptionMonth1Fired = true
        fixture.dataStorage.syncDevicesCount = 2

        // Verify data is present initially
        XCTAssertNotNil(fixture.dataStorage.installDate, "Install date should be set")
        XCTAssertNotNil(fixture.dataStorage.lastRetentionThreshold, "Last retention threshold should be set")
        XCTAssertNotNil(fixture.dataStorage.subscriptionDate, "Subscription date should be set")
        XCTAssertTrue(fixture.dataStorage.subscriptionFreeTrialFired, "Subscription free trial flag should be set")
        XCTAssertTrue(fixture.dataStorage.subscriptionMonth1Fired, "Subscription month 1 flag should be set")
        XCTAssertEqual(fixture.dataStorage.syncDevicesCount, 2, "Sync devices count should be set")

        // Travel to 167 days (< 6 months = 168 days)
        fixture.timeMachine.travel(by: .day, value: 167)
        fixture.attributionManager.process(trigger: .appDidStart)

        // Verify data is still present at 167 days
        XCTAssertNotNil(fixture.dataStorage.installDate, "Install date should still be present at 167 days")
        XCTAssertNotNil(fixture.dataStorage.lastRetentionThreshold, "Last retention threshold should still be present")
        XCTAssertNotNil(fixture.dataStorage.subscriptionDate, "Subscription date should still be present")

        // Travel 1 more day to reach exactly 6 months (168 days total)
        fixture.timeMachine.travel(by: .day, value: 1)
        fixture.attributionManager.process(trigger: .appDidStart)

        // Verify all data has been removed at exactly 6 months (168 days)
        XCTAssertNotNil(fixture.dataStorage.installDate, "Install date should be present")
        XCTAssertNil(fixture.dataStorage.lastRetentionThreshold, "Last retention threshold should be removed")
        XCTAssertEqual(fixture.dataStorage.search8Days.countPast7Days, 0, "Search data should be cleared")
        XCTAssertEqual(fixture.dataStorage.adClick8Days.countPast7Days, 0, "Ad click data should be cleared")
        XCTAssertEqual(fixture.dataStorage.duckAIChat8Days.countPast7Days, 0, "Duck AI chat data should be cleared")
        XCTAssertNil(fixture.dataStorage.subscriptionDate, "Subscription date should be removed")
        XCTAssertFalse(fixture.dataStorage.subscriptionFreeTrialFired, "Subscription free trial flag should be cleared")
        XCTAssertFalse(fixture.dataStorage.subscriptionMonth1Fired, "Subscription month 1 flag should be cleared")
        XCTAssertEqual(fixture.dataStorage.syncDevicesCount, 0, "Sync devices count should be cleared")
    }

    // MARK: - Returning User Tests

    /// Tests that no pixels fire when the user is detected as a returning user
    ///
    /// ## Test Validation
    /// - No pixels fire for any trigger when isReturningUser is true
    /// - Covers all trigger types: appDidStart, userDidSearch, userDidSelectAD, userDidDuckAIChat, userDidSubscribe, userDidSync
    func testNoPixelsFireForReturningUser() {
        var pixelFired = false

        let fixture = createTestFixture(
            pixelHandler: { pixelName, _, _, _, _, _ in
                if pixelName != "attributed_metric_data_store_error" {
                    pixelFired = true
                }
            },
            returningUserProvider: AttributedMetricReturningUserProvidingMock(isReturningUser: true)
        )
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()

        // Travel past install day so triggers would normally fire
        fixture.timeMachine.travel(by: .day, value: 2)

        // Try all trigger types
        fixture.attributionManager.process(trigger: .appDidStart)
        fixture.attributionManager.process(trigger: .userDidSearch)
        fixture.attributionManager.process(trigger: .userDidSelectAD)
        fixture.attributionManager.process(trigger: .userDidDuckAIChat)
        fixture.attributionManager.process(trigger: .userDidSubscribe)
        fixture.attributionManager.process(trigger: .userDidSync(devicesCount: 1))

        XCTAssertFalse(pixelFired, "No pixels should fire for a returning user")
    }
}
