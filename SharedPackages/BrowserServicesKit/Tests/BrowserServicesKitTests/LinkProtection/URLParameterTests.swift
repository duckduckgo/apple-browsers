//
//  URLParameterTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import os.log
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import TrackerRadarKit
@testable import BrowserServicesKit

struct URLParamRefTests: Decodable {
    struct URLParamTests: Decodable {
        let name: String
        let desc: String
        let tests: [URLParamTest]
    }

    struct URLParamTest: Decodable {
        let name: String
        let testURL: String
        let expectURL: String
        let initiatorURL: String?
        let exceptPlatforms: [String]?
    }

    let trackingParameters: URLParamTests
}

final class URLParameterTests: XCTestCase {

    private enum Resource {
        static let config = "Res/privacy-reference-tests/url-parameters/config_reference.json"
        static let tests = "Res/privacy-reference-tests/url-parameters/tests.json"
    }

    private static let data = JsonTestDataLoader()
    private static let config = data.fromJsonFile(Resource.config)

    private var privacyManager: PrivacyConfigurationManager {
        let embeddedDataProvider = MockEmbeddedDataProvider(data: Self.config,
                                                            etag: "embedded")
        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = []

        return PrivacyConfigurationManager(fetchedETag: nil,
                                           fetchedData: nil,
                                           embeddedDataProvider: embeddedDataProvider,
                                           localProtection: localProtection,
                                           internalUserDecider: MockInternalUserDecider())
    }

    private lazy var urlParamTestSuite: URLParamRefTests = {
        let tests = Self.data.fromJsonFile(Resource.tests)
        return try! JSONDecoder().decode(URLParamRefTests.self, from: tests)
    }()

    func testURLParamStripping() throws {
        let tests = urlParamTestSuite.trackingParameters.tests

        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        for test in tests {
            let skip = test.exceptPlatforms?.contains("ios-browser")
            if skip == true {
                os_log("!!SKIPPING TEST: %s", test.name)
                continue
            }

            os_log("TEST: %s", test.name)

            let testUrl = URL(string: test.testURL)
            let initiator = test.initiatorURL != nil ? URL(string: test.initiatorURL!) : nil
            var resultUrl = linkCleaner.cleanTrackingParameters(initiator: initiator, url: testUrl)

            if resultUrl == nil {
                // Tests expect unchanged URLs to match testURL
                resultUrl = testUrl
            }

            XCTAssertEqual(resultUrl?.absoluteString, test.expectURL,
                           "\(resultUrl?.absoluteString ?? "(nil)") not equal to expected: \(test.expectURL)")
        }
    }

    func testURLParamStrippingPreservesEncodedQuerySemantics() throws {
        let testCases = [
            (
                input: "https://example.com/?utm_source=value&",
                expected: "https://example.com/?"
            ),
            (
                input: "https://example.com/?&utm_source=value",
                expected: "https://example.com/?"
            ),
            (
                input: "https://example.com/?first=1&&utm_source=value&&last=2",
                expected: "https://example.com/?first=1&&&last=2"
            ),
            (
                input: "https://example.com/?value=a%26b%3Dc&utm_source=value",
                expected: "https://example.com/?value=a%26b%3Dc"
            ),
            (
                input: "https://example.com/?value=a=b=c&utm_source=value",
                expected: "https://example.com/?value=a=b=c"
            ),
            (
                input: "https://example.com/?utm_source=value#?value=a&other=b",
                expected: "https://example.com/#?value=a&other=b"
            )
        ]
        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        for testCase in testCases {
            let url = try XCTUnwrap(URL(string: testCase.input))
            let result = linkCleaner.cleanTrackingParameters(initiator: nil, url: url)

            XCTAssertEqual(result?.absoluteString, testCase.expected, testCase.input)
            XCTAssertTrue(linkCleaner.urlParametersRemoved, testCase.input)
        }
    }

    func testURLParamStrippingDoesNotMatchPercentEncodedParameterName() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/?%75tm_source=value&safe=1"))
        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        let result = linkCleaner.cleanTrackingParameters(initiator: nil, url: url)

        XCTAssertEqual(result, url)
        XCTAssertFalse(linkCleaner.urlParametersRemoved)
    }

    func testURLParamStrippingSupportsLargeTrackingParameterValue() throws {
        let largeValue = String(repeating: "a", count: 1_000_000)
        let url = try XCTUnwrap(URL(string: "https://example.com/?safe=1&utm_source=\(largeValue)#fragment"))
        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        let result = linkCleaner.cleanTrackingParameters(initiator: nil, url: url)

        XCTAssertEqual(result?.absoluteString, "https://example.com/?safe=1#fragment")
        XCTAssertTrue(linkCleaner.urlParametersRemoved)
    }

    func testURLParamStrippingPreservesLargeURLWithoutTrackingParameters() throws {
        let largeValue = String(repeating: "a", count: 1_000_000)
        let url = try XCTUnwrap(URL(string: "https://example.com/?safe=\(largeValue)#fragment"))
        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        let result = linkCleaner.cleanTrackingParameters(initiator: nil, url: url)

        XCTAssertEqual(result, url)
        XCTAssertFalse(linkCleaner.urlParametersRemoved)
    }

    func testURLParamStrippingPreservesRelativeURLAndBaseURL() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.com/root/"))
        let url = try XCTUnwrap(URL(string: "page?safe=1&utm_source=value#fragment", relativeTo: baseURL))
        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        let result = try XCTUnwrap(linkCleaner.cleanTrackingParameters(initiator: nil, url: url))

        XCTAssertEqual(result.relativeString, "page?safe=1#fragment")
        XCTAssertEqual(result.baseURL, baseURL)
        XCTAssertTrue(linkCleaner.urlParametersRemoved)
    }

}
