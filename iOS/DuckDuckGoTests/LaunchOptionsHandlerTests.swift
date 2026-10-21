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

import Foundation
import Testing
@testable import Core
import Persistence
import PrivacyConfig
import SitePermissions
@testable import DuckDuckGo

@Suite(.serialized)
final class LaunchOptionsHandlerTests {
    private static let suiteName = "testing_launchOptionsHandler"
    private let userDefaults: UserDefaults

    private class MockInternalUserStore: InternalUserStoring {
        var isInternalUser: Bool = false
    }

    init() {
        userDefaults = UserDefaults(suiteName: Self.suiteName)!
    }

    deinit {
        userDefaults.removePersistentDomain(forName: Self.suiteName)
    }

    // MARK: - isOnboardingCompleted

    @Test
    func testShouldReturnStatusOverriddenDeveloperCompletedTrueWhenIsOnboardingCompletedAndEnvironmentsOnboardingIsFalse() {
        // GIVEN
        let environment = ["ONBOARDING": "false"]
        let sut = LaunchOptionsHandler(environment: environment, userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.developer(completed: true)))
    }

    @Test
    func testShouldReturnStatusOverriddenDeveloperCompletedFalseWhenIsOnboardingCompletedAndEnvironmentsOnboardingIsTrue() {
        // GIVEN
        let environment = ["ONBOARDING": "true"]
        let sut = LaunchOptionsHandler(environment: environment, userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.developer(completed: false)))
    }

    @Test
    func testShouldReturnStatusOverriddenUITestsCompletedTrueWhenIsOnboardingCompletedAndDefaultsIsOnboardingCompletedIsTrue() {
        // GIVEN
        userDefaults.set("true", forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.uiTests(completed: true)))
    }

    @Test
    func testShouldReturnStatusOverriddenCompletedFalseWhenIsOnboardingCompletedAndDefaultsIsOnboardingCompletedIsFalse() {
        // GIVEN
        userDefaults.set("false", forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.uiTests(completed: false)))
    }

    @Test
    func testShouldReturnStatusNotOverriddenWhenIsOnboardingCompletedAndDefaultsAndEnvironmentAreNotDefined() {
        // GIVEN
        userDefaults.removeObject(forKey: "isOnboardingCompleted")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .notOverridden)
    }

    @Test
    func testStartupOnboardingDecisionShowsOnboardingWhenNotOverriddenAndOnboardingNotSeen() {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)

        // WHEN
        let decision = StartupOnboardingDecision(onboardingStatus: .notOverridden, tutorialSettings: tutorialSettings)

        // THEN
        #expect(decision.shouldShowOnboarding)
    }

    @Test
    func testStartupOnboardingDecisionSkipsOnboardingWhenDeveloperOverrideMarksItCompleted() {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)

        // WHEN
        let decision = StartupOnboardingDecision(
            onboardingStatus: .overridden(.developer(completed: true)),
            tutorialSettings: tutorialSettings
        )

        // THEN
        #expect(!(decision.shouldShowOnboarding))
    }

    @Test
    func testStartupOnboardingDecisionShowsOnboardingWhenDeveloperOverrideMarksItIncomplete() {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)

        // WHEN
        let decision = StartupOnboardingDecision(
            onboardingStatus: .overridden(.developer(completed: false)),
            tutorialSettings: tutorialSettings
        )

        // THEN
        #expect(decision.shouldShowOnboarding)
    }

    @Test
    func testStartupOnboardingDecisionPersistsUITestCompletionOverride() {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)

        // WHEN
        let decision = StartupOnboardingDecision(
            onboardingStatus: .overridden(.uiTests(completed: true)),
            tutorialSettings: tutorialSettings
        )

        // THEN
        #expect(!(decision.shouldShowOnboarding))
        #expect(tutorialSettings.hasSeenOnboarding)
    }

    @Test
    func testStartupOnboardingDecisionPersistsUITestIncompleteOverride() {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)

        // WHEN
        let decision = StartupOnboardingDecision(
            onboardingStatus: .overridden(.uiTests(completed: false)),
            tutorialSettings: tutorialSettings
        )

        // THEN
        #expect(decision.shouldShowOnboarding)
        #expect(!(tutorialSettings.hasSeenOnboarding))
    }

    // MARK: - App Variant

    @Test
    func testShouldReturnAppVariantWhenAppVariantIsCalledAndDefaultsContainsAppVariant() {
        // GIVEN
        userDefaults.set("mb", forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        #expect(result == "mb")
    }

    @Test
    func testShouldReturnNilWhenAppVariantIsCalledAndDefaultsDoesNotContainsAppVariant() {
        // GIVEN
        userDefaults.removeObject(forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        #expect(result == nil)
    }

    @Test
    func testShouldReturnNilWhenAppVariantIsCalledAndDefaultsContainsNullStringAppVariant() {
        // GIVEN
        userDefaults.set("null", forKey: "currentAppVariant")
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults)

        // WHEN
        let result = sut.appVariantName

        // THEN
        #expect(result == nil)
    }

    // MARK: - iPad 17.7.7 Issue

    @Test
    func testShouldReturnDeveloperOverriddenCompletedWhenIpadAndOSIs17_7_7() throws {
        // GIVEN
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: true, systemVersion: "17.7.7")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .overridden(.developer(completed: true)))
    }

    @Test
    func testShouldNotReturnDeveloperOverriddenCompletedWhenIpadAndOSIsNot17_7_7() throws {
        // GIVEN
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: true, systemVersion: "17.7.6")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .notOverridden)
    }

    @Test
    func testShouldNotReturnDeveloperOverriddenCompletedWhenIsNotIpadAndOSIs17_7_7() {
        // GIVEN
        let sut = LaunchOptionsHandler(environment: [:], userDefaults: userDefaults, isIpad: false, systemVersion: "17.7.7")

        // WHEN
        let result = sut.onboardingStatus

        // THEN
        #expect(result == .notOverridden)
    }

    // MARK: - UI Test Overrides

#if DEBUG
    @MainActor
    @Test
    func testWhenSitePermissionsAreSeededForUITestsThenRecordsCanBeCleared() throws {
        let argumentDomain = userDefaults.volatileDomain(forName: UserDefaults.argumentDomain)
        userDefaults.setVolatileDomain(
            ["sitePermissionsTestSeed": ["example.com": ["camera": "allow"]]],
            forName: UserDefaults.argumentDomain)
        defer { userDefaults.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain) }
        let store = SitePermissionsStore(storage: userDefaults.keyedStoring())
        let url = try #require(URL(string: "https://example.com"))
        let site = try #require(SitePermissionKey(committedURL: url))

        let normalLaunch = LaunchOptionsHandler(
            environment: [:], userDefaults: userDefaults, arguments: [], internalUserStore: MockInternalUserStore())
        normalLaunch.applyUITestOverrides(featureFlagOverrideStore: userDefaults, configRolloutStore: userDefaults)
        #expect(store.storedSites.isEmpty)

        let testLaunch = LaunchOptionsHandler(
            environment: ["UITEST_MODE": "1"], userDefaults: userDefaults, arguments: [], internalUserStore: MockInternalUserStore())
        testLaunch.applyUITestOverrides(featureFlagOverrideStore: userDefaults, configRolloutStore: userDefaults)
        #expect(store.decision(for: .camera, at: site) == .allow)

        store.clearSitePermissions()
        #expect(store.storedSites.isEmpty)
        #expect(userDefaults.dictionary(forKey: "sitePermissionsTestSeed") != nil)
    }
#endif

    @Test
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
        #expect(!(mockInternalUserStore.isInternalUser))

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    @Test
    func testWhenFeatureFlagOverrideIsPassedThenItIsAppliedWithoutEnablingInternalUser() {
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
        #expect(featureFlagStore.bool(forKey: "localOverrideUiTestFeatureFlag"))
        #expect(!(mockInternalUserStore.isInternalUser))

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    @Test
    func testWhenExperimentCohortOverrideIsPassedThenItIsAppliedWithoutEnablingInternalUser() {
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
        #expect(featureFlagStore.string(forKey: "localOverrideUiTestExperiment_cohort") == "treatment")
        #expect(!(mockInternalUserStore.isInternalUser))

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    @Test
    func testWhenConfigRolloutOverrideIsPassedThenItIsAppliedWithoutEnablingInternalUser() {
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
        #expect(configStore.bool(forKey: "config.duckPlayer.enableDuckPlayer.enabled"))
        #expect(!(mockInternalUserStore.isInternalUser))

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    @Test
    func testWhenIsInternalUserArgIsTrueThenInternalUserIsEnabled() {
        // GIVEN
        userDefaults.set("true", forKey: "isInternalUser")
        let featureFlagStore = UserDefaults(suiteName: "testing_featureFlags")!
        let configStore = UserDefaults(suiteName: "testing_configRollout")!
        let mockInternalUserStore = MockInternalUserStore()
        let sut = LaunchOptionsHandler(
            environment: [:],
            userDefaults: userDefaults,
            arguments: ["-isInternalUser", "true"],
            internalUserStore: mockInternalUserStore
        )

        // WHEN
        sut.applyUITestOverrides(featureFlagOverrideStore: featureFlagStore, configRolloutStore: configStore)

        // THEN
        #expect(mockInternalUserStore.isInternalUser)

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

    /// Verifies the one-way semantics of `-isInternalUser`: the arg can only set the flag to `true`.
    /// Passing `false` (or any non-"true" value) is a no-op. To detect "no-op", the mock starts at `true`
    /// and the assertion checks it stayed `true`. Off is the default state, set by absence of the arg.
    @Test
    func testWhenIsInternalUserArgIsFalseThenInternalUserStoreIsNotModified() {
        // GIVEN
        userDefaults.set("false", forKey: "isInternalUser")
        let featureFlagStore = UserDefaults(suiteName: "testing_featureFlags")!
        let configStore = UserDefaults(suiteName: "testing_configRollout")!
        let mockInternalUserStore = MockInternalUserStore()
        mockInternalUserStore.isInternalUser = true
        let sut = LaunchOptionsHandler(
            environment: [:],
            userDefaults: userDefaults,
            arguments: ["-isInternalUser", "false"],
            internalUserStore: mockInternalUserStore
        )

        // WHEN
        sut.applyUITestOverrides(featureFlagOverrideStore: featureFlagStore, configRolloutStore: configStore)

        // THEN
        #expect(mockInternalUserStore.isInternalUser)

        // Cleanup
        featureFlagStore.removePersistentDomain(forName: "testing_featureFlags")
        configStore.removePersistentDomain(forName: "testing_configRollout")
    }

}
