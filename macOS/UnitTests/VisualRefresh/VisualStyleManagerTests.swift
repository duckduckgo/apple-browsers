//
//  VisualStyleManagerTests.swift
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
import Combine
import BrowserServicesKit
import FeatureFlags
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Tests

class VisualStyleManagerTests: XCTestCase {

    private var mockInternalUserDecider: MockInternalUserDecider!
    private var mockLocalOverrides: MockFeatureFlagLocalOverriding!
    private var mockFeatureFlagger: MockFeatureFlagger!
    var visualStyleManager: VisualStyleManager!

    override func setUp() {
        super.setUp()
        mockInternalUserDecider = MockInternalUserDecider()
        mockLocalOverrides = MockFeatureFlagLocalOverriding()
        mockFeatureFlagger = MockFeatureFlagger(internalUserDecider: mockInternalUserDecider)
        mockFeatureFlagger.localOverrides = mockLocalOverrides

        visualStyleManager = VisualStyleManager(
            featureFlagger: mockFeatureFlagger,
            internalUserDecider: mockInternalUserDecider
        )
    }

    override func tearDown() {
        mockInternalUserDecider = nil
        mockLocalOverrides = nil
        mockFeatureFlagger = nil
        visualStyleManager = nil
        super.tearDown()
    }

    // MARK: - Non-Internal User Tests

    func testNonInternalUser_FeatureDisabled_ReturnsLegacyStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatures = []

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Should return legacy corner radius")
        XCTAssertEqual(style.fireButtonSize, 28.0, "Should return legacy fire button size")
        XCTAssertFalse(style.areNavigationBarCornersRound, "Should not have round navigation bar corners")
        XCTAssertFalse(style.addToolbarShadow, "Should not add toolbar shadow")
    }

    func testNonInternalUser_FeatureEnabled_ReturnsCurrentStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatures = [.visualUpdates]

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Should return current corner radius")
        XCTAssertEqual(style.fireButtonSize, 32.0, "Should return current fire button size")
        XCTAssertTrue(style.areNavigationBarCornersRound, "Should have round navigation bar corners")
        XCTAssertTrue(style.addToolbarShadow, "Should add toolbar shadow")
    }

    // MARK: - Internal User Tests

    func testInternalUser_NoLocalOverrides_ReturnsLegacyStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.localOverrides = nil

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Should return legacy corner radius when no local overrides")
    }

    func testInternalUser_LocalOverrideDisabled_ReturnsLegacyStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = true
        mockLocalOverrides.setOverride(for: .visualUpdatesInternalOnly, value: false)

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Should return legacy corner radius when override is false")
        XCTAssertEqual(style.fireButtonSize, 28.0, "Should return legacy fire button size")
        XCTAssertFalse(style.areNavigationBarCornersRound, "Should not have round navigation bar corners")
        XCTAssertFalse(style.addToolbarShadow, "Should not add toolbar shadow")
    }

    func testInternalUser_LocalOverrideEnabled_ReturnsCurrentStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = true
        mockLocalOverrides.setOverride(for: .visualUpdatesInternalOnly, value: true)

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Should return current corner radius when override is true")
        XCTAssertEqual(style.fireButtonSize, 32.0, "Should return current fire button size")
        XCTAssertTrue(style.areNavigationBarCornersRound, "Should have round navigation bar corners")
        XCTAssertTrue(style.addToolbarShadow, "Should add toolbar shadow")
    }

    func testInternalUser_NoLocalOverrideSet_ReturnsCurrentStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = true
        // No override set (nil)

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Should return current corner radius when no override is set")
        XCTAssertEqual(style.fireButtonSize, 32.0, "Should return current fire button size")
        XCTAssertTrue(style.areNavigationBarCornersRound, "Should have round navigation bar corners")
        XCTAssertTrue(style.addToolbarShadow, "Should add toolbar shadow")
    }

    // MARK: - Style Properties Tests

    func testLegacyStyleProperties() {
        // Given
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatures = []

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)
        XCTAssertEqual(style.fireButtonSize, 28.0)
        XCTAssertEqual(style.navigationToolbarButtonsSpacing, 0.0)
        XCTAssertEqual(style.tabBarButtonSize, 28.0)
        XCTAssertFalse(style.areNavigationBarCornersRound)
        XCTAssertFalse(style.addToolbarShadow)

        // Verify style providers are legacy types
        XCTAssertTrue(style.addressBarStyleProvider is LegacyAddressBarStyleProvider)
        XCTAssertTrue(style.tabStyleProvider is LegacyTabStyleProvider)
        XCTAssertTrue(style.colorsProvider is LegacyColorsProviding)
        XCTAssertTrue(style.iconsProvider is LegacyIconsProvider)
    }

    func testCurrentStyleProperties() {
        // Given
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatures = [.visualUpdates]

        // When
        let style = visualStyleManager.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)
        XCTAssertEqual(style.fireButtonSize, 32.0)
        XCTAssertEqual(style.navigationToolbarButtonsSpacing, 2.0)
        XCTAssertEqual(style.tabBarButtonSize, 28.0)
        XCTAssertTrue(style.areNavigationBarCornersRound)
        XCTAssertTrue(style.addToolbarShadow)

        // Verify style providers are current types
        XCTAssertTrue(style.addressBarStyleProvider is CurrentAddressBarStyleProvider)
        XCTAssertTrue(style.tabStyleProvider is NewlineTabStyleProvider)
        XCTAssertTrue(style.colorsProvider is NewColorsProviding)
        XCTAssertTrue(style.iconsProvider is CurrentIconsProvider)
    }

    // MARK: - Feature Flag Separation Tests

    func testInternalUser_IgnoresExternalFeatureFlag() {
        // Given - Internal user with external feature enabled but no local override
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatures = [.visualUpdates] // External feature flag
        // No local override set for internal feature

        // When
        let style = visualStyleManager.style

        // Then - Should return current style (default behavior for internal users when no override)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Internal users should ignore external feature flag")
    }

    func testNonInternalUser_IgnoresInternalFeatureOverride() {
        // Given - Non-internal user with internal feature override set but external feature disabled
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatures = [] // External feature disabled
        mockLocalOverrides.setOverride(for: .visualUpdatesInternalOnly, value: true) // Internal override

        // When
        let style = visualStyleManager.style

        // Then - Should return legacy style (following external feature flag)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Non-internal users should ignore internal feature overrides")
    }

    func testInternalUser_OverridesTakesPrecedenceOverExternalFlag() {
        // Given - Internal user with external feature enabled and internal override disabled
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatures = [.visualUpdates] // External feature enabled
        mockLocalOverrides.setOverride(for: .visualUpdatesInternalOnly, value: false) // Internal override disabled

        // When
        let style = visualStyleManager.style

        // Then - Should return legacy style (following internal override, not external flag)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Internal overrides should take precedence over external feature flags")
    }

    // MARK: - Dynamic Behavior Tests

    func testStyleChangesWithInternalUserStatus() {
        // Given - Start as non-internal user with visualUpdates feature disabled
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatures = []

        // When/Then - Should return legacy style
        var style = visualStyleManager.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Change to internal user with internal feature override enabled
        mockInternalUserDecider.isInternalUser = true
        mockLocalOverrides.setOverride(for: .visualUpdatesInternalOnly, value: true)

        // When/Then - Should return current style
        style = visualStyleManager.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)
    }

    func testStyleChangesWithFeatureToggle() {
        // Given - Non-internal user with feature disabled
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatures = []

        // When/Then - Should return legacy style
        var style = visualStyleManager.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Enable the feature for non-internal users
        mockFeatureFlagger.enabledFeatures = [.visualUpdates]

        // When/Then - Should return current style
        style = visualStyleManager.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)
    }

    func testStyleChangesWithLocalOverride() {
        // Given - Internal user with no override
        mockInternalUserDecider.isInternalUser = true

        // When/Then - Should return current style (default behavior)
        var style = visualStyleManager.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)

        // Given - Set override to disable
        mockLocalOverrides.setOverride(for: .visualUpdatesInternalOnly, value: false)

        // When/Then - Should return legacy style
        style = visualStyleManager.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Set override to enable
        mockLocalOverrides.setOverride(for: .visualUpdatesInternalOnly, value: true)

        // When/Then - Should return current style
        style = visualStyleManager.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)
    }

    // MARK: - Mock Classes

    private class MockInternalUserDecider: InternalUserDecider {
        var isInternalUser: Bool = false
        var isInternalUserPublisher: AnyPublisher<Bool, Never> {
            isInternalUserSubject.eraseToAnyPublisher()
        }

        private let isInternalUserSubject = PassthroughSubject<Bool, Never>()

        func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool {
            return false
        }
    }

    private class MockFeatureFlagger: FeatureFlagger {
        var internalUserDecider: InternalUserDecider
        var localOverrides: FeatureFlagLocalOverriding?
        var enabledFeatures: Set<FeatureFlag> = []

        init(internalUserDecider: InternalUserDecider) {
            self.internalUserDecider = internalUserDecider
        }

        func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
            guard let flag = featureFlag as? FeatureFlag else { return false }
            return enabledFeatures.contains(flag)
        }

        func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
            return nil
        }

        var allActiveExperiments: Experiments { [:] }
    }

    private class MockFeatureFlagLocalOverriding: FeatureFlagLocalOverriding {
        var featureFlagger: (any BrowserServicesKit.FeatureFlagger)? = nil
        var actionHandler: any BrowserServicesKit.FeatureFlagLocalOverridesHandling = MockFeatureFlagLocalOverridesHandling()

        private var overrides: [String: Bool] = [:]

        func setOverride(for flag: FeatureFlag, value: Bool?) {
            if let value = value {
                overrides[flag.rawValue] = value
            } else {
                overrides.removeValue(forKey: flag.rawValue)
            }
        }

        func override<Flag>(for featureFlag: Flag) -> Bool? where Flag : BrowserServicesKit.FeatureFlagDescribing {
            return overrides[featureFlag.rawValue]
        }

        func experimentOverride<Flag>(for featureFlag: Flag) -> BrowserServicesKit.CohortID? where Flag : BrowserServicesKit.FeatureFlagDescribing {
            return nil
        }

        func toggleOverride<Flag>(for featureFlag: Flag) where Flag : BrowserServicesKit.FeatureFlagDescribing {
            let currentValue = override(for: featureFlag)
            setOverride(for: featureFlag as! FeatureFlag, value: currentValue == nil ? true : !currentValue!)
        }

        func setExperimentCohortOverride<Flag>(for featureFlag: Flag, cohort: BrowserServicesKit.CohortID) where Flag : BrowserServicesKit.FeatureFlagDescribing {
            // Not needed for visual updates tests
        }

        func clearOverride<Flag>(for featureFlag: Flag) where Flag : BrowserServicesKit.FeatureFlagDescribing {
            // Not needed for visual updates tests
        }

        func currentValue<Flag>(for featureFlag: Flag) -> Bool? where Flag : BrowserServicesKit.FeatureFlagDescribing {
            return nil
        }

        func currentExperimentCohort<Flag>(for featureFlag: Flag) -> (any BrowserServicesKit.FeatureFlagCohortDescribing)? where Flag : BrowserServicesKit.FeatureFlagDescribing {
            return nil
        }

        func clearAllOverrides<Flag>(for flagType: Flag.Type) where Flag : BrowserServicesKit.FeatureFlagDescribing {
            // Not needed for visual updates tests
        }

        // MARK: - Mocks

        class MockFeatureFlagLocalOverridesHandling: FeatureFlagLocalOverridesHandling {
            func flagDidChange<Flag>(_ featureFlag: Flag, isEnabled: Bool) where Flag : BrowserServicesKit.FeatureFlagDescribing {
                // Not needed for visual updates tests
            }

            func experimentFlagDidChange<Flag>(_ featureFlag: Flag, cohort: BrowserServicesKit.CohortID) where Flag : BrowserServicesKit.FeatureFlagDescribing {
                // Not needed for visual updates tests
            }
        }
    }
}
