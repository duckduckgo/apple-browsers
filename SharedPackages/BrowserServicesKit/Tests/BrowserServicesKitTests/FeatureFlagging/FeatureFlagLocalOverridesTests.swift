//
//  FeatureFlagLocalOverridesTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import PersistenceTestingUtils
import XCTest

final class CapturingFeatureFlagLocalOverridesHandler: FeatureFlagLocalOverridesHandling {

    struct Parameters: Equatable {
        let rawValue: String
        let isEnabled: Bool?
        let cohort: CohortID?
    }
    var calls: [Parameters] = []

    func flagDidChange<Flag: FeatureFlagDescribing>(_ featureFlag: Flag, isEnabled: Bool) {
        calls.append(.init(rawValue: featureFlag.rawValue, isEnabled: isEnabled, cohort: nil))
    }

    func experimentFlagDidChange<Flag>(_ featureFlag: Flag, cohort: CohortID) where Flag: FeatureFlagDescribing {
        calls.append(.init(rawValue: featureFlag.rawValue, isEnabled: nil, cohort: cohort))
    }
}

final class FeatureFlagLocalOverridesTests: XCTestCase {
    var internalUserDeciderStore: MockInternalUserStoring!
    var keyValueStore: MockKeyValueStore!
    var actionHandler: CapturingFeatureFlagLocalOverridesHandler!
    var overrides: FeatureFlagLocalOverrides!
    var featureFlagger: FeatureFlagger!

    override func setUp() {
        super.setUp()

        // Set environment variable to allow DefaultFeatureFlagger in tests
        setenv("TESTS_FEATUREFLAGGER_MODE", "1", 1)

        internalUserDeciderStore = MockInternalUserStoring()
        internalUserDeciderStore.isInternalUser = true
        let internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)
        let privacyConfig = MockPrivacyConfiguration()
        let privacyConfigManager = MockPrivacyConfigurationManager(privacyConfig: privacyConfig, internalUserDecider: internalUserDecider)
        featureFlagger = DefaultFeatureFlagger(internalUserDecider: internalUserDecider, privacyConfigManager: privacyConfigManager, experimentManager: nil)

        keyValueStore = MockKeyValueStore()
        actionHandler = CapturingFeatureFlagLocalOverridesHandler()
        overrides = FeatureFlagLocalOverrides(
            persistor: FeatureFlagLocalOverridesUserDefaultsPersistor(keyValueStore: keyValueStore),
            actionHandler: actionHandler
        )
        overrides.featureFlagger = featureFlagger
    }

    override func tearDown() {
        // Clean up environment variable
        unsetenv("TESTS_FEATUREFLAGGER_MODE")

        super.tearDown()
    }

    func testThatOverridesAreNilByDefault() {
        XCTAssertNil(overrides.override(for: TestFeatureFlag.nonOverridableFlag))
        XCTAssertNil(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault))
        XCTAssertNil(overrides.override(for: TestFeatureFlag.overridableFlagEnabledByDefault))
    }

    func testWhenFlagIsNotOverridableThenOverrideHasNoEffect() throws {
        overrides.toggleOverride(for: TestFeatureFlag.nonOverridableFlag)
        XCTAssertNil(overrides.override(for: TestFeatureFlag.nonOverridableFlag))
    }

    func testWhenFlagIsOverridableThenToggleOverrideChangesFlagValue() throws {
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagEnabledByDefault)
        XCTAssertFalse(try XCTUnwrap(overrides.override(for: TestFeatureFlag.overridableFlagEnabledByDefault)))

        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertTrue(try XCTUnwrap(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault)))
    }

    func testWhenToggleIsCalledMultipleTimesThenItAlternatesFlagValue() throws {
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertTrue(try XCTUnwrap(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault)))
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertFalse(try XCTUnwrap(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault)))
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertTrue(try XCTUnwrap(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault)))
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertFalse(try XCTUnwrap(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault)))
    }

    func testWhenFlagOverrideChangesThenActionHandlerIsCalled() throws {
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagEnabledByDefault)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagEnabledByDefault)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagEnabledByDefault)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagEnabledByDefault)

        XCTAssertEqual(
            actionHandler.calls,
            [
                .init(rawValue: TestFeatureFlag.overridableFlagDisabledByDefault.rawValue, isEnabled: true, cohort: nil),
                .init(rawValue: TestFeatureFlag.overridableFlagEnabledByDefault.rawValue, isEnabled: false, cohort: nil),
                .init(rawValue: TestFeatureFlag.overridableFlagDisabledByDefault.rawValue, isEnabled: false, cohort: nil),
                .init(rawValue: TestFeatureFlag.overridableFlagEnabledByDefault.rawValue, isEnabled: true, cohort: nil),
                .init(rawValue: TestFeatureFlag.overridableFlagEnabledByDefault.rawValue, isEnabled: false, cohort: nil),
                .init(rawValue: TestFeatureFlag.overridableFlagEnabledByDefault.rawValue, isEnabled: true, cohort: nil)
            ]
        )
    }

    func testWhenClearOverrideIsCalledThenOverrideIsRemovedAndActionHandlerIsCalled() throws {
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertTrue(try XCTUnwrap(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault)))
        overrides.clearOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertNil(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault))

        XCTAssertEqual(
            actionHandler.calls,
            [
                .init(rawValue: TestFeatureFlag.overridableFlagDisabledByDefault.rawValue, isEnabled: true, cohort: nil),
                .init(rawValue: TestFeatureFlag.overridableFlagDisabledByDefault.rawValue, isEnabled: false, cohort: nil)
            ]
        )
    }

    func testWhenOverrideIsEqualToNormalFlagValueAndClearOverrideIsCalledThenActionHandlerIsNotCalled() throws {
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        actionHandler.calls.removeAll()
        overrides.clearOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertNil(overrides.override(for: TestFeatureFlag.nonOverridableFlag))
        XCTAssertTrue(actionHandler.calls.isEmpty)
    }

    func testWhenClearOverrideIsCalledForNonOverridableFlagThenItHasNoEffect() throws {
        XCTAssertNil(overrides.override(for: TestFeatureFlag.nonOverridableFlag))
        overrides.clearOverride(for: TestFeatureFlag.nonOverridableFlag)
        XCTAssertNil(overrides.override(for: TestFeatureFlag.nonOverridableFlag))
        XCTAssertTrue(actionHandler.calls.isEmpty)
    }

    func testWhenNoOverrideThenClearOverrideHasNoEffect() throws {
        XCTAssertNil(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault))
        overrides.clearOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        overrides.clearOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        overrides.clearOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        XCTAssertNil(overrides.override(for: TestFeatureFlag.overridableFlagDisabledByDefault))

        XCTAssertTrue(actionHandler.calls.isEmpty)
    }

    func testClearAllOverrides() throws {
        overrides.toggleOverride(for: TestFeatureFlag.nonOverridableFlag)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagDisabledByDefault)
        overrides.toggleOverride(for: TestFeatureFlag.overridableFlagEnabledByDefault)
        actionHandler.calls.removeAll()

        overrides.clearAllOverrides(for: TestFeatureFlag.self)
        XCTAssertEqual(
            actionHandler.calls,
            [
                .init(rawValue: TestFeatureFlag.overridableFlagDisabledByDefault.rawValue, isEnabled: false, cohort: nil),
                .init(rawValue: TestFeatureFlag.overridableFlagEnabledByDefault.rawValue, isEnabled: true, cohort: nil)
            ]
        )
    }
}
