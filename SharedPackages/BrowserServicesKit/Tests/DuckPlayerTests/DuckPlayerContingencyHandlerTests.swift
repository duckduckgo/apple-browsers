//
//  DuckPlayerContingencyHandlerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import DuckPlayer
import BrowserServicesKitTestsUtils

final class DuckPlayerContingencyHandlerTests: XCTestCase {

    func testShouldDisplayContingencyMessageWhenFeatureDisabledAndLinkExists() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: MockConfig.featureDisabledAndLinkPresent, etag: "a")

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let handler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: manager)
        XCTAssertTrue(handler.shouldDisplayContingencyMessage)
        XCTAssertEqual(handler.learnMoreURL, URL(string: MockConfig.learnMoreURL))
    }

    func testShouldNotDisplayContingencyMessageWhenFeatureEnabledAndLinkExists() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: MockConfig.featureEnabledAndLinkPresent, etag: "a")

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let handler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: manager)
        XCTAssertFalse(handler.shouldDisplayContingencyMessage)
        XCTAssertEqual(handler.learnMoreURL, URL(string: MockConfig.learnMoreURL))
    }

    func testShouldNotDisplayContingencyMessageWhenFeatureEnabled() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: MockConfig.featureEnabledAndLinkAbsent, etag: "a")

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let handler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: manager)
        XCTAssertFalse(handler.shouldDisplayContingencyMessage)
        XCTAssertNil(handler.learnMoreURL)
    }

    func testShouldNotDisplayContingencyMessageWhenLinkDoesNotExist() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: MockConfig.featureDisabledAndLinkAbsent, etag: "a")

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let handler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: manager)
        XCTAssertFalse(handler.shouldDisplayContingencyMessage)
        XCTAssertNil(handler.learnMoreURL)
    }

    func testLearnMoreURLWhenLinkExists() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: MockConfig.featureDisabledAndLinkPresent, etag: "a")

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let handler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: manager)
        XCTAssertEqual(handler.learnMoreURL, URL(string: MockConfig.learnMoreURL))
    }

    func testLearnMoreURLWhenLinkDoesNotExist() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: MockConfig.featureDisabledAndLinkAbsent, etag: "a")

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let handler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: manager)
        XCTAssertNil(handler.learnMoreURL)
    }
}

private struct MockConfig {
    static let learnMoreURL = "https://duckduckgo.com/duckduckgo-help-pages/duck-player/"
    static let featureEnabledAndLinkAbsent =
    """
    {
        "readme": "https://github.com/duckduckgo/privacy-configuration",
        "version": 1722602607085,
        "features": {
            "duckPlayer": {
                "exceptions": [],
                "features": {
                    "pip": {
                        "state": "enabled"
                    },
                    "autoplay": {
                        "state": "disabled"
                    },
                    "openInNewTab": {
                        "state": "disabled"
                    }
                },
                "settings": {
                },
                "state": "enabled",
                "hash": "5ccb9e0379c691ea67bb2e73ba0ac194"
            }
        }
    }
    """.data(using: .utf8)!

    static let featureDisabledAndLinkAbsent =
    """
    {
        "readme": "https://github.com/duckduckgo/privacy-configuration",
        "version": 1722602607085,
        "features": {
            "duckPlayer": {
                "exceptions": [],
                "features": {
                    "pip": {
                        "state": "enabled"
                    },
                    "autoplay": {
                        "state": "disabled"
                    },
                    "openInNewTab": {
                        "state": "disabled"
                    }
                },
                "settings": {
                    "tryDuckPlayerLink": "https://www.youtube.com/watch?v=yKWIA-Pys4c",
                },
                "state": "enabled",
                "hash": "5ccb9e0379c691ea67bb2e73ba0ac194"
            }
        }
    }
    """.data(using: .utf8)!

    static let featureDisabledAndLinkPresent =
    """
    {
        "readme": "https://github.com/duckduckgo/privacy-configuration",
        "version": 1722602607085,
        "features": {
            "duckPlayer": {
                "exceptions": [],
                "features": {
                    "pip": {
                        "state": "enabled"
                    },
                    "autoplay": {
                        "state": "disabled"
                    },
                    "openInNewTab": {
                        "state": "disabled"
                    }
                },
                "settings": {
                    "tryDuckPlayerLink": "https://www.youtube.com/watch?v=yKWIA-Pys4c",
                    "duckPlayerDisabledHelpPageLink": "\(MockConfig.learnMoreURL)"
                },
                "state": "disabled",
                "hash": "5ccb9e0379c691ea67bb2e73ba0ac194"
            }
        }
    }
    """.data(using: .utf8)!

    static let featureEnabledAndLinkPresent =
    """
    {
        "readme": "https://github.com/duckduckgo/privacy-configuration",
        "version": 1722602607085,
        "features": {
            "duckPlayer": {
                "exceptions": [],
                "features": {
                    "pip": {
                        "state": "enabled"
                    },
                    "autoplay": {
                        "state": "disabled"
                    },
                    "openInNewTab": {
                        "state": "disabled"
                    }
                },
                "settings": {
                    "tryDuckPlayerLink": "https://www.youtube.com/watch?v=yKWIA-Pys4c",
                    "duckPlayerDisabledHelpPageLink": "\(MockConfig.learnMoreURL)"
                },
                "state": "enabled",
                "hash": "5ccb9e0379c691ea67bb2e73ba0ac194"
            }
        }
    }
    """.data(using: .utf8)!
}

import Combine

class MockPrivacyConfigurationManager: PrivacyConfigurationManaging {
    var currentConfig: Data = .init()
    var updatesSubject = PassthroughSubject<Void, Never>()
    let updatesPublisher: AnyPublisher<Void, Never>
    var privacyConfig: PrivacyConfiguration
    let internalUserDecider: InternalUserDecider
    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }

    init(privacyConfig: PrivacyConfiguration, internalUserDecider: InternalUserDecider) {
        self.updatesPublisher = updatesSubject.eraseToAnyPublisher()
        self.privacyConfig = privacyConfig
        self.internalUserDecider = internalUserDecider
    }
}

private final class MockEmbeddedDataProvider: EmbeddedDataProvider {
    var embeddedDataEtag: String

    var embeddedData: Data

    init(data: Data, etag: String) {
        embeddedData = data
        embeddedDataEtag = etag
    }
}

private final class MockDomainsProtectionStore: DomainsProtectionStore {
    var unprotectedDomains = Set<String>()

    func disableProtection(forDomain domain: String) {
        unprotectedDomains.insert(domain)
    }

    func enableProtection(forDomain domain: String) {
        unprotectedDomains.remove(domain)
    }
}

private final class MockInternalUserStoring: InternalUserStoring {
    var isInternalUser: Bool = false
}

extension DefaultInternalUserDecider {
    fileprivate convenience init(mockedStore: MockInternalUserStoring = MockInternalUserStoring()) {
        self.init(store: mockedStore)
    }
}
