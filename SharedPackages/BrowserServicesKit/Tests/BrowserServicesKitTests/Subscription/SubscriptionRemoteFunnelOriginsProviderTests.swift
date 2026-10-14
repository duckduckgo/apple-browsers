//
//  SubscriptionRemoteFunnelOriginsProviderTests.swift
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

final class SubscriptionRemoteFunnelOriginsProviderTests: XCTestCase {

    private static let appOrigin = "funnel_appsettings_test"

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

    // MARK: - allowlistedOrigins

    func testAllowlistedOriginsComeFromSettingsWhenEnabled() {
        // Given
        setSubfeatureEnabled(true)
        privacyConfig.subfeatureSettings = #"{ "funnelOriginAllowlist": ["funnel_web_a", "funnel_web_b"] }"#

        // Then
        XCTAssertEqual(makeProvider().allowlistedOrigins, ["funnel_web_a", "funnel_web_b"])
    }

    func testAllowlistedOriginsAreEmptyWhenSubfeatureIsDisabled() {
        // Given
        setSubfeatureEnabled(false)
        privacyConfig.subfeatureSettings = #"{ "funnelOriginAllowlist": ["funnel_web_a"] }"#

        // Then
        XCTAssertEqual(makeProvider().allowlistedOrigins, [])
    }

    func testAllowlistedOriginsAreEmptyWhenSettingsAreMissing() {
        // Given
        setSubfeatureEnabled(true)
        privacyConfig.subfeatureSettings = nil

        // Then
        XCTAssertEqual(makeProvider().allowlistedOrigins, [])
    }

    func testAllowlistedOriginsReflectConfigChangesWhileRunning() {
        // Given
        setSubfeatureEnabled(true)
        privacyConfig.subfeatureSettings = #"{ "funnelOriginAllowlist": [] }"#
        let provider = makeProvider()
        XCTAssertEqual(provider.allowlistedOrigins, [])

        // When
        privacyConfig.subfeatureSettings = #"{ "funnelOriginAllowlist": ["funnel_web_a"] }"#

        // Then
        XCTAssertEqual(provider.allowlistedOrigins, ["funnel_web_a"])

        // When
        setSubfeatureEnabled(false)

        // Then
        XCTAssertEqual(provider.allowlistedOrigins, [])
    }

    // MARK: - resolveOrigin

    func testResolveOriginIsNilWhenOriginIsMissing() {
        XCTAssertNil(resolveOrigin(nil))
        XCTAssertNil(resolveOrigin(""))
    }

    func testResolveOriginReturnsAppForAppOrigin() {
        // Given
        setSubfeatureEnabled(false)

        // Then
        XCTAssertEqual(resolveOrigin(Self.appOrigin), .app(Self.appOrigin))
    }

    func testResolveOriginReturnsRemoteForAllowlistedOrigin() {
        // Given
        setSubfeatureEnabled(true)
        privacyConfig.subfeatureSettings = #"{ "funnelOriginAllowlist": ["funnel_web_a"] }"#

        // Then
        XCTAssertEqual(resolveOrigin("funnel_web_a"), .remote("funnel_web_a"))
    }

    func testResolveOriginReturnsUnknownForOtherOrigins() {
        // Given
        setSubfeatureEnabled(true)
        privacyConfig.subfeatureSettings = #"{ "funnelOriginAllowlist": ["funnel_web_a"] }"#

        // Then
        XCTAssertEqual(resolveOrigin("funnel_web_b"), .unknown(reportableOrigin: "funnel_web_b"))
    }

    func testResolveOriginReportsUnknownOriginOnlyWhenItLooksLikeAFunnelOrigin() {
        // Given
        setSubfeatureEnabled(false)

        // Then
        XCTAssertEqual(resolveOrigin("Funnel_Web_A"), .unknown(reportableOrigin: "funnel_web_a"))
        XCTAssertEqual(resolveOrigin("funnel_" + String(repeating: "a", count: 64)),
                       .unknown(reportableOrigin: "funnel_" + String(repeating: "a", count: 64)))
        XCTAssertEqual(resolveOrigin("funnel_" + String(repeating: "a", count: 65)), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolveOrigin("not_a_funnel"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolveOrigin("funnel_"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolveOrigin("funnel_a-b"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolveOrigin("funnel_a@example.com"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolveOrigin("https://example.com/funnel_a"), .unknown(reportableOrigin: nil))
    }

    func testResolveOriginReturnsUnknownForAllowlistedOriginWhenSubfeatureIsDisabled() {
        // Given
        setSubfeatureEnabled(false)
        privacyConfig.subfeatureSettings = #"{ "funnelOriginAllowlist": ["funnel_web_a"] }"#

        // Then
        XCTAssertEqual(resolveOrigin("funnel_web_a"), .unknown(reportableOrigin: "funnel_web_a"))
    }

    // MARK: - Helpers

    private func makeProvider() -> DefaultSubscriptionRemoteFunnelOriginsProvider {
        DefaultSubscriptionRemoteFunnelOriginsProvider(privacyConfigurationManager: privacyConfigurationManager)
    }

    private func resolveOrigin(_ origin: String?) -> ResolvedFunnelOrigin? {
        makeProvider().resolveOrigin(origin, isAppOrigin: { $0 == Self.appOrigin })
    }

    private func setSubfeatureEnabled(_ isEnabled: Bool) {
        privacyConfig.isSubfeatureEnabledCheck = { subfeature, _ in
            subfeature.rawValue == PrivacyProSubfeature.subscriptionRemoteFunnelOrigins.rawValue && isEnabled
        }
    }
}
