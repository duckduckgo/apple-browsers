//
//  RetentionTests.swift
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
@testable import AttributedMetric
import PixelKit
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import AttributedMetricTestsUtils
import PrivacyConfig

final class RetentionTests: XCTestCase {

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

    // Fixed reference date for deterministic time travel
    private static let referenceDate = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))!

    private func createTestFixture(
        pixelHandler: @escaping PixelKit.FireRequest,
        originProvider: AttributedMetricOriginProvider? = AttributedMetricOriginProviderMock(),
        defaultBrowserProvider: AttributedMetricDefaultBrowserProviding = AttributedMetricDefaultBrowserProvidingMock(),
        timeMachine: TimeMachine? = nil
    ) -> TestFixture {
        let suiteName = "testing_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let timeMachine = timeMachine ?? TimeMachine(date: Self.referenceDate)

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
        let subscriptionProvider = SubscriptionStateProviderMock()
        let settingsProvider = AttributedMetricSettingsProviderMock()

        let attributionManager = AttributedMetricManager(
            pixelKit: pixelKit,
            dataStoring: dataStorage,
            featureFlagger: featureFlagger,
            originProvider: originProvider,
            defaultBrowserProviding: defaultBrowserProvider,
            subscriptionStateProvider: subscriptionProvider,
            dateProvider: timeMachine,
            settingsProvider: settingsProvider
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

    func testProcessRetentionDoesNotFireWhenInstallDateMissing() {
        // When install date is missing, retention should not fire pixels.
        var didFire = false

        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_retention_week" || pixelName == "attributed_metric_retention_month" {
                didFire = true
            }
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = nil
        fixture.dataStorage.lastRetentionThreshold = nil
        fixture.attributionManager.processRetention()

        XCTAssertFalse(didFire, "Should not fire retention pixel without install date")
        XCTAssertNil(fixture.dataStorage.lastRetentionThreshold, "Should not set retention threshold without install date")
    }

    func testProcessRetentionDoesNotFireWhenThresholdUnchanged() {
        // When threshold is already stored, retention should avoid duplicate pixels.
        var didFire = false
        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_retention_week" || pixelName == "attributed_metric_retention_month" {
                didFire = true
            }
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()
        fixture.timeMachine.travel(by: .day, value: 1) // Week 1
        fixture.dataStorage.lastRetentionThreshold = .weeks(1)

        fixture.attributionManager.processRetention()

        XCTAssertFalse(didFire, "Should not fire when threshold is unchanged")
        XCTAssertEqual(fixture.dataStorage.lastRetentionThreshold, .weeks(1))
    }

    func testProcessRetentionFiresWeekPixelAndStoresThreshold() {
        // Week 1 should fire a week retention pixel and store the threshold.
        let expectation = XCTestExpectation(description: "Week retention pixel fired")
        var capturedCount: Int?
        var capturedDefaultBrowser: String?
        var capturedInstallDate: String?

        let fixture = createTestFixture(
            pixelHandler: { pixelName, _, parameters, _, _, _ in
                guard pixelName == "attributed_metric_retention_week" else { return }
                capturedCount = Int(parameters["count"] ?? "")
                capturedDefaultBrowser = parameters["default_browser"]
                capturedInstallDate = parameters["install_date"]
                expectation.fulfill()
            },
            defaultBrowserProvider: AttributedMetricDefaultBrowserProvidingMock(isDefaultBrowser: true)
        )
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()
        fixture.timeMachine.travel(by: .day, value: 1) // Week 1

        fixture.attributionManager.processRetention()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedCount, 0, "Week 1 should bucket to count 0")
        XCTAssertEqual(capturedDefaultBrowser, "true", "Should include default browser flag")
        XCTAssertNotNil(capturedInstallDate, "Should include install date when origin is not sent")
        XCTAssertEqual(fixture.dataStorage.lastRetentionThreshold, .weeks(1))
    }

    func testProcessRetentionFiresMonthPixelWithOrigin() {
        // Month 2 should fire a month retention pixel using origin instead of install date.
        let expectation = XCTestExpectation(description: "Month retention pixel fired")
        var capturedCount: Int?
        var capturedOrigin: String?
        var capturedInstallDate: String?

        let fixture = createTestFixture(
            pixelHandler: { pixelName, _, parameters, _, _, _ in
                guard pixelName == "attributed_metric_retention_month" else { return }
                capturedCount = Int(parameters["count"] ?? "")
                capturedOrigin = parameters["origin"]
                capturedInstallDate = parameters["install_date"]
                expectation.fulfill()
            },
            originProvider: AttributedMetricOriginProviderMock(origin: "paid")
        )
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()
        fixture.timeMachine.travel(by: .day, value: 29) // Month 2

        fixture.attributionManager.processRetention()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedCount, 0, "Month 2 should bucket to count 0")
        XCTAssertEqual(capturedOrigin, "paid", "Should include origin when it is in the send list")
        XCTAssertNil(capturedInstallDate, "Should not include install date when origin is sent")
        XCTAssertEqual(fixture.dataStorage.lastRetentionThreshold, .months(2))
    }

    func testProcessRetentionDoesNotFireSameWeekCountMoreThanOnce() {
        // Calling processRetention multiple times for the same week should not emit duplicates.
        var weekPixelCount = 0
        var counts: [Int] = []

        let fixture = createTestFixture { pixelName, _, parameters, _, _, _ in
            guard pixelName == "attributed_metric_retention_week" else { return }
            if let count = Int(parameters["count"] ?? "") {
                counts.append(count)
            }
            weekPixelCount += 1
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()
        fixture.timeMachine.travel(by: .day, value: 1) // Week 1

        fixture.attributionManager.processRetention()
        fixture.attributionManager.processRetention()
        fixture.attributionManager.processRetention()

        XCTAssertEqual(weekPixelCount, 1, "Should not fire duplicate week retention pixels for the same count")
        XCTAssertEqual(counts, [0], "Week 1 should bucket to count 0 only once")
    }

    func testProcessRetentionDoesNotFireWhenInstallDateIsNow() {
        // When threshold is already stored, retention should avoid duplicate pixels.
        var didFire = false
        let fixture = createTestFixture { pixelName, _, _, _, _, _ in
            if pixelName == "attributed_metric_retention_week" || pixelName == "attributed_metric_retention_month" {
                didFire = true
            }
        }
        defer { fixture.cleanup() }

        fixture.dataStorage.installDate = fixture.timeMachine.now()
        fixture.dataStorage.lastRetentionThreshold = nil

        fixture.attributionManager.processRetention()

        XCTAssertFalse(didFire, "Should not fire when threshold is unchanged")
        XCTAssertNil(fixture.dataStorage.lastRetentionThreshold)
    }
}
