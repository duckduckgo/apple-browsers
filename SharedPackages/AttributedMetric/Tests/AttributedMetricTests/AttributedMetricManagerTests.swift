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

final class AttributedMetricManagerTests: XCTestCase {

    func testDisabledFeatureFlag() {

    }

    func testRetentionPixel() {

        // Expectation
        let retention1Expectation = XCTestExpectation(description: "Retention 1 pixel fired")

        // Setup

        let suiteName = "testing_\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            source: "TESTS",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            defaults: userDefaults
        ) { pixelName, _, parameters, _, _, _ in
            print("Pixel fired: \(pixelName)")

            switch pixelName {
            case "m_mac_user_retention_week":
                guard let countString = parameters["count"] else {
                    XCTFail("Missing count parameter for pixel: \(pixelName)")
                    return
                }
//                let count = Int()
//                if
            default:
                XCTFail("Unknown pixel fired: \(pixelName)")
            }
        }

        let errorhandler = AttributedMetricErrorHandler(pixelKit: pixelKit)
        let dataStorage = AttributedMetricDataStorage(userDefaults: userDefaults, errorHandler: errorhandler)
        let featureFlagger: any FeatureFlagger = MockFeatureFlagger(featuresStub:
                                                                        [AttributedMetric.AttributedMetricFeatureFlags.behaviorMetricsEnabled.rawValue: true]) // override FF
        let originProvider: AttributedMetricOriginProvider = AttributedMetricOriginProviderMock()
        let attributedMetricDefaultBrowserProvidingMock = AttributedMetricDefaultBrowserProvidingMock()
        let attributionManager = AttributedMetricManager(pixelKit: pixelKit,
                                                     dataStoring: dataStorage,
                                                     featureFlagger: featureFlagger,
                                                     originProvider: originProvider,
                                                     defaultBrowserProviding: attributedMetricDefaultBrowserProvidingMock)

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

        // 0 days from installation
        attributionManager.process(trigger: .appDidStart)
        // Expectation
        // None, the install date is now, no pixels fired

        // 1 day from installation
        dataStorage.installDate = Date().addingTimeInterval(-.days(1))
        attributionManager.process(trigger: .appDidStart)
        // Expect pixel

        // Cleanup
        dataStorage.removeAll()
        userDefaults.removeSuite(named: suiteName)
    }
}
