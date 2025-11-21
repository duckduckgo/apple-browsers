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
@testable import BrowserServicesKit

final class PopupBlockingConfigurationTests: XCTestCase {

    var mockEmbeddedData: MockEmbeddedDataProvider!
    var privacyConfigManager: PrivacyConfigurationManager!

    override func tearDown() {
        mockEmbeddedData = nil
        privacyConfigManager = nil
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
}
