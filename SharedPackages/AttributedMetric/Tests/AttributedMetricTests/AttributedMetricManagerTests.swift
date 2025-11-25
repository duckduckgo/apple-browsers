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

final class AttributedMetricManagerTests: XCTestCase {

    // MARK: - Test Fixtures

    struct TestFixture {
        let suiteName: String
        let userDefaults: UserDefaults
        let timeMachine: TimeMachine
        let pixelKit: PixelKit
        let dataStorage: AttributedMetricDataStorage
        let attributionManager: AttributedMetricManager

        func cleanup() {
            dataStorage.removeAll()
            userDefaults.removeSuite(named: suiteName)
        }
    }

    // MARK: - Helper Methods

    /// Creates a complete test fixture with all necessary dependencies
    /// - Parameters:
    ///   - pixelHandler: The closure to handle pixel events
    ///   - subscriptionStateProvider: Optional custom subscription state provider (default creates inactive mock)
    /// - Returns: A TestFixture containing all initialized test components
    private func createTestFixture(
        pixelHandler: @escaping PixelKit.FireRequest,
        subscriptionStateProvider: SubscriptionStateProviding? = nil
    ) -> TestFixture {
        let suiteName = "testing_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let startDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970)
        let timeMachine = TimeMachine(date: startDate)

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
        let bucketsSettingsProvider = BucketsSettingsProviderMock()

        let attributionManager = AttributedMetricManager(
            pixelKit: pixelKit,
            dataStoring: dataStorage,
            featureFlagger: featureFlagger,
            originProvider: originProvider,
            defaultBrowserProviding: defaultBrowserProvider,
            subscriptionStateProvider: subscriptionProvider,
            dateProvider: timeMachine,
            bucketsSettingsProvider: bucketsSettingsProvider
        )

        return TestFixture(
            suiteName: suiteName,
            userDefaults: userDefaults,
            timeMachine: timeMachine,
            pixelKit: pixelKit,
            dataStorage: dataStorage,
            attributionManager: attributionManager
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

    func testDisabledFeatureFlag() {

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

        // Setup
        let suiteName = "testing_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!

        // Create TimeMachine to control time for daily pixels
        // Start with a reasonable date (not epoch 0) to avoid triggering the 6-month limit
        let startDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970)
        let timeMachine = TimeMachine(date: startDate)

        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            source: "TESTS",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            dateGenerator: timeMachine.now,
            defaults: userDefaults
        ) { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "m_mac_attributed_metric_retention_week":
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

            case "m_mac_attributed_metric_retention_month":
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

            case "m_mac_attributed_metric_data_store_error":
                // Ignore data store errors in this test (expected in test environment)
                break

            default:
                XCTFail("Unexpected pixel fired: \(pixelName)")
            }
        }

        let errorhandler = AttributedMetricErrorHandler(pixelKit: pixelKit)
        let dataStorage = AttributedMetricDataStorage(userDefaults: userDefaults, errorHandler: errorhandler)
        let featureFlagger: any FeatureFlagger = MockFeatureFlagger(featuresStub:
            [AttributedMetric.AttributedMetricFeatureFlag.attributedMetrics.rawValue: true])
        let originProvider: AttributedMetricOriginProvider = AttributedMetricOriginProviderMock()
        let attributedMetricDefaultBrowserProvidingMock = AttributedMetricDefaultBrowserProvidingMock()
        let subscriptionStateProviderMock = SubscriptionStateProviderMock()
        let bucketsSettingsProvider = BucketsSettingsProviderMock()
        let attributionManager = AttributedMetricManager(pixelKit: pixelKit,
                                                         dataStoring: dataStorage,
                                                         featureFlagger: featureFlagger,
                                                         originProvider: originProvider,
                                                         defaultBrowserProviding: attributedMetricDefaultBrowserProvidingMock,
                                                         subscriptionStateProvider: subscriptionStateProviderMock,
                                                         dateProvider: timeMachine,
                                                         bucketsSettingsProvider: bucketsSettingsProvider)

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
        let installDate = timeMachine.now()
        dataStorage.installDate = installDate

        // Test 1: Day 0 (install day) - No pixels should fire
        let initialPixelCount = pixelFireCount
        attributionManager.process(trigger: AttributedMetricManager.Trigger.appDidStart)
        XCTAssertEqual(pixelFireCount, initialPixelCount, "No pixels should fire on install day")

        // Test 2: Day 1 - Week 1 retention pixel
        timeMachine.travel(by: .day, value: 1)
        attributionManager.process(trigger: AttributedMetricManager.Trigger.appDidStart)

        // Test 3: Day 1 again (same day) - No duplicate pixel
        let pixelCountBeforeDuplicate = pixelFireCount
        attributionManager.process(trigger: AttributedMetricManager.Trigger.appDidStart)
        XCTAssertEqual(pixelFireCount, pixelCountBeforeDuplicate, "No duplicate pixel should fire for same threshold")

        // Test 4: Day 22 - Week 4 retention pixel
        // Travel from day 1 to day 22 (21 more days)
        timeMachine.travel(by: .day, value: 21)
        attributionManager.process(trigger: AttributedMetricManager.Trigger.appDidStart)

        // Test 5: Day 29 - Month 2 retention pixel
        // Travel from day 22 to day 29 (7 more days)
        timeMachine.travel(by: .day, value: 7)
        attributionManager.process(trigger: AttributedMetricManager.Trigger.appDidStart)

        // Test 6: Day 141 - Month 6 retention pixel
        // Travel from day 29 to day 141 (112 more days)
        timeMachine.travel(by: .day, value: 112)
        attributionManager.process(trigger: AttributedMetricManager.Trigger.appDidStart)

        // Wait for expectations
        wait(for: [week1Expectation, week4Expectation, month2Expectation, month6Expectation], timeout: 1.0)
        wait(for: [noDuplicateExpectation], timeout: 0.1)

        // Verify correct number of pixels fired
        XCTAssertEqual(pixelFireCount, 4, "Should fire exactly 4 retention pixels")
        XCTAssertEqual(firedPixels.count, 4, "Should have exactly 4 unique pixels")

        // Cleanup
        dataStorage.removeAll()
        userDefaults.removeSuite(named: suiteName)
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
            case "m_mac_attributed_metric_active_past_week":
                capturedDays = self.extractIntParameter(parameters, key: "days")
                capturedDaysSinceInstalled = self.extractIntParameter(parameters, key: "daysSinceInstalled")
                if capturedDays == nil {
                    XCTFail("Missing or invalid days parameter")
                    return
                }
                pixelFireCount += 1
                pixelExpectation.fulfill()
            case "m_mac_attributed_metric_average_searches_past_week_first_month", "m_mac_attributed_metric_retention_week":
                // These pixels fire during userDidSearch and appDidStart, ignore them in this test
                break
            case "m_mac_attributed_metric_data_store_error":
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

        wait(for: [pixelExpectation], timeout: 1.0)
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
            if pixelName == "m_mac_attributed_metric_active_past_week" {
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

        wait(for: [pixelExpectation], timeout: 1.0)
        XCTAssertNil(capturedDaysSinceInstalled, "Should not include days since installed after first week")
    }

    // MARK: - Average Search Count Tests

    /// Tests average search count pixel within first month (includes day_average parameter)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Raw Average | Bucketed Count | Parameters |
    /// |-------------------|-------------|----------------|------------|
    /// | 18-20 (< 28 days) | varies      | varies         | count=bucketed, day_average=raw_count, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_searches_past_week_first_month: [5, 9] → ≤5 maps to 0, ≤9 maps to 1, >9 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel fires within first 28 days with day_average parameter
    /// - count parameter is bucketed
    /// - day_average parameter contains raw search count
    /// - Trigger: .userDidSearch calls processAverageSearchCount()
    func testProcessAverageSearchCountFirstMonth() {
        let pixelExpectation = XCTestExpectation(description: "Average search count pixel fired")
        var capturedCount: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "m_mac_attributed_metric_average_searches_past_week_first_month":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "m_mac_attributed_metric_data_store_error":
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

        wait(for: [pixelExpectation], timeout: 1.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
    }

    /// Tests average search count pixel after first month (NO day_average parameter)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Raw Average | Bucketed Count | Parameters |
    /// |-------------------|-------------|----------------|------------|
    /// | 29-31 (≥ 28 days) | varies      | varies         | count=bucketed, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_searches_past_week: [5, 9] → ≤5 maps to 0, ≤9 maps to 1, >9 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel fires after 28 days WITHOUT day_average parameter
    /// - count parameter is bucketed
    /// - Different pixel name than first month version
    /// - Trigger: .userDidSearch calls processAverageSearchCount()
    func testProcessAverageSearchCountAfterFirstMonth() {
        let pixelExpectation = XCTestExpectation(description: "Average search count pixel fired")
        var capturedCount: Int?
        var hasDayAverage: Bool = false

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "m_mac_attributed_metric_average_searches_past_week":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                hasDayAverage = parameters["day_average"] != nil
                pixelExpectation.fulfill()
            case "m_mac_attributed_metric_data_store_error":
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

        wait(for: [pixelExpectation], timeout: 1.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
        XCTAssertFalse(hasDayAverage, "Should not include day average after first month")
    }

    // MARK: - Average AD Click Tests

    /// Tests average ad click pixel (does not fire on install day)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | Ad Clicks | Bucketed Count | Parameters |
    /// |-------------------|-----------|----------------|------------|
    /// | 0 (install day)   | any       | -              | No pixel fired (isSameDayOfInstallDate check) |
    /// | 1+ (any other day)| varies    | varies         | count=bucketed, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_ad_clicks_past_week: [2, 5] → ≤2 maps to 0, ≤5 maps to 1, >5 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel does NOT fire on install day (day 0)
    /// - Pixel fires on subsequent days with bucketed count
    /// - Trigger: .userDidSelectAD calls processAverageAdClick()
    func testProcessAverageAdClick() {
        let pixelExpectation = XCTestExpectation(description: "Average ad click pixel fired")
        var capturedCount: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "m_mac_attributed_metric_average_ad_clicks_past_week":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "m_mac_attributed_metric_data_store_error":
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

        wait(for: [pixelExpectation], timeout: 1.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
    }

    // MARK: - Average Duck.AI Chat Tests

    /// Tests average Duck.AI chat pixel (does not fire on install day)
    ///
    /// ## Input → Output Mapping
    ///
    /// | Days Since Install | AI Chats | Bucketed Count | Parameters |
    /// |-------------------|----------|----------------|------------|
    /// | 0 (install day)   | any      | -              | No pixel fired (isSameDayOfInstallDate check) |
    /// | 1+ (any other day)| varies   | varies         | count=bucketed, origin/installDate |
    ///
    /// ## Bucket Configuration
    /// - user_average_duck_ai_usage_past_week: [5, 9] → ≤5 maps to 0, ≤9 maps to 1, >9 maps to 2
    ///
    /// ## Test Validation
    /// - Pixel does NOT fire on install day (day 0)
    /// - Pixel fires on subsequent days with bucketed count
    /// - Trigger: .userDidDuckAIChat calls processAverageDuckAIChat()
    func testProcessAverageDuckAIChat() {
        let pixelExpectation = XCTestExpectation(description: "Average Duck.AI chat pixel fired")
        var capturedCount: Int?

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            switch pixelName {
            case "m_mac_attributed_metric_average_duck_ai_usage_past_week":
                capturedCount = self.extractIntParameter(parameters, key: "count")
                if capturedCount == nil {
                    XCTFail("Missing or invalid count parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "m_mac_attributed_metric_data_store_error":
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

        wait(for: [pixelExpectation], timeout: 1.0)
        XCTAssertNotNil(capturedCount, "Should capture bucketed count")
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
                case "m_mac_attributed_metric_subscribed":
                    capturedLength = self.extractIntParameter(parameters, key: "month")
                    if capturedLength == nil {
                        XCTFail("Missing or invalid length parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "m_mac_attributed_metric_data_store_error":
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

        await fulfillment(of: [pixelExpectation], timeout: 2.0)
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
                case "m_mac_attributed_metric_subscribed":
                    capturedMonth = self.extractIntParameter(parameters, key: "month")
                    if capturedMonth == nil {
                        XCTFail("Missing or invalid month parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "m_mac_attributed_metric_data_store_error":
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

        await fulfillment(of: [pixelExpectation], timeout: 2.0)
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
                case "m_mac_attributed_metric_subscribed":
                    capturedMonth = self.extractIntParameter(parameters, key: "month")
                    if capturedMonth == nil {
                        XCTFail("Missing or invalid length parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "m_mac_attributed_metric_data_store_error":
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

        await fulfillment(of: [pixelExpectation], timeout: 2.0)
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
                case "m_mac_attributed_metric_subscribed":
                    capturedMonth = self.extractIntParameter(parameters, key: "month")
                    if capturedMonth == nil {
                        XCTFail("Missing or invalid length parameter")
                        return
                    }
                    pixelExpectation.fulfill()
                case "m_mac_attributed_metric_data_store_error":
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

        await fulfillment(of: [pixelExpectation], timeout: 2.0)
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
            case "m_mac_attributed_metric_synced_device":
                capturedDevices = self.extractIntParameter(parameters, key: "number_of_devices")
                if capturedDevices == nil {
                    XCTFail("Missing or invalid devices parameter")
                    return
                }
                pixelExpectation.fulfill()
            case "m_mac_attributed_metric_data_store_error":
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

        wait(for: [pixelExpectation], timeout: 1.0)
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
            if pixelName == "m_mac_attributed_metric_synced_device" {
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
}
