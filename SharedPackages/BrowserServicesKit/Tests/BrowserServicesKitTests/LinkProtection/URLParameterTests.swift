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

        for isFastFilterEnabled in [false, true] {
            let linkCleaner = LinkCleaner(privacyManager: privacyManager, isFastTrackingParameterFilterEnabled: { isFastFilterEnabled })

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
                               "\(resultUrl?.absoluteString ?? "(nil)") not equal to expected: \(test.expectURL) (fast filter: \(isFastFilterEnabled))")
            }
        }
    }

    func testFastFilterMatchesURLComponentsFilter() {
        let foundationCleaner = LinkCleaner(privacyManager: privacyManager, isFastTrackingParameterFilterEnabled: { false })
        let fastCleaner = LinkCleaner(privacyManager: privacyManager, isFastTrackingParameterFilterEnabled: { true })

        let prefixes = ["https://www.example.com/", "https://www.example.com:8080/a/b;c", "https://www.example.com:/x",
                        "https://user:pass@www.example.com/", "https://[::1]/p", "HTTPS://WWW.EXAMPLE.COM/P"]
        let items = ["", "a=1", "utm_source=1", "utm_source", "utm_medium=b=c", "utm_sourcex=1", "UTM_SOURCE=1", "utm%5Fsource=%7C", "=x"]
        let fragments = ["", "#", "#f?utm_source=1&a", "#f#g"]
        var queries = ["", "?"]
        var itemLists: [[String]] = [[]]
        for _ in 1...3 {
            itemLists = itemLists.flatMap { list in items.map { list + [$0] } }
            queries += itemLists.map { "?" + $0.joined(separator: "&") }
        }

        var mismatches: [String] = []
        for prefix in prefixes {
            for query in queries {
                for fragment in fragments {
                    let string = prefix + query + fragment
                    for url in [URL(string: string), Self.webKitStyleURL(string)].compactMap({ $0 }) {
                        let expected = foundationCleaner.cleanTrackingParameters(initiator: nil, url: url)
                        let actual = fastCleaner.cleanTrackingParameters(initiator: nil, url: url)
                        if actual?.absoluteString != expected?.absoluteString
                            || fastCleaner.urlParametersRemoved != foundationCleaner.urlParametersRemoved {
                            mismatches.append("\(string): \(actual?.absoluteString ?? "nil") != \(expected?.absoluteString ?? "nil")")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(mismatches.count, 0, mismatches.prefix(5).joined(separator: "\n"))
    }

    func testFastFilterMatchesURLComponentsFilterOnLargeURLs() throws {
        let foundationCleaner = LinkCleaner(privacyManager: privacyManager, isFastTrackingParameterFilterEnabled: { false })
        let fastCleaner = LinkCleaner(privacyManager: privacyManager, isFastTrackingParameterFilterEnabled: { true })
        let query = String(repeating: "p=" + String(repeating: "a", count: 30) + "&", count: 30_000)

        for string in ["https://www.example.com/?" + query + "q=1#f", "https://www.example.com/?utm_source=x&" + query + "utm_medium=y#f"] {
            let url = try XCTUnwrap(Self.webKitStyleURL(string))
            let expected = foundationCleaner.cleanTrackingParameters(initiator: nil, url: url)
            XCTAssertEqual(fastCleaner.cleanTrackingParameters(initiator: nil, url: url)?.absoluteString, expected?.absoluteString)
            XCTAssertEqual(fastCleaner.urlParametersRemoved, foundationCleaner.urlParametersRemoved)
        }
    }

    func testFastFilterFlagIsReadOnEveryCall() throws {
        var flagReads = 0
        let linkCleaner = LinkCleaner(privacyManager: privacyManager, isFastTrackingParameterFilterEnabled: {
            flagReads += 1
            return flagReads.isMultiple(of: 2)
        })
        let url = try XCTUnwrap(URL(string: "https://www.example.com/?utm_source=x&q=1"))

        for _ in 0..<2 {
            XCTAssertEqual(linkCleaner.cleanTrackingParameters(initiator: nil, url: url)?.absoluteString, "https://www.example.com/?q=1")
        }
        XCTAssertEqual(flagReads, 2)
    }

    /// WebKit creates request URLs this way, and their strings are read without copying.
    private static func webKitStyleURL(_ string: String) -> URL? {
        let bytes = Array(string.utf8)
        return CFURLCreateAbsoluteURLWithBytes(nil, bytes, bytes.count, CFStringBuiltInEncodings.UTF8.rawValue, nil, true) as URL?
    }

}
