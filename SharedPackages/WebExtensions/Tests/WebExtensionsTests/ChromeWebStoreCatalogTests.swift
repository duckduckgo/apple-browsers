//
//  ChromeWebStoreCatalogTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import WebExtensions

@MainActor
final class ChromeWebStoreCatalogTests: XCTestCase {
    private let identifier = String(repeating: "a", count: 32)
    private let internalIdentifier = String(repeating: "b", count: 32)
    private let config = MockPrivacyConfiguration()
    private let internalUser = MockInternalUserDecider()

    private func makeCatalog() throws -> ChromeWebStoreCatalog {
        config.isFeatureEnabledCheck = { _, _ in true }
        config.isSubfeatureEnabledCheck = { _, _ in true }
        try setCatalog(["catalog": [["id": identifier]], "catalogInternal": [["id": internalIdentifier]]])
        return ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config, internalUserDecider: internalUser))
    }

    private func setCatalog(_ settings: [String: Any]) throws {
        config.subfeatureSettings = String(data: try JSONSerialization.data(withJSONObject: settings), encoding: .utf8)
    }

    func testPublicCatalogRejectsUnknownAndInvalidIDs() throws {
        let catalog = try makeCatalog()
        XCTAssertTrue(catalog.contains(identifier))
        XCTAssertFalse(catalog.contains(internalIdentifier))
        XCTAssertFalse(catalog.contains("invalid"))
    }

    func testInternalCatalogReplacesPublicCatalogAndFallsBackWhenAbsent() throws {
        let catalog = try makeCatalog()
        internalUser.isInternalUser = true
        XCTAssertTrue(catalog.contains(internalIdentifier))
        XCTAssertFalse(catalog.contains(identifier))
        try setCatalog(["catalog": [["id": identifier]]])
        XCTAssertTrue(catalog.contains(identifier))
        try setCatalog(["catalog": [["id": identifier]], "catalogInternal": []])
        XCTAssertFalse(catalog.contains(identifier))
    }

    func testRemoteGatesAreReevaluatedOnEachRequest() throws {
        let catalog = try makeCatalog()
        XCTAssertTrue(catalog.contains(identifier))

        config.isFeatureEnabledCheck = { feature, _ in feature != .chromeWebstorePatching }
        XCTAssertFalse(catalog.contains(identifier), PrivacyFeature.chromeWebstorePatching.rawValue)
        config.isFeatureEnabledCheck = { _, _ in true }
        XCTAssertTrue(catalog.contains(identifier))

        for disabledSubfeature in [ExtensionManagementSubfeature.isLaunchedExtensions, .curatedExtensions] {
            config.isSubfeatureEnabledCheck = { subfeature, _ in
                (subfeature as? ExtensionManagementSubfeature) != disabledSubfeature
            }
            XCTAssertFalse(catalog.contains(identifier), disabledSubfeature.rawValue)
            config.isSubfeatureEnabledCheck = { _, _ in true }
            XCTAssertTrue(catalog.contains(identifier), disabledSubfeature.rawValue)
        }
    }

    func testDisablingSiteProtectionsKeepsCuratedExtensionAvailable() throws {
        let protectionStore = MockDomainsProtectionStore()
        let config = try makeConfiguration(localProtection: protectionStore)
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config))
        XCTAssertTrue(catalog.contains(identifier))

        protectionStore.disableProtection(forDomain: ChromeWebStoreURL.host)
        XCTAssertFalse(config.isFeature(.chromeWebstorePatching, enabledForDomain: ChromeWebStoreURL.host))
        XCTAssertTrue(catalog.contains(identifier))

        protectionStore.enableProtection(forDomain: ChromeWebStoreURL.host)
        XCTAssertTrue(catalog.contains(identifier))
    }

    func testTemporarilyUnprotectedSiteKeepsCuratedExtensionAvailable() throws {
        let config = try makeConfiguration(unprotectedTemporary: [ChromeWebStoreURL.host])
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config))
        XCTAssertFalse(config.isFeature(.chromeWebstorePatching, enabledForDomain: ChromeWebStoreURL.host))
        XCTAssertTrue(catalog.contains(identifier))
    }

    func testExplicitFeatureExceptionStillRejectsCuratedExtension() throws {
        let protectionStore = MockDomainsProtectionStore()
        let config = try makeConfiguration(localProtection: protectionStore, exceptions: [ChromeWebStoreURL.host])
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config))
        XCTAssertFalse(catalog.contains(identifier))

        protectionStore.disableProtection(forDomain: ChromeWebStoreURL.host)
        XCTAssertFalse(catalog.contains(identifier))
    }

    private func makeConfiguration(localProtection: MockDomainsProtectionStore = MockDomainsProtectionStore(),
                                   exceptions: [String] = [],
                                   unprotectedTemporary: [String] = []) throws -> AppPrivacyConfiguration {
        let json: [String: Any] = [
            "features": [
                "chromeWebstorePatching": [
                    "state": "enabled",
                    "exceptions": exceptions.map { ["domain": $0] }
                ],
                "extensionManagement": [
                    "state": "enabled",
                    "features": [
                        "isLaunchedExtensions": [
                            "state": "enabled"
                        ],
                        "curatedExtensions": [
                            "state": "enabled",
                            "settings": ["catalog": [["id": identifier]]]
                        ]
                    ]
                ]
            ],
            "unprotectedTemporary": unprotectedTemporary.map { ["domain": $0] }
        ]
        let data = try PrivacyConfigurationData(data: JSONSerialization.data(withJSONObject: json))
        return AppPrivacyConfiguration(data: data, identifier: "test", localProtection: localProtection,
                                       internalUserDecider: internalUser)
    }

    func testHiddenDisabledAndRemovedEntriesAreRejected() throws {
        let catalog = try makeCatalog()
        for key in ["hiddenExtensionIds", "disabledExtensionIds"] {
            config.featureSettings = [key: [identifier]]
            XCTAssertFalse(catalog.contains(identifier))
        }
        config.featureSettings = [:]
        try setCatalog(["catalog": []])
        XCTAssertFalse(catalog.contains(identifier))
        config.subfeatureSettings = "{invalid"
        XCTAssertFalse(catalog.contains(identifier))
    }

    func testDownloadURLMatchesScriptContractRegardlessOfQueryOrder() throws {
        let url = try ChromeWebStoreURL.downloadURL(for: identifier)
        XCTAssertTrue(ChromeWebStoreURL.isValidDownloadURL(url, for: identifier))
        var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.queryItems = components.queryItems?.reversed()
        XCTAssertTrue(ChromeWebStoreURL.isValidDownloadURL(try XCTUnwrap(components.url), for: identifier))
        XCTAssertFalse(ChromeWebStoreURL.isValidDownloadURL(url, for: internalIdentifier))
    }

    func testUntrustedDownloadURLsAreRejected() throws {
        let url = try ChromeWebStoreURL.downloadURL(for: identifier)
        for transform: (inout URLComponents) -> Void in [
            { $0.scheme = "http" }, { $0.host = "evil.example" }, { $0.host = "clients2.google.com.evil.example" },
            { $0.path = "/other" }, { $0.user = "user" }, { $0.port = 8443 }, { $0.fragment = "fragment" },
            { $0.queryItems?.append(URLQueryItem(name: "response", value: "redirect")) },
            { $0.queryItems?.append(URLQueryItem(name: "extra", value: "value")) }
        ] {
            var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            transform(&components)
            XCTAssertFalse(ChromeWebStoreURL.isValidDownloadURL(try XCTUnwrap(components.url), for: identifier))
        }
    }

    func testExtensionIDValidation() throws {
        XCTAssertTrue(ChromeWebStoreURL.isValidExtensionID("abcdefghijklmnopabcdefghijklmnop"))
        for identifier in ["", String(repeating: "a", count: 31), String(repeating: "a", count: 33),
                           String(repeating: "A", count: 32), String(repeating: "q", count: 32), String(repeating: "é", count: 16)] {
            XCTAssertFalse(ChromeWebStoreURL.isValidExtensionID(identifier))
            XCTAssertThrowsError(try ChromeWebStoreURL.downloadURL(for: identifier))
        }
    }

    func testRedirectsAreRestrictedToGoogleDownloadHosts() throws {
        for host in ["clients2.google.com", "clients2.googleusercontent.com"] {
            XCTAssertTrue(ChromeWebStoreURL.isAllowedDownloadDestination(try XCTUnwrap(URL(string: "https://\(host)/package"))))
        }
        for url in ["http://clients2.google.com/package", "https://evil.example/package",
                    "https://clients2.googleusercontent.com.evil.example/package", "https://user@clients2.google.com/package"] {
            XCTAssertFalse(ChromeWebStoreURL.isAllowedDownloadDestination(try XCTUnwrap(URL(string: url))))
        }
    }
}
