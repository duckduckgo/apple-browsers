//
//  ReferrerTrimmingTests.swift
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

import XCTest
import os.log
import WebKit
import Common
@testable import TrackerRadarKit
@testable import BrowserServicesKit

struct ReferrerTests: Codable {
    struct ReferrerHeaderTest: Codable {
        let name: String
        let navigatingFromURL: String
        let navigatingToURL: String
        let referrerValue: String?
        let expectReferrerHeaderValue: String?
        let exceptPlatforms: [String]?
    }

    struct ReferrerHeaderTestSuite: Codable {
        let name: String
        let desc: String
        let tests: [ReferrerHeaderTest]
    }

    let refererHeaderNavigation: ReferrerHeaderTestSuite
}

class ReferrerTrimmingTests: XCTestCase {

    private enum Resource {
        static let config = "Resources/privacy-reference-tests/referrer-trimming/config_reference.json"
        static let tds = "Resources/privacy-reference-tests/referrer-trimming/tracker_radar_reference.json"
        static let tests = "Resources/privacy-reference-tests/referrer-trimming/tests.json"
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

    private var contentBlockingManager: ContentBlockerRulesManager {
        let listsSource = ContentBlockerRulesListSourceMock()
        let exceptionsSource = ContentBlockerRulesExceptionsSourceMock()
        return ContentBlockerRulesManager(rulesSource: listsSource, exceptionsSource: exceptionsSource)
    }

    private lazy var tds: TrackerData = {
        let trackerJSON = Self.data.fromJsonFile(Resource.tds)
        return try! JSONDecoder().decode(TrackerData.self, from: trackerJSON)
    }()

    private lazy var referrerTestSuite: ReferrerTests = {
        let tests = Self.data.fromJsonFile(Resource.tests)
        return try! JSONDecoder().decode(ReferrerTests.self, from: tests)
    }()

    func testReferrerTrimming() throws {
        let tests = referrerTestSuite.refererHeaderNavigation.tests
        let referrerTrimming = ReferrerTrimming(privacyManager: privacyManager,
                                                contentBlockingManager: contentBlockingManager,
                                                tld: TLD())

        for test in tests {
            let skip = test.exceptPlatforms?.contains("ios-browser")
            if skip == true {
                os_log("!!SKIPPING TEST: %s", test.name)
                continue
            }

            os_log("TEST: %s", test.name)

            let referrerResult = referrerTrimming.getTrimmedReferrer(originUrl: URL(string: test.navigatingFromURL)!,
                                                                     destUrl: URL(string: test.navigatingToURL)!,
                                                                     referrerUrl: test.referrerValue != nil ? URL(string: test.referrerValue!) : nil,
                                                                     trackerData: tds)

            // nil result is considered unchanged
            let resultUrl = referrerResult == nil ? test.referrerValue : referrerResult
            XCTAssertEqual(resultUrl, test.expectReferrerHeaderValue, "\(test.name) failed")
        }
    }

}
