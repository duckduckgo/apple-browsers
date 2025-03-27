//
//  HTTPSUpgradeReferenceTests.swift
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

import Foundation
import os.log
import Common
import XCTest
@testable import BrowserServicesKit
@testable import BloomFilterWrapper

private struct HTTPSUpgradesRefTests: Decodable {
    struct HTTPSUpgradesTests: Decodable {
        let name: String
        let desc: String
        let tests: [HTTPSUpgradesTest]
    }

    struct HTTPSUpgradesTest: Decodable {
        let name: String
        let siteURL: String
        let requestURL: String
        let requestType: String
        let expectURL: String
        let exceptPlatforms: [String]

        var shouldSkip: Bool { exceptPlatforms.contains("ios-browser") }
    }

    let navigations: HTTPSUpgradesTests
    let subrequests: HTTPSUpgradesTests
}

final class HTTPSUpgradeReferenceTests: XCTestCase {

    private enum Resource {
        static let config = "Resources/privacy-reference-tests/https-upgrades/config_reference.json"
        static let tests = "Resources/privacy-reference-tests/https-upgrades/tests.json"
        static let allowList = "Resources/privacy-reference-tests/https-upgrades/https_allowlist_reference.json"
        static let bloomFilterSpec = "Resources/privacy-reference-tests/https-upgrades/https_bloomfilter_spec_reference.json"
        static let bloomFilter = "Resources/privacy-reference-tests/https-upgrades/https_bloomfilter_reference"
    }

    private static let data = JsonTestDataLoader()

    private static let config = data.fromJsonFile(Resource.config)
    private static let emptyConfig =
    """
    {
        "features": {
            "https": {
                "state": "enabled"
            }
        }
    }
    """.data(using: .utf8)!

    private func makePrivacyManager(config: Data? = config, unprotectedDomains: [String] = []) -> PrivacyConfigurationManager {
        let embeddedDataProvider = MockEmbeddedDataProvider(data: config ?? Self.emptyConfig,
                                                            etag: "embedded")
        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = Set(unprotectedDomains)

        return PrivacyConfigurationManager(fetchedETag: nil,
                                           fetchedData: nil,
                                           embeddedDataProvider: embeddedDataProvider,
                                           localProtection: localProtection,
                                           internalUserDecider: DefaultInternalUserDecider())
    }

    private lazy var httpsUpgradesTestSuite: HTTPSUpgradesRefTests = {
        let tests = Self.data.fromJsonFile(Resource.tests)
        return try! JSONDecoder().decode(HTTPSUpgradesRefTests.self, from: tests)
    }()

    private lazy var excludedDomains: [String] = {
        let allowListData = Self.data.fromJsonFile(Resource.allowList)
        return try! HTTPSUpgradeParser.convertExcludedDomainsData(allowListData)
    }()

    private lazy var bloomFilterSpecification: HTTPSBloomFilterSpecification = {
        let data = Self.data.fromJsonFile(Resource.bloomFilterSpec)
        return try! HTTPSUpgradeParser.convertBloomFilterSpecification(fromJSONData: data)
    }()

    private lazy var bloomFilter: BloomFilterWrapper? = {
        let path = Bundle.module.path(forResource: Resource.bloomFilter, ofType: "bin")!
        return BloomFilterWrapper(fromPath: path,
                                  withBitCount: Int32(bloomFilterSpecification.bitCount),
                                  andTotalItems: Int32(bloomFilterSpecification.totalEntries))
    }()

    private lazy var mockStore: HTTPSUpgradeStore = {
        HTTPSUpgradeStoreMock(bloomFilter: bloomFilter, bloomFilterSpecification: bloomFilterSpecification, excludedDomains: excludedDomains)
    }()

    func testHTTPSUpgradesNavigations() async {
        let tests = httpsUpgradesTestSuite.navigations.tests
        let httpsUpgrade = HTTPSUpgrade(store: mockStore, privacyManager: makePrivacyManager(), logger: Logger())
        await httpsUpgrade.loadData()

        for test in tests {
            os_log("TEST: %s", test.name)

            guard !test.shouldSkip else {
                os_log("SKIPPING TEST: \(test.name)")
                return
            }

            guard let url = URL(string: test.requestURL) else {
                XCTFail("BROKEN INPUT: \(Resource.tests)")
                return
            }

            var resultURL = url
            let result = await httpsUpgrade.upgrade(url: url)
            if case let .success(upgradedURL) = result {
                resultURL = upgradedURL
            }
            XCTAssertEqual(resultURL.absoluteString, test.expectURL, "FAILED: \(test.name)")
        }
    }

    func testLocalUnprotectedDomainShouldNotUpgradeToHTTPS() async {
        let httpsUpgrade = HTTPSUpgrade(store: mockStore, privacyManager: makePrivacyManager(config: nil, unprotectedDomains: ["secure.thirdtest.com"]), logger: Logger())
        await httpsUpgrade.loadData()

        let url = URL(string: "http://secure.thirdtest.com")!

        var resultURL = url
        let result = await httpsUpgrade.upgrade(url: url)
        if case let .success(upgradedURL) = result {
            resultURL = upgradedURL
        }

        XCTAssertEqual(resultURL.absoluteString, url.absoluteString, "FAILED: \(resultURL)")
    }

    func testLocalUnprotectedDomainShouldUpgradeSubdomainToHTTPS() async {
        let httpsUpgrade = HTTPSUpgrade(store: mockStore, privacyManager: makePrivacyManager(config: nil, unprotectedDomains: ["thirdtest.com"]), logger: Logger())
        await httpsUpgrade.loadData()

        let url = URL(string: "http://secure.thirdtest.com")!

        var resultURL = url
        let result = await httpsUpgrade.upgrade(url: url)
        if case let .success(upgradedURL) = result {
            resultURL = upgradedURL
        }

        XCTAssertEqual(resultURL.absoluteString, url.toHttps()?.absoluteString, "FAILED: \(resultURL)")
    }

}
