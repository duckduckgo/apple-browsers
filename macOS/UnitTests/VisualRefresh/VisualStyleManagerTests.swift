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
    private var mockFeatureFlagger: MockFeatureFlagger!
    var visualStyleDecider: VisualStyleDecider!

    override func setUp() {
        super.setUp()
        mockInternalUserDecider = MockInternalUserDecider()
        mockFeatureFlagger = MockFeatureFlagger(internalUserDecider: mockInternalUserDecider)

        visualStyleDecider = DefaultVisualStyleDecider(
            featureFlagger: mockFeatureFlagger,
            internalUserDecider: mockInternalUserDecider
        )
    }

    override func tearDown() {
        mockInternalUserDecider = nil
        mockFeatureFlagger = nil
        visualStyleDecider = nil
        super.tearDown()
    }

    // MARK: - Non-Internal User Tests

    func testNonInternalUser_FeatureDisabled_ReturnsLegacyStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatureFlags = []

        // When
        let style = visualStyleDecider.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Should return legacy corner radius")
        XCTAssertEqual(style.fireButtonSize, 28.0, "Should return legacy fire button size")
        XCTAssertFalse(style.areNavigationBarCornersRound, "Should not have round navigation bar corners")
        XCTAssertFalse(style.addToolbarShadow, "Should not add toolbar shadow")
    }

    func testNonInternalUser_FeatureEnabled_ReturnsCurrentStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates]

        // When
        let style = visualStyleDecider.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Should return current corner radius")
        XCTAssertEqual(style.fireButtonSize, 32.0, "Should return current fire button size")
        XCTAssertTrue(style.areNavigationBarCornersRound, "Should have round navigation bar corners")
        XCTAssertTrue(style.addToolbarShadow, "Should add toolbar shadow")
    }

    // MARK: - Internal User Tests

    func testInternalUser_VisualUpdatesInternalOnlyDisabled_ReturnsLegacyStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatureFlags = [] // No feature flags enabled

        // When
        let style = visualStyleDecider.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Internal users should get legacy style when visualUpdatesInternalOnly is disabled")
        XCTAssertEqual(style.fireButtonSize, 28.0, "Should return legacy fire button size")
        XCTAssertFalse(style.areNavigationBarCornersRound, "Should not have round navigation bar corners")
        XCTAssertFalse(style.addToolbarShadow, "Should not add toolbar shadow")
    }

    func testInternalUser_VisualUpdatesInternalOnlyEnabled_ReturnsCurrentStyle() {
        // Given
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdatesInternalOnly]

        // When
        let style = visualStyleDecider.style

        // Then
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Internal users should get current style when visualUpdatesInternalOnly is enabled")
        XCTAssertEqual(style.fireButtonSize, 32.0, "Should return current fire button size")
        XCTAssertTrue(style.areNavigationBarCornersRound, "Should have round navigation bar corners")
        XCTAssertTrue(style.addToolbarShadow, "Should add toolbar shadow")
    }

    func testInternalUser_IgnoresVisualUpdatesFeatureFlag() {
        // Given - Internal user with visualUpdates enabled but visualUpdatesInternalOnly disabled
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates] // Regular feature flag enabled

        // When
        let style = visualStyleDecider.style

        // Then - Should return legacy style (internal users ignore .visualUpdates flag)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Internal users should ignore .visualUpdates flag and only respond to .visualUpdatesInternalOnly")
        XCTAssertEqual(style.fireButtonSize, 28.0, "Should return legacy fire button size")
        XCTAssertFalse(style.areNavigationBarCornersRound, "Should not have round navigation bar corners")
        XCTAssertFalse(style.addToolbarShadow, "Should not add toolbar shadow")
    }

    // MARK: - Style Properties Tests

    func testLegacyStyleProperties() {
        // Given
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatureFlags = []

        // When
        let style = visualStyleDecider.style

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
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates]

        // When
        let style = visualStyleDecider.style

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

    func testInternalUser_OnlyRespondsToInternalOnlyFeatureFlag() {
        // Given - Internal user with regular visualUpdates enabled
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates]

        // When
        let style = visualStyleDecider.style

        // Then - Should return legacy style (internal users ignore .visualUpdates)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Internal users should ignore .visualUpdates flag")

        // Given - Enable visualUpdatesInternalOnly
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdatesInternalOnly]

        // When
        let styleWithInternalFlag = visualStyleDecider.style

        // Then - Should return current style
        XCTAssertEqual(styleWithInternalFlag.toolbarButtonsCornerRadius, 9.0, "Internal users should respond to .visualUpdatesInternalOnly flag")
    }

    func testNonInternalUser_OnlyRespondsToVisualUpdatesFlag() {
        // Given - Non-internal user with visualUpdatesInternalOnly enabled
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdatesInternalOnly]

        // When
        let style = visualStyleDecider.style

        // Then - Should return legacy style (non-internal users ignore .visualUpdatesInternalOnly)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0, "Non-internal users should ignore .visualUpdatesInternalOnly flag")

        // Given - Enable visualUpdates
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates]

        // When
        let styleWithVisualUpdates = visualStyleDecider.style

        // Then - Should return current style
        XCTAssertEqual(styleWithVisualUpdates.toolbarButtonsCornerRadius, 9.0, "Non-internal users should respond to .visualUpdates flag")
    }

    func testBothFlagsEnabled_InternalUserUsesInternalOnlyFlag() {
        // Given - Internal user with both flags enabled
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates, .visualUpdatesInternalOnly]

        // When
        let style = visualStyleDecider.style

        // Then - Should return current style (both flags enabled, internal user uses internal-only flag)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Internal users should use .visualUpdatesInternalOnly when both flags are enabled")
    }

    func testBothFlagsEnabled_NonInternalUserUsesVisualUpdatesFlag() {
        // Given - Non-internal user with both flags enabled
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates, .visualUpdatesInternalOnly]

        // When
        let style = visualStyleDecider.style

        // Then - Should return current style (both flags enabled, non-internal user uses .visualUpdates flag)
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0, "Non-internal users should use .visualUpdates when both flags are enabled")
    }

    // MARK: - Dynamic Behavior Tests

    func testStyleChangesWithInternalUserStatus() {
        // Given - Start as non-internal user with visualUpdates feature disabled
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatureFlags = []

        // When/Then - Should return legacy style
        var style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Change to internal user (still no feature flags)
        mockInternalUserDecider.isInternalUser = true

        // When/Then - Should still return legacy style (internal users need .visualUpdatesInternalOnly)
        style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Enable internal-only feature flag
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdatesInternalOnly]

        // When/Then - Should now return current style
        style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)
    }

    func testStyleChangesWithFeatureToggleForNonInternalUsers() {
        // Given - Non-internal user with feature disabled
        mockInternalUserDecider.isInternalUser = false
        mockFeatureFlagger.enabledFeatureFlags = []

        // When/Then - Should return legacy style
        var style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Enable the feature for non-internal users
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates]

        // When/Then - Should return current style
        style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)
    }

    func testStyleChangesWithFeatureToggleForInternalUsers() {
        // Given - Internal user with no features enabled
        mockInternalUserDecider.isInternalUser = true
        mockFeatureFlagger.enabledFeatureFlags = []

        // When/Then - Should return legacy style
        var style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Enable regular visualUpdates (should be ignored by internal users)
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdates]

        // When/Then - Should still return legacy style
        style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)

        // Given - Enable internal-only feature
        mockFeatureFlagger.enabledFeatureFlags = [.visualUpdatesInternalOnly]

        // When/Then - Should return current style
        style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 9.0)

        // Given - Disable internal-only feature
        mockFeatureFlagger.enabledFeatureFlags = []

        // When/Then - Should return legacy style again
        style = visualStyleDecider.style
        XCTAssertEqual(style.toolbarButtonsCornerRadius, 4.0)
    }
}
