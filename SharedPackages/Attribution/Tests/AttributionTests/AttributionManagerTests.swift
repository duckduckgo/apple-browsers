//
//  AttributionManagerTests.swift
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
@testable import Attribution
import PixelKit
import BrowserServicesKit

final class AttributionManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {

        super.tearDown()
    }

    private var userDefaults: UserDefaults {
        UserDefaults(suiteName: "testing_\(UUID().uuidString)")!
    }

    func testRetentionPixel() {

        // Setup PixelKit with callback to capture parameters
        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            defaults: userDefaults
        ) { pixelName, headers, parameters, _, _, _ in
//            print("DEBUG: FireRequest called #\(callCount + 1) for pixel: \(pixelName) with parameters: \(parameters)")
//            callCount += 1
//            if ddgErrorParams == nil {
//                ddgErrorParams = parameters
//            } else {
//                standardErrorParams = parameters
//            }
        }

        let dataStorage = AttributionDataStorage(userDefaults: userDefaults)
        let featureFlagger: any FeatureFlagger = MockFeatureFlagger()
        let originProvider: AttributionOriginProvider = AttributionOriginProviderMock()

//        var attributionManager = AttributionManager(pixelKit: pixelKit,
//                                                    dataStoring: dataStorage,
//                                                    featureFlagger: featureFlagger,
//                                                    originProvider: originProvider,
//                                                    defaultBrowserProviding: <#any AttributionDefaultBrowserProviding#>)

        // >>>
    }
}
