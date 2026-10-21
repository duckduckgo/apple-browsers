//
//  AmpMatchingTests.swift
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

import os.log
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import TrackerRadarKit
@testable import BrowserServicesKit

struct AmpRefTests: Decodable {
    struct AmpFormatTests: Decodable {
        let name: String
        let desc: String
        let tests: [AmpFormatTest]
    }

    struct AmpFormatTest: Decodable {
        let name: String
        let ampURL: String
        let expectURL: String
        let exceptPlatforms: [String]?
    }

    struct AmpKeywordTests: Decodable {
        let name: String
        let desc: String
        let tests: [AmpKeywordTest]
    }

    struct AmpKeywordTest: Decodable {
        let name: String
        let ampURL: String
        let expectAmpDetected: Bool
        let exceptPlatforms: [String]?
    }

    let ampFormats: AmpFormatTests
    let ampKeywords: AmpKeywordTests
}

final class AmpMatchingTests: XCTestCase {

    private enum Resource {
        static let config = "Res/privacy-reference-tests/amp-protections/config_reference.json"
        static let tests = "Res/privacy-reference-tests/amp-protections/tests.json"
    }

    private static let data = JsonTestDataLoader()
    private static let config = data.fromJsonFile(Resource.config)

    private var privacyManager: PrivacyConfigurationManager {
        makePrivacyManager(config: Self.config)
    }

    private func makePrivacyManager(config: Data) -> PrivacyConfigurationManager {
        let embeddedDataProvider = MockEmbeddedDataProvider(data: config,
                                                            etag: "embedded")
        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = []

        return PrivacyConfigurationManager(fetchedETag: nil,
                                           fetchedData: nil,
                                           embeddedDataProvider: embeddedDataProvider,
                                           localProtection: localProtection,
                                           internalUserDecider: MockInternalUserDecider())
    }

    private var contentBlockingManager: ContentBlockerRulesManager {
        let listsSource = ContentBlockerRulesListSourceMock()
        let exceptionsSource = ContentBlockerRulesExceptionsSourceMock()
        return ContentBlockerRulesManager(rulesSource: listsSource, exceptionsSource: exceptionsSource)
    }

    private lazy var ampTestSuite: AmpRefTests = {
        let tests = Self.data.fromJsonFile(Resource.tests)
        return try! JSONDecoder().decode(AmpRefTests.self, from: tests)
    }()

    func testAmpFormats() throws {
        let tests = ampTestSuite.ampFormats.tests
        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        for test in tests {
            let skip = test.exceptPlatforms?.contains("ios-browser")
            if skip == true {
                os_log("!!SKIPPING TEST: %s", test.name)
                continue
            }

            os_log("TEST: %s", test.name)

            let ampUrl = URL(string: test.ampURL)
            let resultUrl = linkCleaner.extractCanonicalFromAMPLink(initiator: nil, destination: ampUrl)

            // Empty expectedUrl should be treated as nil
            let expectedUrl = !test.expectURL.isEmpty ? test.expectURL : nil
            XCTAssertEqual(resultUrl?.absoluteString, expectedUrl, "\(resultUrl!.absoluteString) not equal to expected: \(expectedUrl ?? "nil")")
        }
    }

    func testAmpKeywords() throws {
        let tests = ampTestSuite.ampKeywords.tests
        let linkCleaner = LinkCleaner(privacyManager: privacyManager)

        let ampExtractor = AMPCanonicalExtractor(linkCleaner: linkCleaner,
                                                 privacyManager: privacyManager,
                                                 contentBlockingManager: contentBlockingManager,
                                                 errorReporting: nil)

        for test in tests {
            let skip = test.exceptPlatforms?.contains("ios-browser")
            if skip == true {
                os_log("!!SKIPPING TEST: %s", test.name)
                continue
            }

            os_log("TEST: %s", test.name)

            let ampUrl = URL(string: test.ampURL)
            let result = ampExtractor.urlContainsAMPKeyword(ampUrl)
            XCTAssertEqual(result, test.expectAmpDetected, "\(test.ampURL) not correctly identified. Expected: \(test.expectAmpDetected.description)")
        }
    }

    private static let deepExtractionConfig = """
    {
        "features": {
            "ampLinks": {
                "state": "enabled",
                "exceptions": [],
                "settings": {
                    "deepExtractionEnabled": true,
                    "keywords": ["/amp"],
                    "linkFormats": []
                }
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8) ?? Data()

    private func makeDeepExtractionAMPExtractor() -> AMPCanonicalExtractor {
        let deepExtractionPrivacyManager = makePrivacyManager(config: Self.deepExtractionConfig)
        return AMPCanonicalExtractor(linkCleaner: LinkCleaner(privacyManager: deepExtractionPrivacyManager),
                                     privacyManager: deepExtractionPrivacyManager,
                                     contentBlockingManager: contentBlockingManager,
                                     errorReporting: nil)
    }

    func testWhenURLIsWithinMaxLengthThenAMPKeywordIsDetected() throws {
        let ampExtractor = makeDeepExtractionAMPExtractor()
        let url = try XCTUnwrap(URL(string: "https://www.example.com/amp/article?query=value"))

        XCTAssertTrue(ampExtractor.urlContainsAMPKeyword(url))
    }

    func testWhenURLExceedsMaxLengthThenAMPKeywordIsNotDetected() throws {
        let ampExtractor = makeDeepExtractionAMPExtractor()
        let longQuery = String(repeating: "a", count: AMPCanonicalExtractor.Constants.maxURLLength)
        let url = try XCTUnwrap(URL(string: "https://www.example.com/amp/article?query=\(longQuery)"))

        XCTAssertFalse(ampExtractor.urlContainsAMPKeyword(url))
    }

}
