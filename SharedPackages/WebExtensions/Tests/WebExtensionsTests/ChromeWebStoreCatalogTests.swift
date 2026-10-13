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
    private let otherIdentifier = String(repeating: "b", count: 32)
    private let thirdIdentifier = String(repeating: "c", count: 32)
    private let internalUser = MockInternalUserDecider()

    // MARK: - Catalog contents

    func testCatalogListsEnabledExtensionsByOrderWithUnorderedLast() throws {
        let catalog = try makeCatalog(extensions: [
            "bitwarden": entry(identifier, order: 2),
            "onePassword": entry(otherIdentifier, order: 1),
            "lastPass": entry(thirdIdentifier)
        ])
        XCTAssertEqual(catalog.extensionIDs, [otherIdentifier, identifier, thirdIdentifier])
        XCTAssertTrue(catalog.contains(identifier))
        XCTAssertFalse(catalog.contains("invalid"))
    }

    func testEachExtensionIsGatedByItsOwnSubfeatureState() throws {
        let extensions = [
            "bitwarden": entry(identifier, order: 1),
            "onePassword": entry(otherIdentifier, state: "internal", order: 2),
            "lastPass": entry(thirdIdentifier, state: "disabled", order: 3)
        ]
        XCTAssertEqual(try makeCatalog(extensions: extensions).extensionIDs, [identifier])

        internalUser.isInternalUser = true
        XCTAssertEqual(try makeCatalog(extensions: extensions).extensionIDs, [identifier, otherIdentifier])
    }

    func testUnknownSubfeaturesAndMalformedEntriesAreIgnored() throws {
        let catalog = try makeCatalog(extensions: [
            "bitwarden": entry(identifier),
            "onePassword": ["state": "enabled", "settings": ["name": "no id"]],
            "lastPass": entry("invalid"),
            "someFutureExtension": entry(otherIdentifier)
        ])
        XCTAssertEqual(catalog.extensionIDs, [identifier])
    }

    func testHiddenAndDisabledExtensionsAreExcluded() throws {
        for key in ["hiddenExtensionIds", "disabledExtensionIds"] {
            let catalog = try makeCatalog(extensions: ["bitwarden": entry(identifier), "onePassword": entry(otherIdentifier)],
                                          managementSettings: [key: [identifier]])
            XCTAssertEqual(catalog.extensionIDs, [otherIdentifier], key)
        }
    }

    // MARK: - Remote gates

    func testParentFeaturesGateTheWholeCatalog() throws {
        let extensions = ["bitwarden": entry(identifier)]
        XCTAssertEqual(try makeCatalog(extensions: extensions, catalogState: "disabled").extensionIDs, [])
        XCTAssertEqual(try makeCatalog(extensions: extensions, webstoreState: "disabled").extensionIDs, [])
        XCTAssertEqual(try makeCatalog(extensions: extensions, launchedState: "disabled").extensionIDs, [])
        XCTAssertEqual(try makeCatalog(extensions: extensions).extensionIDs, [identifier])
    }

    func testConfigurationUpdatesApplyToTheNextRequest() throws {
        let manager = MockPrivacyConfigurationManager(
            privacyConfig: try makeConfiguration(extensions: ["bitwarden": entry(identifier)]),
            internalUserDecider: internalUser
        )
        let catalog = ChromeWebStoreCatalog(configurationManager: manager)
        XCTAssertEqual(catalog.extensionIDs, [identifier])

        manager.privacyConfig = try makeConfiguration(extensions: [
            "bitwarden": entry(identifier, state: "disabled"),
            "onePassword": entry(otherIdentifier)
        ])
        XCTAssertEqual(catalog.extensionIDs, [otherIdentifier])
        XCTAssertFalse(catalog.contains(identifier))
    }

    func testDisablingSiteProtectionsKeepsCatalogExtensionAvailable() throws {
        let protectionStore = MockDomainsProtectionStore()
        let config = try makeConfiguration(extensions: ["bitwarden": entry(identifier)], localProtection: protectionStore)
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config))
        XCTAssertTrue(catalog.contains(identifier))

        protectionStore.disableProtection(forDomain: ChromeWebStoreURL.host)
        XCTAssertFalse(config.isFeature(.chromeWebstorePatching, enabledForDomain: ChromeWebStoreURL.host))
        XCTAssertTrue(catalog.contains(identifier))

        protectionStore.enableProtection(forDomain: ChromeWebStoreURL.host)
        XCTAssertTrue(catalog.contains(identifier))
    }

    func testTemporarilyUnprotectedSiteKeepsCatalogExtensionAvailable() throws {
        let config = try makeConfiguration(extensions: ["bitwarden": entry(identifier)],
                                           unprotectedTemporary: [ChromeWebStoreURL.host])
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config))
        XCTAssertFalse(config.isFeature(.chromeWebstorePatching, enabledForDomain: ChromeWebStoreURL.host))
        XCTAssertTrue(catalog.contains(identifier))
    }

    func testExplicitFeatureExceptionStillRejectsCatalogExtension() throws {
        let protectionStore = MockDomainsProtectionStore()
        let config = try makeConfiguration(extensions: ["bitwarden": entry(identifier)],
                                           localProtection: protectionStore, exceptions: [ChromeWebStoreURL.host])
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config))
        XCTAssertFalse(catalog.contains(identifier))

        protectionStore.disableProtection(forDomain: ChromeWebStoreURL.host)
        XCTAssertFalse(catalog.contains(identifier))
    }

    // MARK: - Helpers

    private func entry(_ id: String, state: String = "enabled", order: Int? = nil) -> [String: Any] {
        var settings: [String: Any] = ["id": id, "name": "Extension"]
        settings["order"] = order
        return ["state": state, "settings": settings]
    }

    private func makeCatalog(extensions: [String: [String: Any]],
                             catalogState: String = "enabled",
                             webstoreState: String = "enabled",
                             launchedState: String = "enabled",
                             managementSettings: [String: Any] = [:]) throws -> ChromeWebStoreCatalog {
        let config = try makeConfiguration(extensions: extensions, catalogState: catalogState, webstoreState: webstoreState,
                                           launchedState: launchedState, managementSettings: managementSettings)
        return ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: config,
                                                                                           internalUserDecider: internalUser))
    }

    // swiftlint:disable:next function_parameter_count
    private func makeConfiguration(extensions: [String: [String: Any]],
                                   catalogState: String = "enabled",
                                   webstoreState: String = "enabled",
                                   launchedState: String = "enabled",
                                   managementSettings: [String: Any] = [:],
                                   localProtection: MockDomainsProtectionStore = MockDomainsProtectionStore(),
                                   exceptions: [String] = [],
                                   unprotectedTemporary: [String] = []) throws -> AppPrivacyConfiguration {
        let json: [String: Any] = [
            "features": [
                "chromeWebstorePatching": [
                    "state": webstoreState,
                    "exceptions": exceptions.map { ["domain": $0] }
                ],
                "extensionManagement": [
                    "state": "enabled",
                    "settings": managementSettings,
                    "features": [
                        "isLaunchedExtensions": ["state": launchedState]
                    ]
                ],
                "extensionsCatalog": [
                    "state": catalogState,
                    "features": extensions
                ]
            ],
            "unprotectedTemporary": unprotectedTemporary.map { ["domain": $0] }
        ]
        let data = try PrivacyConfigurationData(data: JSONSerialization.data(withJSONObject: json))
        return AppPrivacyConfiguration(data: data, identifier: "test", localProtection: localProtection,
                                       internalUserDecider: internalUser)
    }

    // MARK: - Store URLs

    func testDownloadURLMatchesScriptContractRegardlessOfQueryOrder() throws {
        let url = try ChromeWebStoreURL.downloadURL(for: identifier)
        XCTAssertTrue(ChromeWebStoreURL.isValidDownloadURL(url, for: identifier))
        var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.queryItems = components.queryItems?.reversed()
        XCTAssertTrue(ChromeWebStoreURL.isValidDownloadURL(try XCTUnwrap(components.url), for: identifier))
        XCTAssertFalse(ChromeWebStoreURL.isValidDownloadURL(url, for: otherIdentifier))
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
