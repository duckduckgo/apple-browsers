//
//  SiteLoadingPerformanceSubfeatureTests.swift
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
@testable import PrivacyDashboard
import PixelKit
import WebKit
import BrowserServicesKitTestsUtils

final class SiteLoadingPerformanceSubfeatureTests: XCTestCase {

    private struct FiredPixel {
        let event: PixelKitEvent
        let frequency: PixelKit.Frequency
    }

    func testFeatureNameMatchesContentScopeScriptsFeature() {
        let subfeature = SiteLoadingPerformanceSubfeature()
        XCTAssertEqual(subfeature.featureName, "performanceMetrics")
    }

    func testWhenExpandedMetricsPayloadIsValidThenSiteLoadingPerformancePixelIsFiredWithSampleFrequency() async throws {
        var fired: [FiredPixel] = []
        let subfeature = SiteLoadingPerformanceSubfeature(
            samplePercentage: 20,
            pixelFire: { event, frequency in
                fired.append(FiredPixel(event: event, frequency: frequency))
            }
        )

        let payload: [String: Any] = [
            "metrics": [
                "firstContentfulPaint": 556.0,
                "timeToFirstByte": 235.0,
                "loadComplete": 1097.0,
                "transferSize": 12345.0,
                "decodedBodySize": 23456.0,
                "encodedBodySize": 8000.0,
                "totalResourcesSize": 50000.0,
                "resourceCount": 25,
                "redirectCount": 0,
                "domInteractive": 940.0,
                "domComplete": 1090.0,
                "domContentLoaded": 961.0
            ]
        ]
        let message = WKScriptMessage.mock(name: "expandedPerformanceMetricsResult", body: payload)

        _ = try await subfeature.expandedPerformanceMetricsResult(params: payload, original: message)

        XCTAssertEqual(fired.count, 1)
        let firedPixel = try XCTUnwrap(fired.first)
        XCTAssertEqual(firedPixel.event.name, "site_loading_performance")
        if case .sample(let percentage) = firedPixel.frequency {
            XCTAssertEqual(percentage, 20)
        } else {
            XCTFail("Expected .sample frequency, got \(firedPixel.frequency)")
        }

        let params = try XCTUnwrap(firedPixel.event.parameters)
        XCTAssertEqual(params["first_contentful_paint_ms"], "556")
        XCTAssertEqual(params["time_to_first_byte_ms"], "235")
        XCTAssertEqual(params["load_complete_ms"], "1097")
        XCTAssertEqual(params["dom_interactive_ms"], "940")
        XCTAssertEqual(params["dom_complete_ms"], "1090")
        XCTAssertEqual(params["dom_content_loaded_ms"], "961")
    }

    func testWhenPayloadIsNotADictionaryThenNoPixelIsFired() async throws {
        var fired = 0
        let subfeature = SiteLoadingPerformanceSubfeature(
            samplePercentage: 20,
            pixelFire: { _, _ in fired += 1 }
        )
        let bogus: Any = "not a dictionary"
        let message = WKScriptMessage.mock(name: "expandedPerformanceMetricsResult", body: bogus)

        _ = try await subfeature.expandedPerformanceMetricsResult(params: bogus, original: message)

        XCTAssertEqual(fired, 0)
    }

    func testWhenPayloadHasNoMetricsKeyThenNoPixelIsFired() async throws {
        var fired = 0
        let subfeature = SiteLoadingPerformanceSubfeature(
            samplePercentage: 20,
            pixelFire: { _, _ in fired += 1 }
        )
        let payload: [String: Any] = ["other": "value"]
        let message = WKScriptMessage.mock(name: "expandedPerformanceMetricsResult", body: payload)

        _ = try await subfeature.expandedPerformanceMetricsResult(params: payload, original: message)

        XCTAssertEqual(fired, 0)
    }

    func testHandlerForMethodNameReturnsHandlerForExpandedPerformanceMetricsResultOnly() {
        let subfeature = SiteLoadingPerformanceSubfeature()
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "expandedPerformanceMetricsResult"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "vitalsResult"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "breakageReportResult"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "anythingElse"))
    }
}
