//
//  UserAgentTests.swift
//  UnitTests
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import WebKit
import XCTest

@testable import Core

class MockEmbeddedDataProvider: EmbeddedDataProvider {
    var embeddedDataEtag: String

    var embeddedData: Data

    init(data: Data, etag: String) {
        embeddedData = data
        embeddedDataEtag = etag
    }
}

class MockDomainsProtectionStore: DomainsProtectionStore {
    var unprotectedDomains = Set<String>()

    func disableProtection(forDomain domain: String) {
        unprotectedDomains.remove(domain)
    }

    func enableProtection(forDomain domain: String) {
        unprotectedDomains.insert(domain)
    }
}

final class UserAgentTests: XCTestCase {
    
    private struct DefaultAgent {

        static let mobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        static let tablet = "Mozilla/5.0 (iPad; CPU OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        static let oldWebkitVersionMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.14 (KHTML, like Gecko) Mobile/15E148"
        static let newWebkitVersionMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.16 (KHTML, like Gecko) Mobile/15E148"
        static let sameWebkitVersionMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    }
    
    private struct ExpectedAgent {

        static let osVersion = ProcessInfo.processInfo.operatingSystemVersion

        static func backwardsCompatibleVersionComponent(_ fallback: String) -> String {
            osVersion.majorVersion < 26 ? fallback : "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        }

        // Based on DefaultAgent values
        static let mobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
        static let tablet = "Mozilla/5.0 (iPad; CPU OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
        static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) DuckDuckGo/7 Safari/605.1.15"
        static let oldWebkitVersionMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.14 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 DuckDuckGo/7 Safari/605.1.14"
        static let newWebkitVersionMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 DuckDuckGo/7 Safari/604.1"
        static let sameWebkitVersionMobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 DuckDuckGo/7 Safari/604.1"

        static let mobileNoApplication = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 Safari/605.1.15"

        // Based on fallback constants in UserAgent
        static let mobileFallback = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("13.5")) Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
        static let desktopFallback = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("13.5")) DuckDuckGo/7 Safari/605.1.15"

        static let mobileFixed = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 DuckDuckGo/7 Safari/604.1"
        static let tabletFixed = "Mozilla/5.0 (iPad; CPU OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 DuckDuckGo/7 Safari/604.1"
        static let desktopFixed = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("18.3")) DuckDuckGo/7 Safari/605.1.15"

        static let mobileClosest = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 Safari/604.1"
        static let tabletClosest = "Mozilla/5.0 (iPad; CPU OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("12.4")) Mobile/15E148 Safari/604.1"
        static let desktopClosest = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(backwardsCompatibleVersionComponent("18.3")) Safari/605.1.15"

        static let mobileMappedPre26 = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.4 Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
        static let mobileMapped2600 = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
        static let mobileMapped2601 = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
        static let mobileMappedPost26 = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 DuckDuckGo/7 Safari/605.1.15"
    }
    
    private struct Constants {
        static let url = URL(string: "http://example.com/index.html")!
        static let noAppUrl = URL(string: "http://cvs.com/index.html")!
        static let noAppSubdomainUrl = URL(string: "http://subdomain.cvs.com/index.html")!
        static let ddgFixedUrl = URL(string: "http://test2.com/index.html")!
        static let ddgDefaultUrl = URL(string: "http://test3.com/index.html")!
    }
    
    let testConfig = """
    {
        "features": {
            "customUserAgent": {
                "state": "enabled",
                "settings": {
                    "useUpdatedSafariVersions": true,
                    "safariVersionMappings": {},
                    "omitApplicationSites": [
                        {
                            "domain": "cvs.com",
                            "reason": "Site reports browser not supported"
                        }
                    ]
                },
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!
    
    private var privacyConfig: PrivacyConfiguration!

    override func setUp() {
        super.setUp()
        
        let mockEmbeddedData = MockEmbeddedDataProvider(data: testConfig, etag: "test")
        let mockProtectionStore = MockDomainsProtectionStore()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: MockInternalUserDecider())

        privacyConfig = manager.privacyConfig
    }
    
    func testWhenMobileUaAndDektopFalseThenMobileAgentCreatedWithApplicationAndSafariSuffix() {
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.mobile, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: privacyConfig))
    }
    
    func testWhenMobileUaAndDektopTrueThenDesktopAgentCreatedWithApplicationAndSafariSuffix() {
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.desktop, testee.agent(forUrl: Constants.url, isDesktop: true, privacyConfig: privacyConfig))
    }
    
    func testWhenTabletUaAndDektopFalseThenTabletAgentCreatedWithApplicationAndSafariSuffix() {
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.tablet, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: privacyConfig))
    }
    
    func testWhenTabletUaAndDektopTrueThenDesktopAgentCreatedWithApplicationAndSafariSuffix() {
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.desktop, testee.agent(forUrl: Constants.url, isDesktop: true, privacyConfig: privacyConfig))
    }
    
    func testWhenNoUaAndDesktopFalseThenFallbackMobileAgentIsUsed() {
        let testee = UserAgent(privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.mobileFallback, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: privacyConfig))
    }
    
    func testWhenNoUaAndDesktopTrueThenFallbackDesktopAgentIsUsed() {
        let testee = UserAgent(privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.desktopFallback, testee.agent(forUrl: Constants.url, isDesktop: true, privacyConfig: privacyConfig))
    }
    
    func testWhenDomainDoesNotSupportApplicationComponentThenApplicationIsOmittedFromUa() {
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.mobileNoApplication, testee.agent(forUrl: Constants.noAppUrl, isDesktop: false, privacyConfig: privacyConfig))
    }
    
    func testWhenSubdomainDoesNotSupportApplicationComponentThenApplicationIsOmittedFromUa() {
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.mobileNoApplication,
                       testee.agent(forUrl: Constants.noAppSubdomainUrl, isDesktop: false, privacyConfig: privacyConfig))
    }
    
    func testWhenCustomUserAgentIsDisabledThenApplicationIsOmittedFromUa() {
        let disabledConfig = """
        {
            "features": {
                "customUserAgent": {
                    "state": "disabled",
                    "settings": {
                    "useUpdatedSafariVersions": true,
                    "safariVersionMappings": {},
                        "omitApplicationSites": [
                            {
                                "domain": "cvs.com",
                                "reason": "Site breakage"
                            }
                        ]
                    },
                    "exceptions": []
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
        
        let mockEmbeddedData = MockEmbeddedDataProvider(data: disabledConfig, etag: "test")
        let mockProtectionStore = MockDomainsProtectionStore()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: MockInternalUserDecider())

        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: privacyConfig)
        XCTAssertEqual(ExpectedAgent.mobileNoApplication, testee.agent(forUrl: Constants.url, isDesktop: false,
                                                                       privacyConfig: manager.privacyConfig))
    }

    /// Experimental config

    func makePrivacyConfig(from rawConfig: Data) -> PrivacyConfiguration {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: rawConfig, etag: "test")
        let mockProtectionStore = MockDomainsProtectionStore()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: MockInternalUserDecider())
        return manager.privacyConfig
    }

    let ddgConfig = """
    {
        "features": {
            "customUserAgent": {
                "defaultPolicy": "ddg",
                "state": "enabled",
                "settings": {
                    "useUpdatedSafariVersions": true,
                    "safariVersionMappings": {},
                    "omitApplicationSites": [
                        {
                            "domain": "cvs.com",
                            "reason": "Site reports browser not supported"
                        }
                    ],
                    "ddgFixedSites": [
                        {
                            "domain": "test2.com"
                        }
                    ]
                },
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenMobileUaAndDesktopFalseAndDomainSupportsFixedUAThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobileFixed, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, privacyConfig: config))
    }

    func testWhenMobileUaAndDesktopTrueAndDomainSupportsFixedUAThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.desktopFixed, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: true, privacyConfig: config))
    }

    func testWhenTabletUaAndDesktopFalseAndDomainSupportsFixedUAThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.tabletFixed, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, privacyConfig: config))
    }

    func testWhenTabletUaAndDesktopTrueAndDomainSupportsFixedUAThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.desktopFixed, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: true, privacyConfig: config))
    }

    let ddgFixedConfig = """
    {
        "features": {
            "customUserAgent": {
                "state": "enabled",
                "settings": {
                    "defaultPolicy": "ddgFixed",
                    "useUpdatedSafariVersions": true,
                    "safariVersionMappings": {},
                    "omitApplicationSites": [
                        {
                            "domain": "cvs.com",
                            "reason": "Site reports browser not supported"
                        }
                    ],
                    "ddgDefaultSites": [
                        {
                            "domain": "test3.com"
                        }
                    ]
                },
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenMobileUaAndDesktopFalseAndDefaultPolicyFixedThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobileFixed, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenMobileUaAndDesktopTrueAndDefaultPolicyFixedThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.desktopFixed, testee.agent(forUrl: Constants.url, isDesktop: true, privacyConfig: config))
    }

    func testWhenTabletUaAndDesktopFalseAndDefaultPolicyFixedThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.tabletFixed, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenTabletUaAndDesktopTrueAndDefaultPolicyFixedThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.desktopFixed, testee.agent(forUrl: Constants.url, isDesktop: true, privacyConfig: config))
    }

    func testWhenDefaultPolicyFixedAndDomainIsOnDefaultListThenDefaultAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobile, testee.agent(forUrl: Constants.ddgDefaultUrl, isDesktop: false, privacyConfig: config))
    }

    let closestConfig = """
    {
        "features": {
            "customUserAgent": {
                "state": "enabled",
                "settings": {
                    "defaultPolicy": "closest",
                    "useUpdatedSafariVersions": true,
                    "safariVersionMappings": {},
                    "omitApplicationSites": [
                        {
                            "domain": "cvs.com",
                            "reason": "Site reports browser not supported"
                        }
                    ],
                    "ddgFixedSites": [
                        {
                            "domain": "test2.com"
                        }
                    ],
                    "ddgDefaultSites": [
                        {
                            "domain": "test3.com"
                        }
                    ]
                },
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenMobileUaAndDesktopFalseAndDefaultPolicyClosestThenClosestMobileAgentUsed() {
        let config = makePrivacyConfig(from: closestConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobileClosest, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenMobileUaAndDesktopTrueAndDefaultPolicyClosestThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: closestConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.desktopClosest, testee.agent(forUrl: Constants.url, isDesktop: true, privacyConfig: config))
    }

    func testWhenTabletUaAndDesktopFalseAndDefaultPolicyClosestThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: closestConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.tabletClosest, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenTabletUaAndDesktopTrueAndDefaultPolicyClosestThenFixedMobileAgentUsed() {
        let config = makePrivacyConfig(from: closestConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.tablet, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.desktopClosest, testee.agent(forUrl: Constants.url, isDesktop: true, privacyConfig: config))
    }

    func testWhenDefaultPolicyClosestAndDomainIsOnDefaultListThenDefaultAgentUsed() {
        let config = makePrivacyConfig(from: closestConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobile, testee.agent(forUrl: Constants.ddgDefaultUrl, isDesktop: false, privacyConfig: config))
    }

    func testWhenDefaultPolicyClosestAndDomainIsOnFixedListThenFixedAgentUsed() {
        let config = makePrivacyConfig(from: closestConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobileFixed, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, privacyConfig: config))
    }

    let configWithVersions = """
    {
        "features": {
            "customUserAgent": {
                "state": "enabled",
                "settings": {
                    "defaultPolicy": "ddg",
                    "useUpdatedSafariVersions": true,
                    "safariVersionMappings": {},
                    "omitApplicationSites": [
                        {
                            "domain": "cvs.com",
                            "reason": "Site reports browser not supported"
                        }
                    ],
                    "closestUserAgent": {
                        "versions": ["350", "360"]
                    },
                    "ddgFixedUserAgent": {
                        "versions": ["351", "361"]
                    }
                },
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenAtbDoesNotMatchVersionFromConfigThenDefaultUAIsUsed() {
        let statisticsStore = MockStatisticsStore()
        statisticsStore.atb = "v300-1"
        let config = makePrivacyConfig(from: configWithVersions)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, statistics: statisticsStore, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobile, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenAtbMatchesVersionInClosestUserAgentThenClosestUAIsUsed() {
        let statisticsStore = MockStatisticsStore()
        statisticsStore.atb = "v360-1"
        let config = makePrivacyConfig(from: configWithVersions)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, statistics: statisticsStore, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobileClosest, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenAtbMatchesVersionInDDGFixedUserAgentThenDDGFixedUAIsUsed() {
        let statisticsStore = MockStatisticsStore()
        statisticsStore.atb = "v361-1"
        let config = makePrivacyConfig(from: configWithVersions)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, statistics: statisticsStore, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobileFixed, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenAtbWithoutDayComponentMatchesVersionInDDGFixedUserAgentThenDDGFixedUAIsUsed() {
        let statisticsStore = MockStatisticsStore()
        statisticsStore.atb = "v361"
        let config = makePrivacyConfig(from: configWithVersions)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, statistics: statisticsStore, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.mobileFixed, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenOldWebKitVersionThenDefaultMobileAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.oldWebkitVersionMobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.oldWebkitVersionMobile, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenNewerWebKitVersionThenFixedAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.newWebkitVersionMobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.newWebkitVersionMobile, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    func testWhenSameWebKitVersionThenFixedAgentUsed() {
        let config = makePrivacyConfig(from: ddgFixedConfig)
        let testee = UserAgent(defaultAgent: DefaultAgent.sameWebkitVersionMobile, privacyConfig: config)

        XCTAssertEqual(ExpectedAgent.sameWebkitVersionMobile, testee.agent(forUrl: Constants.url, isDesktop: false, privacyConfig: config))
    }

    let testConfigWithMapping = """
    {
        "features": {
            "customUserAgent": {
                "state": "enabled",
                "settings": {
                    "useUpdatedSafariVersions": true,
                    "safariVersionMappings": {
                        "26": "18_6",
                        "26.0": "18_6",
                        "26.0.1": "18_7"
                    },
                    "omitApplicationSites": [
                        {
                            "domain": "cvs.com",
                            "reason": "Site reports browser not supported"
                        }
                    ]
                },
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenOnIOS26_0_0AndMappingMatchesThenItIsUsed() {
        let config = makePrivacyConfig(from: testConfigWithMapping)
        let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config, deviceVersion: version)

        XCTAssertEqual(ExpectedAgent.mobileMapped2600, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, deviceVersion: version, privacyConfig: config))
    }

    func testWhenOnIOS26_0_1AndMappingMatchesThenItIsUsed() {
        let config = makePrivacyConfig(from: testConfigWithMapping)
        let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config, deviceVersion: version)

        XCTAssertEqual(ExpectedAgent.mobileMapped2601, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, deviceVersion: version, privacyConfig: config))
    }

    func testWhenOnIOS26AndMappingDoesNotMatchThenMostGenericIsUsed() {
        let config = makePrivacyConfig(from: testConfigWithMapping)
        let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1000)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config, deviceVersion: version)

        XCTAssertEqual(ExpectedAgent.mobileMapped2600, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, deviceVersion: version, privacyConfig: config))
    }

    func testWhenOnIOS27AndMappingDoesNotMatchThenItIsIgnored() {
        let config = makePrivacyConfig(from: testConfigWithMapping)
        let version = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config, deviceVersion: version)

        XCTAssertEqual(ExpectedAgent.mobileMappedPost26, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, deviceVersion: version, privacyConfig: config))
    }

    func testWhenNotOnIOS26ThenMappingIsNotUsed() {
        let config = makePrivacyConfig(from: testConfigWithMapping)
        let version = OperatingSystemVersion(majorVersion: 18, minorVersion: 7, patchVersion: 0)
        let testee = UserAgent(defaultAgent: DefaultAgent.mobile, privacyConfig: config, deviceVersion: version)

        XCTAssertEqual(ExpectedAgent.mobileMappedPre26, testee.agent(forUrl: Constants.ddgFixedUrl, isDesktop: false, deviceVersion: version, privacyConfig: config))
    }
}
