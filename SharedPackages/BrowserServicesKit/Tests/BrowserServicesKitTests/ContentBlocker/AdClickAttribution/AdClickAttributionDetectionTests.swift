//
//  AdClickAttributionDetectionTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import XCTest

final class MockAttributing: AdClickAttributing {

    init(onFormatMatching: @escaping (URL) -> Bool = { _ in return true },
         onParameterNameQuery: @escaping (URL) -> String? = { _ in return nil }) {
        self.onFormatMatching = onFormatMatching
        self.onParameterNameQuery = onParameterNameQuery
    }

    var isEnabled = true

    var allowlist = [AdClickAttributionFeature.AllowlistEntry]()

    var navigationExpiration: Double = 30
    var totalExpiration: Double = 7 * 24 * 60

    var onFormatMatching: (URL) -> Bool
    var onParameterNameQuery: (URL) -> String?

    func isMatchingAttributionFormat(_ url: URL) -> Bool {
        return onFormatMatching(url)
    }

    func attributionDomainParameterName(for url: URL) -> String? {
        return onParameterNameQuery(url)
    }

    var isHeuristicDetectionEnabled: Bool = true
    var isDomainDetectionEnabled: Bool = true

}

final class MockAdClickAttributionDetectionDelegate: AdClickAttributionDetectionDelegate {

    init(onAttributionDetection: @escaping (String) -> Void) {
        self.onAttributionDetection = onAttributionDetection
    }

    var onAttributionDetection: (String) -> Void
    func attributionDetection(_ detection: AdClickAttributionDetection, didDetectVendor vendorHost: String) {
        onAttributionDetection(vendorHost)
    }
}

final class AdClickAttributionDetectionTests: XCTestCase {

    let domainParameterName = "ad_domain_param.com"

    static let tld = TLD()

    func testWhenFeatureIsDisabledThenNothingIsDetected() {
        let feature = MockAttributing { _ in return true }
        feature.isEnabled = false

        let delegate = MockAdClickAttributionDetectionDelegate { _ in
            XCTFail("Nothing should be detected")
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com")!)
        detection.on2XXResponse(url: URL(string: "https://test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://test.com")!)
    }

    func testWhenHeuristicOptionIsDisabledThenNothingIsDetected() {
        let feature = MockAttributing { _ in return true }
        feature.isHeuristicDetectionEnabled = false

        let delegate = MockAdClickAttributionDetectionDelegate { _ in
            XCTFail("Nothing should be detected")
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com")!)
        detection.on2XXResponse(url: URL(string: "https://test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://test.com")!)
    }

    func testWhenDomainDetectionOptionIsDisabledThenFallbackToHeuristic() {
        let feature = MockAttributing(onParameterNameQuery: { _ in
            return self.domainParameterName
        })
        feature.isDomainDetectionEnabled = false
        feature.isHeuristicDetectionEnabled = true

        var delegate = MockAdClickAttributionDetectionDelegate { _ in
            XCTFail("Nothing should be detected")
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com?\(domainParameterName)=domain.net"))

        let delegateCalled = expectation(description: "Delegate called")
        delegate = MockAdClickAttributionDetectionDelegate { vendorHost in
            XCTAssertEqual(vendorHost, "test.com")
            delegateCalled.fulfill()
        }
        detection.delegate = delegate

        detection.on2XXResponse(url: URL(string: "https://test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://test.com")!)

        wait(for: [delegateCalled], timeout: 0.1)
    }

    func testWhenThereAreNoMatchesThenNothingIsDetected() {

        let feature = MockAttributing { _ in return false }

        let delegate = MockAdClickAttributionDetectionDelegate { _ in
            XCTFail("Nothing should be detected")
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com")!)
        detection.on2XXResponse(url: URL(string: "https://test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://test.com")!)
    }

    func testWhenThereAreMatchesThenVendorIsDetected_Heuristic() {

        let feature = MockAttributing { _ in return true }

        let delegateCalled = expectation(description: "Delegate called")

        let delegate = MockAdClickAttributionDetectionDelegate { vendorHost in
            XCTAssertEqual(vendorHost, "test.com")
            delegateCalled.fulfill()
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com")!)
        detection.on2XXResponse(url: URL(string: "https://test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://test.com")!)

        waitForExpectations(timeout: 0.1)
    }

    func testWhenThereAreMatchesThenVendorIsDetected_Directly() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return self.domainParameterName
        })

        let delegateCalled = expectation(description: "Delegate called")

        let delegate = MockAdClickAttributionDetectionDelegate { vendorHost in
            XCTAssertEqual(vendorHost, "domain.net")
            delegateCalled.fulfill()
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com?\(domainParameterName)=domain.net"))
        detection.on2XXResponse(url: URL(string: "https://test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://test.com")!)

        waitForExpectations(timeout: 0.1)
    }

    func testWhenThereAreMatchesThenVendorIsETLDplus1_Heuristic() {

        let feature = MockAttributing { _ in return true }

        let delegateCalled = expectation(description: "Delegate called")

        let delegate = MockAdClickAttributionDetectionDelegate { vendorHost in
            XCTAssertEqual(vendorHost, "test.com")
            delegateCalled.fulfill()
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com")!)
        detection.on2XXResponse(url: URL(string: "https://a.sub.test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://a.sub.test.com")!)

        waitForExpectations(timeout: 0.1)
    }

    func testWhenThereAreMatchesThenVendorIsETLDplus1_Directly() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return self.domainParameterName
        })

        let delegateCalled = expectation(description: "Delegate called")

        let delegate = MockAdClickAttributionDetectionDelegate { vendorHost in
            XCTAssertEqual(vendorHost, "domain.net")
            delegateCalled.fulfill()
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com?\(domainParameterName)=a.domain.net"))
        detection.on2XXResponse(url: URL(string: "https://sub.test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://sub.test.com")!)

        waitForExpectations(timeout: 0.1)
    }

    func testWhenMatchedAndWrongParameterThenFallbackToHeuristic() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return self.domainParameterName
        })

        let delegateCalled = expectation(description: "Delegate called")
        delegateCalled.expectedFulfillmentCount = 1

        let delegate = MockAdClickAttributionDetectionDelegate { vendorHost in
            XCTAssertEqual(vendorHost, "test.com")
            delegateCalled.fulfill()
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://example.com?\(domainParameterName)=com"))
        detection.on2XXResponse(url: URL(string: "https://sub.test.com")!)

        // Should match and notify only once
        detection.on2XXResponse(url: URL(string: "https://another.test.com")!)

        detection.onDidFinishNavigation(url: URL(string: "https://another.test.com")!)

        waitForExpectations(timeout: 0.1)
    }

    func testWhenNavigationFailsThenCorrectVendorIsDetected() {

        let feature = MockAttributing { _ in return true }

        var delegate = MockAdClickAttributionDetectionDelegate { _ in
            XCTFail("Should not detect in case of an error")
        }

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld)
        detection.delegate = delegate

        // First matching requests that fails
        detection.onStartNavigation(url: URL(string: "https://example.com")!)
        detection.onDidFailNavigation()

        // Simulate non-matching request - nothing should be detected
        feature.onFormatMatching = { _ in return false }

        detection.onStartNavigation(url: URL(string: "https://other.com")!)
        detection.on2XXResponse(url: URL(string: "https://test.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://test.com")!)

        // Simulate matching request - it should be detected
        feature.onFormatMatching = { _ in return true }

        let delegateCalled = expectation(description: "Delegate called")
        delegate = MockAdClickAttributionDetectionDelegate { vendorHost in
            XCTAssertEqual(vendorHost, "something.com")
            delegateCalled.fulfill()
        }
        detection.delegate = delegate

        detection.onStartNavigation(url: URL(string: "https://domain.com")!)
        detection.on2XXResponse(url: URL(string: "https://a.something.com")!)
        detection.onDidFinishNavigation(url: URL(string: "https://a.something.com")!)

        waitForExpectations(timeout: 0.1)
    }
}
