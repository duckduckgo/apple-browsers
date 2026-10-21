//
//  PopupBlockingConfigurationTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PrivacyConfigTestsUtils
@testable import PrivacyConfig

final class PopupBlockingConfigurationTests: XCTestCase {

    var mockEmbeddedData: MockEmbeddedDataProvider!
    var privacyConfigManager: PrivacyConfigurationManager!

    @MainActor
    override func tearDown() {
        mockEmbeddedData = nil
        privacyConfigManager = nil
        // Clear static cache to prevent test pollution
        DefaultPopupBlockingConfiguration.clearCache()
        super.tearDown()
    }

    // MARK: - Threshold Tests

    func testWhenThresholdIsDouble_ThenReturnsValue() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "userInitiatedPopupThreshold": 10.5
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // THEN
        XCTAssertEqual(popupConfig.userInitiatedPopupThreshold, 10.5)
    }

    func testWhenThresholdIsInt_ThenReturnsValue() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "userInitiatedPopupThreshold": 8
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // THEN
        XCTAssertEqual(popupConfig.userInitiatedPopupThreshold, 8.0)
    }

    func testWhenThresholdIsString_ThenParsesValue() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "userInitiatedPopupThreshold": "7.5"
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // THEN
        XCTAssertEqual(popupConfig.userInitiatedPopupThreshold, 7.5)
    }

    func testWhenThresholdIsNotSet_ThenReturnsDefault() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {}
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // THEN
        XCTAssertEqual(popupConfig.userInitiatedPopupThreshold, 6.0)
    }

    func testWhenThresholdIsNegative_ThenReturnsDefault() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "userInitiatedPopupThreshold": -5.0
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)
        popupConfig.assertionHandler = { _, _ in }

        // THEN
        XCTAssertEqual(popupConfig.userInitiatedPopupThreshold, 6.0)
    }

    func testWhenThresholdIsZero_ThenReturnsDefault() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "userInitiatedPopupThreshold": 0
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)
        popupConfig.assertionHandler = { _, _ in }

        // THEN
        XCTAssertEqual(popupConfig.userInitiatedPopupThreshold, 6.0)
    }

    // MARK: - Allowlist Tests

    @MainActor
    func testWhenAllowlistIsProvided_ThenReturnsSet() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "allowlist": ["example.com", "test.org", "sample.net"]
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // THEN
        XCTAssertEqual(popupConfig.allowlist, Set(["example.com", "test.org", "sample.net"]))
    }

    @MainActor
    func testWhenAllowlistIsEmpty_ThenReturnsEmptySet() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "allowlist": []
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // THEN
        XCTAssertTrue(popupConfig.allowlist.isEmpty)
    }

    @MainActor
    func testWhenAllowlistIsNotSet_ThenReturnsEmptySet() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {}
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // THEN
        XCTAssertTrue(popupConfig.allowlist.isEmpty)
    }

    // MARK: - Caching Tests

    @MainActor
    func testWhenAllowlistAccessedMultipleTimes_ThenCacheIsUsed() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "allowlist": ["example.com", "test.org"]
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "test-etag-1")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // WHEN - Access allowlist multiple times
        let firstAccess = popupConfig.allowlist
        let secondAccess = popupConfig.allowlist
        let thirdAccess = popupConfig.allowlist

        // THEN - All accesses return the same cached Set instance
        XCTAssertEqual(firstAccess, Set(["example.com", "test.org"]))
        XCTAssertEqual(secondAccess, Set(["example.com", "test.org"]))
        XCTAssertEqual(thirdAccess, Set(["example.com", "test.org"]))
    }

    @MainActor
    func testWhenConfigChanges_ThenCacheIsInvalidated() {
        // GIVEN - Initial config
        let initialConfig = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "allowlist": ["example.com"]
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: initialConfig, etag: "etag-1")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: nil,
            fetchedData: nil,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // WHEN - Access initial allowlist
        let initialAllowlist = popupConfig.allowlist
        XCTAssertEqual(initialAllowlist, Set(["example.com"]))

        // Update config with different etag and allowlist
        let updatedConfig = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "allowlist": ["newsite.com", "anothersite.org"]
                    }
                }
            }
        }
        """.data(using: .utf8)!

        privacyConfigManager.reload(etag: "etag-2", data: updatedConfig)

        // THEN - Cache is invalidated and new allowlist is returned
        let updatedAllowlist = popupConfig.allowlist
        XCTAssertEqual(updatedAllowlist, Set(["newsite.com", "anothersite.org"]))
        XCTAssertNotEqual(updatedAllowlist, initialAllowlist)
    }

    @MainActor
    func testWhenConfigReloadsWithSameEtag_ThenCacheIsReused() {
        // GIVEN
        let config = """
        {
            "features": {
                "popupBlocking": {
                    "state": "enabled",
                    "settings": {
                        "allowlist": ["example.com"]
                    }
                }
            }
        }
        """.data(using: .utf8)!

        mockEmbeddedData = MockEmbeddedDataProvider(data: config, etag: "same-etag")
        privacyConfigManager = PrivacyConfigurationManager(
            fetchedETag: "same-etag",
            fetchedData: config,
            embeddedDataProvider: mockEmbeddedData,
            localProtection: MockDomainsProtectionStore(),
            internalUserDecider: MockInternalUserDecider()
        )

        let popupConfig = DefaultPopupBlockingConfiguration(privacyConfigurationManager: privacyConfigManager)

        // WHEN - Access allowlist, reload with same etag, access again
        let beforeReload = popupConfig.allowlist
        privacyConfigManager.reload(etag: "same-etag", data: config)
        let afterReload = popupConfig.allowlist

        // THEN - Cache is still valid and returns same set
        XCTAssertEqual(beforeReload, Set(["example.com"]))
        XCTAssertEqual(afterReload, Set(["example.com"]))
    }
}
