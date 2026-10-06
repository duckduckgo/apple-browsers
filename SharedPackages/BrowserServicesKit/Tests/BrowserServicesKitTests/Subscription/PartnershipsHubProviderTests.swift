//
//  PartnershipsHubProviderTests.swift
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

import XCTest
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import BrowserServicesKit

final class PartnershipsHubProviderTests: XCTestCase {

    private static let fallbackURL = URL(string: "https://duckduckgo.com/partner-benefits")!

    private var privacyConfig: MockPrivacyConfiguration!
    private var privacyConfigurationManager: MockPrivacyConfigurationManager!

    override func setUp() {
        super.setUp()
        privacyConfig = MockPrivacyConfiguration()
        privacyConfigurationManager = MockPrivacyConfigurationManager(
            privacyConfig: privacyConfig,
            internalUserDecider: DefaultInternalUserDecider(store: MockInternalUserStoring())
        )
    }

    override func tearDown() {
        privacyConfig = nil
        privacyConfigurationManager = nil
        super.tearDown()
    }

    // MARK: - isEntryPointEnabled

    func testIsEntryPointEnabledReflectsTheFeatureFlag() {
        XCTAssertTrue(makeProvider(isFeatureEnabled: true).isEntryPointEnabled)
        XCTAssertFalse(makeProvider(isFeatureEnabled: false).isEntryPointEnabled)
    }

    func testIsEntryPointEnabledIgnoresTheSettings() {
        // Given
        // A hub URL alone must not switch the entry point on: the flag is the only gate.
        privacyConfig.subfeatureSettings = #"{ "url": "https://example.com/hub" }"#

        // Then
        XCTAssertFalse(makeProvider(isFeatureEnabled: false).isEntryPointEnabled)
    }

    // MARK: - hubURL

    func testHubURLComesFromSettings() {
        // Given
        // The shape shipped in `privacyPro.partnershipsHub.settings`, shared with Android and Windows.
        privacyConfig.subfeatureSettings = #"{ "url": "https://example.com/hub" }"#

        // When
        let url = makeProvider().hubURL

        // Then
        XCTAssertEqual(url, URL(string: "https://example.com/hub"))
    }

    func testHubURLFallsBackWhenSettingsAreAbsent() {
        // Given
        privacyConfig.subfeatureSettings = nil

        // Then
        XCTAssertEqual(makeProvider().hubURL, Self.fallbackURL)
    }

    func testHubURLFallsBackWhenSettingsCarryNoURL() {
        // Given
        privacyConfig.subfeatureSettings = #"{ "showNewPill": false }"#

        // Then
        XCTAssertEqual(makeProvider().hubURL, Self.fallbackURL)
    }

    func testHubURLFallsBackWhenSettingsAreNotValidJSON() {
        // Given
        privacyConfig.subfeatureSettings = "not json"

        // Then
        XCTAssertEqual(makeProvider().hubURL, Self.fallbackURL)
    }

    /// Call sites navigate to `hubURL` directly, so anything that is not an absolute https URL has to
    /// fall back rather than reach them.
    func testHubURLFallsBackForEveryValueThatIsNotAbsoluteHTTPS() {
        let unusableValues = [
            "",
            "   ",
            "http://example.com/hub",
            "example.com/hub",
            "/partner-benefits",
            "ftp://example.com/hub",
            "javascript:alert(1)",
            "https://",
            "not a url at all"
        ]

        for value in unusableValues {
            // Given
            privacyConfig.subfeatureSettings = "{ \"url\": \"\(value)\" }"

            // Then
            XCTAssertEqual(makeProvider().hubURL, Self.fallbackURL, "Expected a fallback for \"\(value)\"")
        }
    }

    func testHubURLUsesTheFallbackCurrentAtReadTime() {
        // Given
        // The fallback follows the subscription environment, which an internal user can change while
        // the app is running.
        var staging = false
        let provider = DefaultPartnershipsHubProvider(
            privacyConfigurationManager: privacyConfigurationManager,
            featureFlagger: MockPartnershipsHubFeatureFlagger(isEnabled: true),
            fallbackURL: { staging ? URL(string: "https://staging.example.com/hub")! : Self.fallbackURL }
        )
        privacyConfig.subfeatureSettings = nil

        // When
        let productionURL = provider.hubURL
        staging = true
        let stagingURL = provider.hubURL

        // Then
        XCTAssertEqual(productionURL, Self.fallbackURL)
        XCTAssertEqual(stagingURL, URL(string: "https://staging.example.com/hub"))
    }

    // MARK: - showsNewBadge

    func testShowsNewBadgeIsOnWhenSettingsAreAbsent() {
        // Given
        privacyConfig.subfeatureSettings = nil

        // Then
        XCTAssertTrue(makeProvider().showsNewBadge)
    }

    func testShowsNewBadgeIsOnWhenSettingsCarryNoToggle() {
        // Given
        privacyConfig.subfeatureSettings = #"{ "url": "https://example.com/hub" }"#

        // Then
        XCTAssertTrue(makeProvider().showsNewBadge)
    }

    func testShowsNewBadgeIsOffWhenSettingsTurnItOff() {
        // Given
        privacyConfig.subfeatureSettings = #"{ "url": "https://example.com/hub", "showNewPill": false }"#

        // Then
        XCTAssertFalse(makeProvider().showsNewBadge)
    }

    // MARK: - Helpers

    private func makeProvider(isFeatureEnabled: Bool = true) -> DefaultPartnershipsHubProvider {
        DefaultPartnershipsHubProvider(privacyConfigurationManager: privacyConfigurationManager,
                                       featureFlagger: MockPartnershipsHubFeatureFlagger(isEnabled: isFeatureEnabled),
                                       fallbackURL: { Self.fallbackURL })
    }
}

private struct MockPartnershipsHubFeatureFlagger: PartnershipsHubFeatureFlagging {
    let isPartnershipsHubEnabled: Bool

    init(isEnabled: Bool) {
        isPartnershipsHubEnabled = isEnabled
    }
}
