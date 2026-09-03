//
//  PerformanceOptimizedPaywallsProviderTests.swift
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
import Subscription
@testable import BrowserServicesKit

final class PerformanceOptimizedPaywallsProviderTests: XCTestCase {

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

    // MARK: - isEnabled

    func testIsEnabledReflectsTheFeatureFlag() {
        XCTAssertTrue(makeProvider(isFeatureEnabled: true).isEnabled)
        XCTAssertFalse(makeProvider(isFeatureEnabled: false).isEnabled)
    }

    // MARK: - Paths

    func testPathsComeFromSettings() {
        // Given
        // The shape shipped in `privacyPro.performanceOptimizedPaywalls.settings`.
        privacyConfig.subfeatureSettings = """
        {
            "entryPoints": {
                "vpn": { "path": "/subscriptions/new/mobile/vpn" },
                "duckai": { "path": "/subscriptions/new/mobile/duckai" },
                "pir": { "path": "/subscriptions/new/mobile/pir" }
            }
        }
        """

        // When
        let paths = makeProvider().paths

        // Then
        XCTAssertEqual(paths, SubscriptionURL.PerformanceOptimizedPaywallPaths(vpn: "/subscriptions/new/mobile/vpn",
                                                                              duckai: "/subscriptions/new/mobile/duckai",
                                                                              pir: "/subscriptions/new/mobile/pir"))
    }

    func testPathsFallBackWhenSettingsAreAbsent() {
        // Given
        privacyConfig.subfeatureSettings = nil

        // When
        let paths = makeProvider().paths

        // Then
        XCTAssertEqual(paths, .default)
    }

    func testEachPathFallsBackIndependently() {
        // Given
        privacyConfig.subfeatureSettings = """
        { "entryPoints": { "duckai": { "path": "/subscriptions/v2/duckai" } } }
        """

        // When
        let paths = makeProvider().paths

        // Then
        XCTAssertEqual(paths.vpn, SubscriptionURL.PerformanceOptimizedPaywallPaths.default.vpn)
        XCTAssertEqual(paths.duckai, "/subscriptions/v2/duckai")
        XCTAssertEqual(paths.pir, SubscriptionURL.PerformanceOptimizedPaywallPaths.default.pir)
    }

    func testPirPathFallsBackWhileTheOthersAreConfigured() {
        // Given
        privacyConfig.subfeatureSettings = """
        {
            "entryPoints": {
                "vpn": { "path": "/subscriptions/v2/vpn" },
                "duckai": { "path": "/subscriptions/v2/duckai" }
            }
        }
        """

        // When
        let paths = makeProvider().paths

        // Then
        XCTAssertEqual(paths.vpn, "/subscriptions/v2/vpn")
        XCTAssertEqual(paths.duckai, "/subscriptions/v2/duckai")
        XCTAssertEqual(paths.pir, SubscriptionURL.PerformanceOptimizedPaywallPaths.default.pir)
    }

    func testPathsFallBackWhenSettingsAreNotValidJSON() {
        // Given
        privacyConfig.subfeatureSettings = "not json"

        // When
        let paths = makeProvider().paths

        // Then
        XCTAssertEqual(paths, .default)
    }

    func testPathsFallBackWhenSettingsCarryNoEntryPoints() {
        // Given
        privacyConfig.subfeatureSettings = "{}"

        // When
        let paths = makeProvider().paths

        // Then
        XCTAssertEqual(paths, .default)
    }

    // MARK: - Helpers

    private func makeProvider(isFeatureEnabled: Bool = true) -> DefaultPerformanceOptimizedPaywallsProvider {
        DefaultPerformanceOptimizedPaywallsProvider(privacyConfigurationManager: privacyConfigurationManager,
                                                    isFeatureEnabled: { isFeatureEnabled })
    }
}
