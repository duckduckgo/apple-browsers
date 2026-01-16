//
//  BrowsingMenuSheetCapabilityTests.swift
//  DuckDuckGo
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
@testable import Core
@testable import DuckDuckGo
import PrivacyConfig
import PersistenceTestingUtils

@available(iOS 17.0, *)
final class BrowsingMenuSheetCapabilityTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockKeyValueStore: MockThrowingKeyValueStore!
    private var mockInternalUserDecider: MockInternalUserDecider!

    override func setUp() {
        super.setUp()
        mockInternalUserDecider = MockInternalUserDecider()
        mockFeatureFlagger = MockFeatureFlagger(internalUserDecider: mockInternalUserDecider)
        mockKeyValueStore = MockThrowingKeyValueStore()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockKeyValueStore = nil
        mockInternalUserDecider = nil
        super.tearDown()
    }

    // MARK: - isExperimentalMenuOptInEnabled

    func testExperimentalMenuOptInEnabledReturnsTrueWhenBrowsingMenuSheetPresentationFlagIsEnabled() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetPresentation]

        let capability = createCapability()

        XCTAssertTrue(capability.isExperimentalMenuOptInEnabled)
    }

    func testExperimentalMenuOptInEnabledReturnsFalseWhenBrowsingMenuSheetPresentationFlagIsDisabled() {
        mockFeatureFlagger.enabledFeatureFlags = []

        let capability = createCapability()

        XCTAssertFalse(capability.isExperimentalMenuOptInEnabled)
    }

    // MARK: - isEnabled (when isEnabledByDefault is false)

    func testIsEnabledReturnsFalseWhenExperimentalMenuOptInEnabledIsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []

        let capability = createCapability()

        XCTAssertFalse(capability.isEnabled)
    }

    func testIsEnabledReturnsFalseWhenExperimentalMenuOptInEnabledIsTrueButNoStoredValue() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetPresentation]

        let capability = createCapability()

        XCTAssertFalse(capability.isEnabled)
    }

    func testIsEnabledReturnsTrueWhenExperimentalMenuOptInEnabledIsTrueAndStoredValueIsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetPresentation]
        try? mockKeyValueStore.set(true, forKey: "com_duckduckgo_experimentalBrowsingMenu_enabled")

        let capability = createCapability()

        XCTAssertTrue(capability.isEnabled)
    }

    func testIsEnabledReturnsFalseWhenExperimentalMenuOptInEnabledIsTrueAndStoredValueIsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetPresentation]
        try? mockKeyValueStore.set(false, forKey: "com_duckduckgo_experimentalBrowsingMenu_enabled")

        let capability = createCapability()

        XCTAssertFalse(capability.isEnabled)
    }

    // MARK: - isEnabled (when isEnabledByDefault is true)

    func testIsEnabledReturnsTrueWhenEnabledByDefaultAndInternalUserWithNoStoredValue() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetEnabledByDefault]
        mockInternalUserDecider.isInternalUser = true

        let capability = createCapability()

        XCTAssertTrue(capability.isEnabled)
    }

    func testIsEnabledReturnsFalseWhenEnabledByDefaultAndInternalUserWithStoredValueFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetEnabledByDefault]
        mockInternalUserDecider.isInternalUser = true
        try? mockKeyValueStore.set(false, forKey: "com_duckduckgo_experimentalBrowsingMenu_enabled")

        let capability = createCapability()

        XCTAssertFalse(capability.isEnabled)
    }

    func testIsEnabledReturnsTrueWhenEnabledByDefaultAndInternalUserWithStoredValueTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetEnabledByDefault]
        mockInternalUserDecider.isInternalUser = true
        try? mockKeyValueStore.set(true, forKey: "com_duckduckgo_experimentalBrowsingMenu_enabled")

        let capability = createCapability()

        XCTAssertTrue(capability.isEnabled)
    }

    func testIsEnabledReturnsTrueWhenEnabledByDefaultAndExternalUser() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetEnabledByDefault]
        mockInternalUserDecider.isInternalUser = false

        let capability = createCapability()

        XCTAssertTrue(capability.isEnabled)
    }

    func testIsEnabledReturnsTrueWhenEnabledByDefaultAndExternalUserEvenWithStoredValueFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetEnabledByDefault]
        mockInternalUserDecider.isInternalUser = false
        try? mockKeyValueStore.set(false, forKey: "com_duckduckgo_experimentalBrowsingMenu_enabled")

        let capability = createCapability()

        XCTAssertTrue(capability.isEnabled)
    }

    // MARK: - isSettingsOptionVisible (when isEnabledByDefault is false)

    func testIsSettingsOptionVisibleReturnsTrueWhenExperimentalMenuOptInEnabledIsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetPresentation]

        let capability = createCapability()

        XCTAssertTrue(capability.isSettingsOptionVisible)
    }

    func testIsSettingsOptionVisibleReturnsFalseWhenExperimentalMenuOptInEnabledIsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []

        let capability = createCapability()

        XCTAssertFalse(capability.isSettingsOptionVisible)
    }

    // MARK: - isSettingsOptionVisible (when isEnabledByDefault is true)

    func testIsSettingsOptionVisibleReturnsTrueWhenEnabledByDefaultAndInternalUser() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetEnabledByDefault]
        mockInternalUserDecider.isInternalUser = true

        let capability = createCapability()

        XCTAssertTrue(capability.isSettingsOptionVisible)
    }

    func testIsSettingsOptionVisibleReturnsFalseWhenEnabledByDefaultAndExternalUser() {
        mockFeatureFlagger.enabledFeatureFlags = [.browsingMenuSheetEnabledByDefault]
        mockInternalUserDecider.isInternalUser = false

        let capability = createCapability()

        XCTAssertFalse(capability.isSettingsOptionVisible)
    }

    // MARK: - setEnabled

    func testSetEnabledStoresValue() {
        let capability = createCapability()

        capability.setEnabled(true)

        let storedValue = try? mockKeyValueStore.object(forKey: "com_duckduckgo_experimentalBrowsingMenu_enabled") as? Bool
        XCTAssertEqual(storedValue, true)
    }

    // MARK: - Helpers

    private func createCapability() -> BrowsingMenuSheetDefaultCapability {
        return BrowsingMenuSheetDefaultCapability(
            featureFlagger: mockFeatureFlagger,
            keyValueStore: mockKeyValueStore
        )
    }
}
