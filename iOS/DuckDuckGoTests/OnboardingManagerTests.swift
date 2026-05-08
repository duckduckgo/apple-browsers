//
//  OnboardingManagerTests.swift
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

import Onboarding
import Persistence
import PersistenceTestingUtils
import Testing
import class UIKit.UIDevice
@testable import Core
@testable import DuckDuckGo

private enum OnboardingManagerVariants {
    static let newUserVariantManagerMock = MockVariantManager(
        currentVariant: VariantIOS(
            name: "test_variant",
            weight: 0,
            isIncluded: VariantIOS.When.always,
            features: []
        )
    )

    static let returningUserVariantManagerMock = MockVariantManager(
        currentVariant: VariantIOS(
            name: "ru",
            weight: 0,
            isIncluded: VariantIOS.When.always,
            features: []
        )
    )
}


@Suite("Onboarding - Manager")
struct OnboardingManagerTests {

    struct OnboardingStepsNewUser {

        @Test("Check correct onboarding steps are returned for iPhone")
        func checkOnboardingSteps_iPhone() async throws {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.newUserVariantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad")
        func checkOnboardingSteps_iPad() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.newUserVariantManagerMock, isIphone: false)
            let expectedSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

    }

    struct OnboardingStepsReturningUser {

        @Test("Check correct onboarding steps are returned for iPhone")
        func checkOnboardingSteps_iPhone() async throws {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.returningUserVariantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad")
        func checkOnboardingSteps_iPad() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.returningUserVariantManagerMock, isIphone: false)
            let expectedSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: true)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

    }

    struct OnboardingStepsCorrectFlow {

        @Test("Check correct onboarding steps are returned, new user")
        func checkOnboardingStepsNewUser() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.newUserVariantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned, returning user")
        func checkOnboardingStepsReturningUser() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.returningUserVariantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }
    }

    struct NewUserValue {

        @Test(
            "Check correct user type value is returned",
            arguments: zip(
                [
                    OnboardingUserType.notSet,
                    .newUser,
                    .returningUser,
                ],
                [
                    true,
                    true,
                    false,
                ]
            )
        )
        func checkUserType(_ userType: OnboardingUserType, expectedResult: Bool) {
            // GIVEN
            let settingsMock = AppSettingsMock()
            settingsMock.onboardingUserType = userType
            let variant = VariantIOS(name: "test_variant", weight: 0, isIncluded: VariantIOS.When.always, features: [])
            let variantManagerMock = MockVariantManager(currentVariant: variant)
            let sut = OnboardingManager(appDefaults: settingsMock, featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock)

            // WHEN
            let result = sut.isNewUser

            // THEN
            #expect(result == expectedResult)
        }

    }

}

@Suite("Onboarding - Manager + Flow Configuration")
struct OnboardingFlowConfiguration {

    @Test("Check default flow is configured when URL is nil")
    func configuresDefaultFlowForNilURL() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        #expect(tutorialSettings.onboardingFlowType == nil)

        // WHEN
        sut.configureOnboardingFlow(from: nil)

        // THEN
        #expect(tutorialSettings.onboardingFlowType == .default)
        #expect(sharedPixelStorage.onboardingSource == .default)
        #expect(sharedPixelStorage.onboardingFlow == .default)
    }

    @Test("Check Duck.ai flow is configured when URL is ddgCPP://duckAI")
    func configuresDuckAIFlowForValidURL() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        #expect(tutorialSettings.onboardingFlowType == nil)
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        sut.configureOnboardingFlow(from: url)

        // THEN
        #expect(tutorialSettings.onboardingFlowType == .duckAI)
        #expect(sharedPixelStorage.onboardingSource == .duckAICustomProductPage)
        #expect(sharedPixelStorage.onboardingFlow == .duckAI)
    }

    @Test("Check default flow is configured when URL is invalid")
    func configuresDefaultFlowForInvalidURL() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        #expect(tutorialSettings.onboardingFlowType == nil)
        let url = URL(string: "ddgCPP://unknown-flow")

        // WHEN
        sut.configureOnboardingFlow(from: url)

        // THEN
        #expect(tutorialSettings.onboardingFlowType == .default)
        #expect(sharedPixelStorage.onboardingSource == .default)
        #expect(sharedPixelStorage.onboardingFlow == .default)
    }

    @Test("Check flow is not reconfigured when it is already been set")
    func doesNotReconfigureWhenAlreadySet() {
        // GIVEN
        let sharedPixelStorage = makePixelStore(source: .duckAICustomProductPage, flow: .duckAI)
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        tutorialSettings.onboardingFlowType = .default
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        sut.configureOnboardingFlow(from: url)

        // THEN - Should remain .default, not switch to .duckAI
        #expect(tutorialSettings.onboardingFlowType == .default)
        #expect(sharedPixelStorage.onboardingSource == .duckAICustomProductPage)
        #expect(sharedPixelStorage.onboardingFlow == .duckAI)
    }

    @Test("Check flow is not reconfigured when onboarding has been seen")
    func doesNotConfigureWhenOnboardingHasBeenSeen() {
        // GIVEN
        let sharedPixelStorage = makePixelStore(source: .default, flow: .default)
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        sut.configureOnboardingFlow(from: url)

        // THEN - Should remain nil
        #expect(tutorialSettings.onboardingFlowType == nil)
        #expect(sharedPixelStorage.onboardingSource == .default)
        #expect(sharedPixelStorage.onboardingFlow == .default)
    }

    @Test("Check Duck.ai flow falls back to default when feature flag is disabled")
    func fallsBackToDefaultWhenDuckAIFeatureFlagDisabled() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        #expect(tutorialSettings.onboardingFlowType == nil)
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        sut.configureOnboardingFlow(from: url)

        // THEN - Should fall back to .default, not .duckAI
        #expect(tutorialSettings.onboardingFlowType == .default)
        #expect(sharedPixelStorage.onboardingSource == .duckAICustomProductPage)
        #expect(sharedPixelStorage.onboardingFlow == .default)
    }

    @Test("Check Duck.ai flow is configured when feature flag is enabled")
    func configuresDuckAIFlowWhenFeatureFlagEnabled() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        #expect(tutorialSettings.onboardingFlowType == nil)
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        sut.configureOnboardingFlow(from: url)

        // THEN - Should configure .duckAI flow
        #expect(tutorialSettings.onboardingFlowType == .duckAI)
        #expect(sharedPixelStorage.onboardingSource == .duckAICustomProductPage)
        #expect(sharedPixelStorage.onboardingFlow == .duckAI)
    }

    @Test("Check default flow is not affected by Duck.ai feature flag")
    func defaultFlowNotAffectedByDuckAIFeatureFlag() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        #expect(tutorialSettings.onboardingFlowType == nil)

        // WHEN - Nil URL should still result in .default flow
        sut.configureOnboardingFlow(from: nil)

        // THEN - Should configure .default flow normally
        #expect(tutorialSettings.onboardingFlowType == .default)
        #expect(sharedPixelStorage.onboardingSource == .default)
        #expect(sharedPixelStorage.onboardingFlow == .default)
    }

    private func makePixelStore(source: OnboardingPixelParameter.Source? = nil,
                                flow: OnboardingPixelParameter.Flow? = nil) -> any KeyedStoring<OnboardingSharedPixelsKeys> {
        let mockStore = InMemoryKeyValueStore()
        let storage: any KeyedStoring<OnboardingSharedPixelsKeys> = mockStore.keyedStoring()
        if let source {
            storage.onboardingSource = source
        }
        if let flow {
            storage.onboardingFlow = flow
        }
        return storage
    }
}

@Suite("Onboarding - Onboarding Steps for Flow")
struct OnboardingStepsForConfiguredFlow {

    @Test(
        "Check return default new user steps when flow is nil",
        arguments: [true, false]
    )
    func returnsDefaultStepsWhenFlowIsNil(isReturningUser: Bool) {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        tutorialSettings.onboardingFlowType = nil
        let variantManager = isReturningUser ? OnboardingManagerVariants.returningUserVariantManagerMock : OnboardingManagerVariants.newUserVariantManagerMock
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(),
            variantManager: variantManager,
            isIphone: true,
            tutorialSettings: tutorialSettings
        )
        let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: isReturningUser)

        // WHEN
        let result = sut.onboardingSteps

        // THEN
        #expect(result == expectedSteps)
    }

    @Test(
        "Check return default new user steps when flow is explicitly set to default",
        arguments: [true, false]
    )
    func returnsDefaultStepsWhenFlowIsDefault(isReturningUser: Bool) {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        tutorialSettings.onboardingFlowType = .default
        let variantManager = isReturningUser ? OnboardingManagerVariants.returningUserVariantManagerMock : OnboardingManagerVariants.newUserVariantManagerMock
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(),
            variantManager: variantManager,
            isIphone: true,
            tutorialSettings: tutorialSettings
        )
        let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: isReturningUser)

        // WHEN
        let result = sut.onboardingSteps

        // THEN
        #expect(result == expectedSteps)
    }

    @Test(
        "Check return duckAI steps when flow is set to duckAI",
        arguments: [true, false]
    )
    func returnsDuckAIStepsWhenFlowIsDuckAI(isReturningUser: Bool) {
        // GIVEN
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        tutorialSettings.onboardingFlowType = .duckAI
        let variantManager = isReturningUser ? OnboardingManagerVariants.returningUserVariantManagerMock : OnboardingManagerVariants.newUserVariantManagerMock
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(),
            variantManager: variantManager,
            isIphone: true,
            tutorialSettings: tutorialSettings
        )
        let expectedSteps: [OnboardingIntroStep] = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: isReturningUser)

        // WHEN
        let result = sut.onboardingSteps

        // THEN
        #expect(result == expectedSteps)
    }
    
}
