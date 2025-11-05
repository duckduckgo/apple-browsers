//
//  PixelKitEventWithCustomPrefixTests.swift
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
@testable import PixelKit
import os.log

final class PixelKitEventWithCustomPrefixTests: XCTestCase {

    enum TestEvent: String, PixelKitEvent, PixelKitEventWithCustomPrefix {
        /// Both test events are the same but the macOS one adds the "mac" prefix, since prefixes aren't
        /// centrally managed anymore.
        case macEvent
        case iosEvent

        var name: String {
            return rawValue
        }

        var parameters: [String: String]? {
            nil
        }

        var frequency: PixelKit.Frequency {
            .dailyAndCount
        }

        var namePrefix: String {
            switch self {
            case .macEvent:
                return "m_mac_"
            case .iosEvent:
                return "m_"
            }
        }
    }

    struct PixelNameTest {
        let event: TestEvent
        let expectedName: String
    }

    /// Tests firing a sample V3 pixel and ensures the pixel name is correct
    ///
    func testFiringPixelWithCustomPrefix() {
        // Prepare tests
        let userDefaults = UserDefaults(suiteName: "testFiringASamplePixel-\(UUID().uuidString))")!
        let tests: [PixelKit.Source: PixelNameTest] = [
            .macDMG: .init(event: TestEvent.macEvent, expectedName: "m_mac_macEvent"),
            .macStore: .init(event: TestEvent.macEvent, expectedName: "m_mac_macEvent"),
            .iOS: .init(event: TestEvent.iosEvent, expectedName: "m_iosEvent_ios_phone"),
            .iPadOS: .init(event: TestEvent.iosEvent, expectedName: "m_iosEvent_ios_tablet"),
        ]

        // Test for each expectation
        for test in tests {
            let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")

            let pixelKit = PixelKit(dryRun: false,
                                    appVersion: "1.0.5",
                                    source: test.key.rawValue,
                                    defaultHeaders: [:],
                                    dailyPixelCalendar: nil,
                                    defaults: userDefaults) { firedPixelName, firedHeaders, parameters, _, _, _ in

                XCTAssertEqual(firedPixelName, test.value.expectedName)
                fireCallbackCalled.fulfill()
            }

            // Run test
            pixelKit.fire(test.value.event)

            wait(for: [fireCallbackCalled], timeout: 0.5)
        }
    }
}
