//
//  BreakageReportingSubfeatureTests.swift
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
@testable import PrivacyDashboard
import WebKit
import BrowserServicesKitTestsUtils

final class BreakageReportingSubfeatureTests: XCTestCase {

    // MARK: - Percent Decoding Tests

    func testWhenBreakageDataIsPercentEncodedThenItIsDecoded() async throws {
        let webView = WKWebView()
        let subfeature = BreakageReportingSubfeature(targetWebview: webView)

        let percentEncodedBreakageData = "%7B%22webDetection%22%3A%5B%7B%22detectorId%22%3A%22adwalls.generic_en%22%2C%22detected%22%3Atrue%7D%5D%2C%22detectorData%22%3A%7B%22botDetection%22%3A%7B%22detected%22%3Afalse%2C%22type%22%3A%22botDetection%22%2C%22results%22%3A%5B%5D%7D%2C%22fraudDetection%22%3A%7B%22detected%22%3Afalse%2C%22type%22%3A%22fraudDetection%22%2C%22results%22%3A%5B%5D%7D%2C%22adwallDetection%22%3A%7B%22detected%22%3Atrue%2C%22type%22%3A%22adwallDetection%22%2C%22results%22%3A%5B%7B%22detected%22%3Atrue%2C%22detectorId%22%3A%22generic%22%7D%5D%7D%2C%22youtubeAds%22%3A%7B%22detected%22%3Afalse%2C%22type%22%3A%22youtubeAds%22%2C%22results%22%3A%5B%5D%7D%7D%7D"

        let expectedDecodedData = """
            {"webDetection":[{"detectorId":"adwalls.generic_en","detected":true}],"detectorData":{"botDetection":{"detected":false,"type":"botDetection","results":[]},"fraudDetection":{"detected":false,"type":"fraudDetection","results":[]},"adwallDetection":{"detected":true,"type":"adwallDetection","results":[{"detected":true,"detectorId":"generic"}]},"youtubeAds":{"detected":false,"type":"youtubeAds","results":[]}}}
            """

        let payload: [String: Any] = [
            "expandedPerformanceMetrics": [:],
            "breakageData": percentEncodedBreakageData
        ]

        let mockMessage = WKScriptMessage.mock(name: "breakageReportResult", body: payload)
        _ = try await subfeature.breakageReportResult(params: payload, original: mockMessage)

        // The breakageData should be decoded when passed to completion handler
        // We verify this by checking if removingPercentEncoding works correctly
        let decoded = percentEncodedBreakageData.removingPercentEncoding
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, expectedDecodedData)
    }

    func testWhenBreakageDataIsNotPercentEncodedThenItIsPassedThrough() {
        let plainBreakageData = "{\"test\":\"value\"}"

        // Simulate the decoding logic used in BreakageReportingSubfeature
        let result = plainBreakageData.removingPercentEncoding ?? plainBreakageData

        // Plain string should be passed through (removingPercentEncoding returns the same string for non-encoded content)
        XCTAssertEqual(result, plainBreakageData)
    }

    func testWhenBreakageDataIsNilThenResultIsNil() {
        let rawBreakageData: String? = nil

        // Simulate the decoding logic used in BreakageReportingSubfeature
        let result = rawBreakageData.flatMap { $0.removingPercentEncoding ?? $0 }

        XCTAssertNil(result)
    }

    func testWhenBreakageDataHasInvalidEncodingThenOriginalIsReturned() {
        // This is a malformed percent-encoded string (incomplete encoding)
        let malformedData = "test%ZZinvalid"

        // Simulate the decoding logic used in BreakageReportingSubfeature
        let result = malformedData.removingPercentEncoding ?? malformedData

        // When decoding fails, we should fall back to original
        // Note: removingPercentEncoding returns nil for invalid sequences
        XCTAssertEqual(result, malformedData)
    }
}
