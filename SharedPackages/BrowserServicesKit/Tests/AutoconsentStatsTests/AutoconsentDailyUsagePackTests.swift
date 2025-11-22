//
//  AutoconsentDailyUsagePackTests.swift
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
@testable import AutoconsentStats

final class AutoconsentDailyUsagePackTests: XCTestCase {

    // MARK: - asDictionary Tests

    func testAsDictionaryReturnsCorrectKeys() {
        // Given
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 5,
            totalClicksMadeBlockingCookiePopUps: 10,
            totalTotalTimeSpentBlockingCookiePopUps: 100
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary.keys.count, 3)
        XCTAssertTrue(dictionary.keys.contains(AutoconsentDailyUsagePack.Constants.averageClicksBlockingCookiePopUp))
        XCTAssertTrue(dictionary.keys.contains(AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket))
        XCTAssertTrue(dictionary.keys.contains(AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket))
    }

    func testAsDictionaryWithZeroValues() {
        // Given
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 0,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.averageClicksBlockingCookiePopUp], "0")
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "0")
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "0s")
    }

    // MARK: - Average Clicks Tests

    func testAverageClicksWithZeroPopUps() {
        // Given
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 0,
            totalClicksMadeBlockingCookiePopUps: 100,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.averageClicksBlockingCookiePopUp], "0")
    }

    func testAverageClicksCalculation() {
        // Given
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 5,
            totalClicksMadeBlockingCookiePopUps: 15,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.averageClicksBlockingCookiePopUp], "3")
    }

    func testAverageClicksWithFractionalResult() {
        // Given
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 3,
            totalClicksMadeBlockingCookiePopUps: 10,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.averageClicksBlockingCookiePopUp], "3.333")
    }

    // MARK: - Cookie Pop-Ups Blocked Bucket Tests

    func testCookiePopUpsBlockedBucket_Zero() {
        // Given
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 0,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "0")
    }

    func testCookiePopUpsBlockedBucket_1To10() {
        let testCases = [1, 5, 10]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "1-10", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_11To50() {
        let testCases = [11, 30, 50]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "11-50", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_51To100() {
        let testCases = [51, 75, 100]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "51-100", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_101To150() {
        let testCases = [101, 125, 150]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "101-150", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_151To200() {
        let testCases = [151, 175, 200]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "151-200", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_201To250() {
        let testCases = [201, 225, 250]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "201-250", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_251To300() {
        let testCases = [251, 275, 300]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "251-300", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_301To500() {
        let testCases = [301, 400, 500]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "301-500", "Failed for value \(value)")
        }
    }

    func testCookiePopUpsBlockedBucket_500Plus() {
        let testCases = [501, 1000, 10000]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: Int64(value),
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: 0
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "500+", "Failed for value \(value)")
        }
    }

    // MARK: - Time Blocking Cookie Pop-Ups Bucket Tests

    func testTimeBlockingBucket_Zero() {
        // Given
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 0,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "0s")
    }

    func testTimeBlockingBucket_1To10Seconds() {
        let testCases: [TimeInterval] = [1, 5, 9.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "1-10s", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_11To60Seconds() {
        let testCases: [TimeInterval] = [10, 30, 59.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "10-60s", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_1To5Minutes() {
        let testCases: [TimeInterval] = [60, 150, 299.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "1-5min", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_6To10Minutes() {
        let testCases: [TimeInterval] = [300, 450, 599.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "5-10min", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_10To20Minutes() {
        let testCases: [TimeInterval] = [600, 900, 1199.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "10-20min", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_21To40Minutes() {
        let testCases: [TimeInterval] = [1200, 1800, 2399.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "20-40min", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_41To60Minutes() {
        let testCases: [TimeInterval] = [2400, 3000, 3599.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "40-60min", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_1To2Hours() {
        let testCases: [TimeInterval] = [3600, 5400, 7199.9]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "1-2hr", "Failed for value \(value)")
        }
    }

    func testTimeBlockingBucket_2HoursPlus() {
        let testCases: [TimeInterval] = [7200, 10000, 100000]
        for value in testCases {
            // Given
            let pack = AutoconsentDailyUsagePack(
                totalCookiePopUpsBlocked: 0,
                totalClicksMadeBlockingCookiePopUps: 0,
                totalTotalTimeSpentBlockingCookiePopUps: value
            )

            // When
            let dictionary = pack.asPixelParameters()

            // Then
            XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "2hr+", "Failed for value \(value)")
        }
    }

    // MARK: - Boundary Tests

    func testBoundaryBetween1To10And11To50PopUps() {
        // Test value 10 should be "1-10"
        let pack10 = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 10,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )
        XCTAssertEqual(pack10.asPixelParameters()[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "1-10")

        // Test value 11 should be "11-50"
        let pack11 = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 11,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )
        XCTAssertEqual(pack11.asPixelParameters()[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "11-50")
    }

    func testBoundaryBetweenTimeBuckets() {
        // Test 60 seconds (1 minute boundary)
        let pack60 = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 0,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 59.999
        )
        XCTAssertEqual(pack60.asPixelParameters()[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "10-60s")

        // Test 61 seconds
        let pack61 = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 0,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 60
        )
        XCTAssertEqual(pack61.asPixelParameters()[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "1-5min")
    }

    // MARK: - Integration Tests

    func testRealWorldScenario() {
        // Given - A realistic scenario
        let pack = AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: 75,
            totalClicksMadeBlockingCookiePopUps: 150,
            totalTotalTimeSpentBlockingCookiePopUps: 450 // 7.5 minutes
        )

        // When
        let dictionary = pack.asPixelParameters()

        // Then
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalCookiePopUpsBlockedBucket], "51-100")
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.averageClicksBlockingCookiePopUp], "2")
        XCTAssertEqual(dictionary[AutoconsentDailyUsagePack.Constants.totalTimeBlockingCookiePopUpsBucket], "5-10min")
    }
}
