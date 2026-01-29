//
//  LaunchOptionsHandlerTests.swift
//  DuckDuckGo
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

import XCTest
@testable import Core
import PrivacyConfig

final class LaunchOptionsHandlerTests: XCTestCase {
    private static let suiteName = "testing_launchOptionsHandler"
    private var userDefaults: UserDefaults!

    private class MockInternalUserStore: InternalUserStoring {
        var isInternalUser: Bool = false
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDefaults = UserDefaults(suiteName: Self.suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: Self.suiteName)
        userDefaults = nil
        try super.tearDownWithError()
    }

    // MARK: - isOnboardingCompleted

    func testShouldReturnStatusOverriddenDeveloperCompletedTrueWhenIsOnboardingCompletedAndEnvironmentsOnboardingIsFalse() {
        // GIVEN
        let environment = ["ONBOARDING": "false"]
        let sut = LaunchOptionsHandler(environment: environment, userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .overridden(.developer(completed: true)))
    }

    func testShouldReturnStatusOverriddenDeveloperCompletedFalseWhenIsOnboardingCompletedAndEnvironmentsOnboardingIsTrue() {
        // GIVEN
        let environment = ["ONBOARDING": "true"]
        let sut = LaunchOptionsHandler(environment: environment, userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .overridden(.developer(completed: false)))
    }

    func testShouldReturnStatusOverriddenUITestsCompletedTrueWhenIsOnboardingCompletedAndDefaultsIsOnboardingCompletedIsTrue() {
        // GIVEN
        userDefaults.set("true", forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .overridden(.uiTests(completed: true)))
    }

    func testShouldReturnStatusOverriddenCompletedFalseWhenIsOnboardingCompletedAndDefaultsIsOnboardingCompletedIsFalse() {
        // GIVEN
        userDefaults.set("false", forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .overridden(.uiTests(completed: false)))
    }

    func testShouldReturnStatusNotOverriddenWhenIsOnboardingCompletedAndDefaultsAndEnvironmentAreNotDefined() {
        // GIVEN
        userDefaults.removeObject(forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .notOverridden)
    }

    // MARK: - App Variant

    func testShouldReturnAppVariantWhenAppVariantIsCalledAndDefaultsContainsAppVariant() {
        // GIVEN
        userDefaults.set("mb", forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        XCTAssertEqual(result, "mb")
    }

    func testShouldReturnNilWhenAppVariantIsCalledAndDefaultsDoesNotContainsAppVariant() {
        // GIVEN
        userDefaults.removeObject(forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        XCTAssertNil(result)
    }

    func testShouldReturnNilWhenAppVariantIsCalledAndDefaultsContainsNullStringAppVariant() {
        // GIVEN
        userDefaults.set("null", forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        XCTAssertNil(result)
    }

    // MARK: - iPad 17.7.7 Issue

    func testShouldReturnDeveloperOverriddenCompletedWhenIpadAndOSIs17_7_7() throws {
        // GIVEN
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: true, systemVersion: "17.7.7")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .overridden(.developer(completed: true)))
    }

    func testShouldNotReturnDeveloperOverriddenCompletedWhenIpadAndOSIsNot17_7_7() throws {
        // GIVEN
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: true, systemVersion: "17.7.6")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .notOverridden)
    }

    func testShouldNotReturnDeveloperOverriddenCompletedWhenIsNotIpadAndOSIs17_7_7() {
        // GIVEN
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: false, systemVersion: "17.7.7")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        XCTAssertEqual(result, .notOverridden)
    }

    // MARK: - UI Test Overrides

    func testWhenNoOverridesPassedThenInternalUserNotEnabled() {
        // GIVEN
        let featureFlagStore = UserDefaults(suiteName: "testing_featureFlags")!
        let configStore = UserDefaults(suiteName: "testing_configRollout")!
        let mockInternalUserStore = MockInternalUserStore()
        let sut = LaunchOptionsHandler(
            environment: [:],
            userDefaults: userDefaults,
            arguments: [],
            internalUserStore: mockInternalUserStore
        )

        // WHEN
        sut.applyUITestOverrides(featureFlagOverrideStore: featureFlagStore, configRolloutStore: configStore)

        // THEN - No overrides applied, internal user should NOT be enabled
        XCTAssertFalse(mockInternalUserStore.isInternalUser)

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    func testWhenFeatureFlagOverrideIsPassedThenItIsAppliedAndInternalUserEnabled() {
        // GIVEN
        userDefaults.set("true", forKey: "ff.uiTestFeatureFlag")
        let featureFlagStore = UserDefaults(suiteName: "testing_featureFlags")!
        let configStore = UserDefaults(suiteName: "testing_configRollout")!
        let mockInternalUserStore = MockInternalUserStore()
        let sut = LaunchOptionsHandler(
            environment: [:],
            userDefaults: userDefaults,
            arguments: ["-ff.uiTestFeatureFlag", "true"],
            internalUserStore: mockInternalUserStore
        )

        // WHEN
        sut.applyUITestOverrides(featureFlagOverrideStore: featureFlagStore, configRolloutStore: configStore)

        // THEN
        XCTAssertTrue(featureFlagStore.bool(forKey: "localOverrideUiTestFeatureFlag"))
        XCTAssertTrue(mockInternalUserStore.isInternalUser)

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    func testWhenExperimentCohortOverrideIsPassedThenItIsAppliedAndInternalUserEnabled() {
        // GIVEN
        userDefaults.set("treatment", forKey: "experiment.uiTestExperiment")
        let featureFlagStore = UserDefaults(suiteName: "testing_featureFlags")!
        let configStore = UserDefaults(suiteName: "testing_configRollout")!
        let mockInternalUserStore = MockInternalUserStore()
        let sut = LaunchOptionsHandler(
            environment: [:],
            userDefaults: userDefaults,
            arguments: ["-experiment.uiTestExperiment", "treatment"],
            internalUserStore: mockInternalUserStore
        )

        // WHEN
        sut.applyUITestOverrides(featureFlagOverrideStore: featureFlagStore, configRolloutStore: configStore)

        // THEN
        XCTAssertEqual(featureFlagStore.string(forKey: "localOverrideUiTestExperiment_cohort"), "treatment")
        XCTAssertTrue(mockInternalUserStore.isInternalUser)

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    func testWhenConfigRolloutOverrideIsPassedThenItIsAppliedAndInternalUserEnabled() {
        // GIVEN
        userDefaults.set("true", forKey: "config.rollout.duckPlayer.enableDuckPlayer")
        let featureFlagStore = UserDefaults(suiteName: "testing_featureFlags")!
        let configStore = UserDefaults(suiteName: "testing_configRollout")!
        let mockInternalUserStore = MockInternalUserStore()
        let sut = LaunchOptionsHandler(
            environment: [:],
            userDefaults: userDefaults,
            arguments: ["-config.rollout.duckPlayer.enableDuckPlayer", "true"],
            internalUserStore: mockInternalUserStore
        )

        // WHEN
        sut.applyUITestOverrides(featureFlagOverrideStore: featureFlagStore, configRolloutStore: configStore)

        // THEN
        XCTAssertTrue(configStore.bool(forKey: "config.duckPlayer.enableDuckPlayer.enabled"))
        XCTAssertTrue(mockInternalUserStore.isInternalUser)

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

}
