//
//  AuthV2WideEventTests.swift
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
import PixelKit
@testable import Subscription

final class AuthV2WideEventTests: XCTestCase {

    // MARK: - AuthV2TokenRefreshWideEventData Tests

    func testPixelParameters_withMinimalData() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let eventData = AuthV2TokenRefreshWideEventData(
            contextData: contextData
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then
        XCTAssertNil(parameters["feature.data.ext.failing_step"])
        XCTAssertNil(parameters["feature.data.ext.application_state"])
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])
        XCTAssertNil(parameters["feature.data.ext.fetch_jwks_latency_ms_bucketed"])
    }

    func testPixelParameters_withFailingStep() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let eventData = AuthV2TokenRefreshWideEventData(
            failingStep: .refreshAccessToken,
            contextData: contextData
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then
        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "refresh_access_token")
    }

    func testPixelParameters_withAllFailingSteps() {
        let contextData = WideEventContextData(name: "test-context")

        for failingStep in AuthV2TokenRefreshWideEventData.FailingStep.allCases {
            // Given
            let eventData = AuthV2TokenRefreshWideEventData(
                failingStep: failingStep,
                contextData: contextData
            )

            // When
            let parameters = eventData.pixelParameters()

            // Then
            XCTAssertEqual(parameters["feature.data.ext.failing_step"], failingStep.rawValue)
        }
    }

    func testPixelParameters_withRefreshTokenDuration_bucketing() {
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()

        // Test each bucket threshold
        let testCases: [(milliseconds: Int, expectedBucket: String)] = [
            (500, "1000"),          // 0-1000ms → 1000
            (999, "1000"),          // 0-1000ms → 1000
            (1000, "5000"),         // 1000-5000ms → 5000
            (3000, "5000"),         // 1000-5000ms → 5000
            (5000, "10000"),        // 5000-10000ms → 10000
            (7500, "10000"),        // 5000-10000ms → 10000
            (10000, "30000"),       // 10000-30000ms → 30000
            (20000, "30000"),       // 10000-30000ms → 30000
            (30000, "60000"),       // 30000-60000ms → 60000
            (45000, "60000"),       // 30000-60000ms → 60000
            (60000, "300000"),      // 60000-300000ms → 300000
            (150000, "300000"),     // 60000-300000ms → 300000
            (300000, "600000"),     // 300000+ms → 600000
            (500000, "600000")      // 300000+ms → 600000
        ]

        for (milliseconds, expectedBucket) in testCases {
            // Given
            let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
            let endDate = baseDate.addingTimeInterval(TimeInterval(milliseconds) / 1000.0)
            eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: baseDate, end: endDate)

            // When
            let parameters = eventData.pixelParameters()

            // Then
            XCTAssertEqual(
                parameters["feature.data.ext.refresh_token_latency_ms_bucketed"],
                expectedBucket,
                "Expected bucket \(expectedBucket) for \(milliseconds)ms"
            )
        }
    }

    func testPixelParameters_withFetchJWKSDuration_bucketing() {
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()

        // Test a few key buckets for fetchJWKSDuration
        let testCases: [(milliseconds: Int, expectedBucket: String)] = [
            (100, "1000"),          // 0-1000ms → 1000
            (2000, "5000"),         // 1000-5000ms → 5000
            (8000, "10000"),        // 5000-10000ms → 10000
            (25000, "30000")        // 10000-30000ms → 30000
        ]

        for (milliseconds, expectedBucket) in testCases {
            // Given
            let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
            let endDate = baseDate.addingTimeInterval(TimeInterval(milliseconds) / 1000.0)
            eventData.fetchJWKSDuration = WideEvent.MeasuredInterval(start: baseDate, end: endDate)

            // When
            let parameters = eventData.pixelParameters()

            // Then
            XCTAssertEqual(
                parameters["feature.data.ext.fetch_jwks_latency_ms_bucketed"],
                expectedBucket,
                "Expected bucket \(expectedBucket) for \(milliseconds)ms"
            )
        }
    }

    func testPixelParameters_withIncompleteInterval() {
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()

        let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: baseDate, end: nil)
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])

        // Test with only end date
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: nil, end: baseDate)
        parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])

        // Test with no dates
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: nil, end: nil)
        parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])
    }

    func testPixelParameters_withAllParametersSet() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()
        let eventData = AuthV2TokenRefreshWideEventData(
            failingStep: .verifyingAccessToken,
            contextData: contextData
        )

        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(
            start: baseDate,
            end: baseDate.addingTimeInterval(2.5) // 2500ms → bucket 5000
        )

        eventData.fetchJWKSDuration = WideEvent.MeasuredInterval(
            start: baseDate,
            end: baseDate.addingTimeInterval(0.5) // 500ms → bucket 1000
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then
        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "verify_access_token")
        XCTAssertEqual(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"], "5000")
        XCTAssertEqual(parameters["feature.data.ext.fetch_jwks_latency_ms_bucketed"], "1000")
    }

    func testPixelParameters_withNegativeInterval() {
        // Given - end date before start date
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()
        let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(
            start: baseDate,
            end: baseDate.addingTimeInterval(-5.0) // Negative interval
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then - should be bucketed to 1000 (max(0, negative) = 0, which falls in 0-1000 range)
        XCTAssertEqual(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"], "1000")
    }
}
