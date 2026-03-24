//
//  AdClickAttributionPixelTests.swift
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
import ContentBlocking
import XCTest

final class AdClickAttributionPixelTests: XCTestCase {

    static let tld = TLD()

    static let noEventExpectedHandler: (AdClickAttributionEvents, [String: String]?) -> Void = { event, _ in
        XCTFail("Unexpected event: \(event)")}

    static let domainParameterName = "ad_domain_param.com"
    static let linkUrlWithParameter = URL(string: "https://example.com/test.html?\(domainParameterName)=test.com")!
    static let linkUrlWithoutParameter = URL(string: "https://example.com/test.html")!

    static let matchedVendorURL = URL(string: "https://test.com/site")!
    static let mismatchedVendorURL = URL(string: "https://other.com/site")!

    var currentEventHandler: (AdClickAttributionEvents, [String: String]?) -> Void = { _, _ in }

    lazy var mockEventMapping = EventMapping<AdClickAttributionEvents> { event, _, params, _ in
        self.currentEventHandler(event, params)
    }

    func testWhenSERPAndHeuristicsMatchThenThisMatchIsSent() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return Self.domainParameterName
        })
        feature.isDomainDetectionEnabled = true
        feature.isHeuristicDetectionEnabled = true

        currentEventHandler = Self.noEventExpectedHandler

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld, eventReporting: mockEventMapping)

        detection.onStartNavigation(url: Self.linkUrlWithParameter)

        let expectation = expectation(description: "Event fired")
        currentEventHandler = { event, params in
            expectation.fulfill()
            XCTAssertEqual(event, AdClickAttributionEvents.adAttributionDetected)
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetection], "matched")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetectionEnabled], "1")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.heuristicDetectionEnabled], "1")
        }

        detection.on2XXResponse(url: Self.matchedVendorURL)
        wait(for: [expectation], timeout: 1)
    }

    func testWhenSERPAndHeuristicsDoNotMatchThenThisMismatchIsSent() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return Self.domainParameterName
        })
        feature.isDomainDetectionEnabled = true
        feature.isHeuristicDetectionEnabled = true

        currentEventHandler = Self.noEventExpectedHandler

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld, eventReporting: mockEventMapping)

        detection.onStartNavigation(url: Self.linkUrlWithParameter)

        let expectation = expectation(description: "Event fired")
        currentEventHandler = { event, params in
            expectation.fulfill()
            XCTAssertEqual(event, AdClickAttributionEvents.adAttributionDetected)
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetection], "mismatch")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetectionEnabled], "1")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.heuristicDetectionEnabled], "1")
        }

        detection.on2XXResponse(url: Self.mismatchedVendorURL)
        wait(for: [expectation], timeout: 1)
    }

    func testWhenHeuristicsAreDisabledAndSerpIsPresentThenSerpIsUsed() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return Self.domainParameterName
        })
        feature.isDomainDetectionEnabled = true
        feature.isHeuristicDetectionEnabled = false

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld, eventReporting: mockEventMapping)

        let expectation = expectation(description: "Event fired")
        currentEventHandler = { event, params in
            expectation.fulfill()
            XCTAssertEqual(event, AdClickAttributionEvents.adAttributionDetected)
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetection], "serp_only")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetectionEnabled], "1")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.heuristicDetectionEnabled], "0")
        }

        detection.onStartNavigation(url: Self.linkUrlWithParameter)
        wait(for: [expectation], timeout: 1)

        currentEventHandler = Self.noEventExpectedHandler
        detection.on2XXResponse(url: Self.matchedVendorURL)
    }

    func testWhenHeuristicsAreDisabledAndSerpIsMissingThenNoneIsSent() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return Self.domainParameterName
        })
        feature.isDomainDetectionEnabled = true
        feature.isHeuristicDetectionEnabled = false

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld, eventReporting: mockEventMapping)

        let expectation = expectation(description: "Event fired")
        currentEventHandler = { event, params in
            expectation.fulfill()
            XCTAssertEqual(event, AdClickAttributionEvents.adAttributionDetected)
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetection], "none")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetectionEnabled], "1")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.heuristicDetectionEnabled], "0")
        }

        detection.onStartNavigation(url: Self.linkUrlWithoutParameter)
        wait(for: [expectation], timeout: 1)

        currentEventHandler = Self.noEventExpectedHandler
        detection.on2XXResponse(url: Self.matchedVendorURL)
    }

    func testWhenHeuristicsAndSerpAreDisabledThenNoneIsSent() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return Self.domainParameterName
        })
        feature.isDomainDetectionEnabled = false
        feature.isHeuristicDetectionEnabled = false

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld, eventReporting: mockEventMapping)

        let expectation = expectation(description: "Event fired")
        currentEventHandler = { event, params in
            expectation.fulfill()
            XCTAssertEqual(event, AdClickAttributionEvents.adAttributionDetected)
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetection], "none")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetectionEnabled], "0")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.heuristicDetectionEnabled], "0")
        }

        detection.onStartNavigation(url: Self.linkUrlWithParameter)

        wait(for: [expectation], timeout: 1)

        currentEventHandler = Self.noEventExpectedHandler
        detection.on2XXResponse(url: Self.matchedVendorURL)
    }

    func testWhenSerpIsDisabledThenHeuristicsAreUsed() {

        let feature = MockAttributing(onParameterNameQuery: { _ in
            return Self.domainParameterName
        })
        feature.isDomainDetectionEnabled = false
        feature.isHeuristicDetectionEnabled = true

        currentEventHandler = Self.noEventExpectedHandler

        let detection = AdClickAttributionDetection(feature: feature, tld: Self.tld, eventReporting: mockEventMapping)

        detection.onStartNavigation(url: Self.linkUrlWithParameter)

        let expectation = expectation(description: "Event fired")
        currentEventHandler = { event, params in
            expectation.fulfill()
            XCTAssertEqual(event, AdClickAttributionEvents.adAttributionDetected)
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetection], "heuristic_only")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.domainDetectionEnabled], "0")
            XCTAssertEqual(params?[AdClickAttributionEvents.Parameters.heuristicDetectionEnabled], "1")
        }

        detection.on2XXResponse(url: Self.matchedVendorURL)
        wait(for: [expectation], timeout: 1)
    }

    func testWhenAttributionIsInactiveThenNoActivityPixelIsSent() async {
        currentEventHandler = Self.noEventExpectedHandler

        let feature = MockAttributing()
        feature.onFormatMatching = { _ in return false }
        let mockRulesProvider = await MockAttributionRulesProvider()

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: Self.tld,
                                            eventReporting: mockEventMapping)

        logic.onProvisionalNavigation {}
        logic.onDidFinishNavigation(host: "test.com")

        logic.onRequestDetected(request: DetectedRequest(url: "example.com",
                                                         eTLDplus1: "example.com",
                                                         knownTracker: nil,
                                                         entity: nil,
                                                         state: .allowed(reason: .adClickAttribution),
                                                         pageUrl: "test.com"))
    }

    func testWhenAttributionIsActiveThenActivityPixelIsSentOnce() async {
        let expectation = expectation(description: "Event fired")
        expectation.expectedFulfillmentCount = 1
        currentEventHandler = { event, _ in
            expectation.fulfill()
            XCTAssertEqual(event, AdClickAttributionEvents.adAttributionActive)
        }

        let feature = MockAttributing()
        let mockRulesProvider = await MockAttributionRulesProvider()
        let mockDetection = AdClickAttributionDetection(feature: feature,
                                                        tld: Self.tld)

        let logic = AdClickAttributionLogic(featureConfig: feature,
                                            rulesProvider: mockRulesProvider,
                                            tld: Self.tld,
                                            eventReporting: mockEventMapping)

        logic.attributionDetection(mockDetection, didDetectVendor: "vendor.com")
        logic.onDidFinishNavigation(host: "https://vendor.com")

        logic.onRequestDetected(request: DetectedRequest(url: "example.com",
                                                         eTLDplus1: "example.com",
                                                         knownTracker: nil,
                                                         entity: nil,
                                                         state: .allowed(reason: .adClickAttribution),
                                                         pageUrl: "test.com"))

        logic.onRequestDetected(request: DetectedRequest(url: "example.com",
                                                         eTLDplus1: "example.com",
                                                         knownTracker: nil,
                                                         entity: nil,
                                                         state: .allowed(reason: .adClickAttribution),
                                                         pageUrl: "test.com"))

        await fulfillment(of: [expectation], timeout: 1)
    }

}
