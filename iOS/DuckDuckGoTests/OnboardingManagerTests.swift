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
import PrivacyConfig
import Testing
import class UIKit.UIDevice
import protocol BrowserServicesKit.VariantManager
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
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.newUserVariantManagerMock, isIphone: true, tutorialSettings: MockTutorialSettings(hasSeenOnboarding: false))
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad")
        func checkOnboardingSteps_iPad() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.newUserVariantManagerMock, isIphone: false, tutorialSettings: MockTutorialSettings(hasSeenOnboarding: false))
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
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.returningUserVariantManagerMock, isIphone: true, tutorialSettings: MockTutorialSettings(hasSeenOnboarding: true))
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad")
        func checkOnboardingSteps_iPad() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.returningUserVariantManagerMock, isIphone: false, tutorialSettings: MockTutorialSettings(hasSeenOnboarding: true))
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
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.newUserVariantManagerMock, isIphone: true, tutorialSettings: MockTutorialSettings(hasSeenOnboarding: false))
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned, returning user")
        func checkOnboardingStepsReturningUser() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: OnboardingManagerVariants.returningUserVariantManagerMock, isIphone: true, tutorialSettings: MockTutorialSettings(hasSeenOnboarding: false))
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

    @Test("Check Duck.ai flow falls back to default on iPad")
    func fallsBackToDefaultWhenDeviceIsIPad() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            isIphone: false,
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )
        #expect(tutorialSettings.onboardingFlowType == nil)
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        sut.configureOnboardingFlow(from: url)

        // THEN - Should fall back to .default since Duck.ai onboarding is iPhone-only
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

    @Test("Check stale resume checkpoint is cleared when configuring the flow for the first time")
    func clearsStaleResumeCheckpointWhenConfiguringFlowFirstTime() {
        // GIVEN - resume step persisted by a prior build that never set onboardingFlowType
        let sharedPixelStorage = makePixelStore()
        let resumeStore: any KeyedStoring<OnboardingStoringKeys> = InMemoryKeyValueStore().keyedStoring()
        resumeStore.resumeStep = .appIconSelection
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage,
            onboardingResumeStepStore: resumeStore
        )
        #expect(tutorialSettings.onboardingFlowType == nil)
        #expect(resumeStore.resumeStep == .appIconSelection)

        // WHEN
        sut.configureOnboardingFlow(from: URL(string: "ddgCPP://duckAI"))

        // THEN - resume checkpoint is wiped so we don't restore into a step that may not exist in the resolved flow
        #expect(resumeStore.resumeStep == nil)
    }

    @Test("Check resume checkpoint is preserved when flow is already configured")
    func preservesResumeCheckpointWhenFlowAlreadyConfigured() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let resumeStore: any KeyedStoring<OnboardingStoringKeys> = InMemoryKeyValueStore().keyedStoring()
        resumeStore.resumeStep = .appIconSelection
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        tutorialSettings.onboardingFlowType = .default
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIFlow]),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage,
            onboardingResumeStepStore: resumeStore
        )

        // WHEN
        sut.configureOnboardingFlow(from: URL(string: "ddgCPP://duckAI"))

        // THEN - flow was already set, no reconfiguration, no clear
        #expect(resumeStore.resumeStep == .appIconSelection)
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
        let expectedSteps: [OnboardingIntroStep] = OnboardingStepsHelper.expectedDuckAISteps(isReturningUser: isReturningUser)

        // WHEN
        let result = sut.onboardingSteps

        // THEN
        #expect(result == expectedSteps)
    }

    // MARK: - Resume-step mapping

    @Test("Check OnboardingIntroStep.resumeStep maps each step to the matching checkpoint")
    func resumeStepMappingIsCorrect() {
        #expect(OnboardingIntroStep.introDialog(isReturningUser: false).resumeStep == nil)
        #expect(OnboardingIntroStep.introDialog(isReturningUser: true).resumeStep == nil)
        #expect(OnboardingIntroStep.downloadReasonSelection.resumeStep == .downloadReasonSelection)
        #expect(OnboardingIntroStep.searchPrivacySettingsSelection.resumeStep == .searchPrivacySettingsSelection)
        #expect(OnboardingIntroStep.aiSearchSettingsSelection.resumeStep == .aiSearchSettingsSelection)
        #expect(OnboardingIntroStep.aiModelSelection.resumeStep == .aiModelSelection)
        #expect(OnboardingIntroStep.toggleInputModeSelection.resumeStep == .toggleInputModeSelection)
        #expect(OnboardingIntroStep.keepDuckAISelection.resumeStep == .keepDuckAISelection)
        #expect(OnboardingIntroStep.duckPlayerSelection.resumeStep == .duckPlayerSelection)
        #expect(OnboardingIntroStep.setDefaultBrowser.resumeStep == .setDefaultBrowser)
        #expect(OnboardingIntroStep.aiIntro.resumeStep == .aiIntro)
        #expect(OnboardingIntroStep.addToDockPromo.resumeStep == .addToDockPromo)
        #expect(OnboardingIntroStep.appIconSelection.resumeStep == .appIconSelection)
        #expect(OnboardingIntroStep.addressBarPositionSelection.resumeStep == .addressBarPositionSelection)
        #expect(OnboardingIntroStep.searchExperienceSelection.resumeStep == .searchExperienceSelection)
        #expect(OnboardingIntroStep.duckAIQuerySelection.resumeStep == .duckAIQuerySelection)
        #expect(OnboardingIntroStep.interlude(.duckAI).resumeStep == .interludeDuckAI)
    }

    @Test("Check countsTowardProgress excludes the intro dialog, interludes, and the Download Screen")
    func countsTowardProgressExcludesNonProgressSteps() {
        // Steps excluded regardless of flow.
        #expect(OnboardingIntroStep.introDialog(isReturningUser: false).countsTowardProgress(flow: .default) == false)
        #expect(OnboardingIntroStep.interlude(.duckAI).countsTowardProgress(flow: .default) == false)
        #expect(OnboardingIntroStep.downloadReasonSelection.countsTowardProgress(flow: .default) == false)

        // Steps counted regardless of flow.
        #expect(OnboardingIntroStep.setDefaultBrowser.countsTowardProgress(flow: .default) == true)
        #expect(OnboardingIntroStep.aiIntro.countsTowardProgress(flow: .default) == true)
        #expect(OnboardingIntroStep.addToDockPromo.countsTowardProgress(flow: .default) == true)
        #expect(OnboardingIntroStep.appIconSelection.countsTowardProgress(flow: .default) == true)
        #expect(OnboardingIntroStep.addressBarPositionSelection.countsTowardProgress(flow: .default) == true)
        #expect(OnboardingIntroStep.searchExperienceSelection.countsTowardProgress(flow: .default) == true)
    }

    @Test("Check countsTowardProgress counts the Duck.ai query step only in the Duck.ai flow")
    func countsTowardProgressForDuckAIQueryDependsOnFlow() {
        #expect(OnboardingIntroStep.duckAIQuerySelection.countsTowardProgress(flow: .duckAI) == true)
        #expect(OnboardingIntroStep.duckAIQuerySelection.countsTowardProgress(flow: .default) == false)
    }

}

@Suite("Onboarding - Download Reason Experiment")
struct OnboardingDownloadReasonExperimentTests {

    typealias Cohort = FeatureFlag.OnboardingFlowByDownloadReasonExperimentCohort

    // MARK: - Enrollment / pixel bucket

    @Test("Experiment users keep the .default flow but report under the tailored pixel", arguments: [Cohort.control, Cohort.treatment])
    func treatmentReportsTailoredPixel(_ cohort: Cohort) {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: PrivacyConfig.MockFeatureFlagger(resolveCohortStub: cohort),
            variantManager: OnboardingManagerVariants.newUserVariantManagerMock,
            isIphone: true,
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )

        // WHEN
        sut.configureOnboardingFlow(from: nil)

        // THEN
        #expect(tutorialSettings.onboardingFlowType == .default)
        #expect(sharedPixelStorage.onboardingFlow == .tailoredByDownloadReason)
    }

    @Test("Users not enrolled in the experiment report default flow pixel")
    func usersNotEnrolledInExperimentReportExpectedPixel() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: PrivacyConfig.MockFeatureFlagger(),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )

        // WHEN
        sut.configureOnboardingFlow(from: nil)

        // THEN
        #expect(tutorialSettings.onboardingFlowType == .default)
        #expect(sharedPixelStorage.onboardingFlow == .default)
    }

    @Test("Duck.ai flow users report duckAI pixel")
    func duckAIFlowUsersReportDuckAiPixel() {
        // GIVEN
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: PrivacyConfig.MockFeatureFlagger(
                featuresStub: [FeatureFlag.onboardingDuckAIFlow.rawValue: true],
                resolveCohortStub: Cohort.treatment
            ),
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )

        // WHEN
        sut.configureOnboardingFlow(from: URL(string: "ddgCPP://duckAI"))

        // THEN
        #expect(tutorialSettings.onboardingFlowType == .duckAI)
        #expect(sharedPixelStorage.onboardingFlow == .duckAI)
    }

    // MARK: - Steps

    @Test("Treatment users start with just the intro and the Download Screen before a reason is chosen")
    func treatmentStartsWithDownloadReasonStep() {
        // GIVEN
        let sut = makeManager(cohort: .treatment)

        // THEN
        #expect(sut.onboardingSteps == [.introDialog(isReturningUser: false), .downloadReasonSelection])
    }

    @Test("Treatment rebuilds the full flow once a reason is persisted (resume)")
    func treatmentRebuildsFullFlowAfterReason() {
        // GIVEN
        let tutorialSettings = makeTutorialSettings()
        tutorialSettings.onboardingDownloadReason = .blockAds
        let sut = makeManager(cohort: .treatment, tutorialSettings: tutorialSettings)
        let expected: [OnboardingIntroStep] = [.introDialog(isReturningUser: false), .downloadReasonSelection] + sut.selectDownloadReason(.blockAds)

        // THEN
        #expect(sut.onboardingSteps == expected)
    }

    @Test("Control users get the standard default flow")
    func controlGetsStandardFlow() {
        // GIVEN
        let sut = makeManager(cohort: .control)

        // THEN
        #expect(sut.onboardingSteps == OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false))
    }

    @Test("Users not enrolled in the experiment get the standard default flow")
    func unenrolledGetsStandardFlow() {
        // GIVEN
        let sut = makeManager(cohort: nil)

        // THEN
        #expect(sut.onboardingSteps == OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false))
    }

    @Test("selectDownloadReason persists the reason", arguments: OnboardingDownloadReason.allCases)
    func selectDownloadReasonPersistsReason(_ reason: OnboardingDownloadReason) {
        // GIVEN
        let tutorialSettings = makeTutorialSettings()
        let sut = makeManager(cohort: .treatment, tutorialSettings: tutorialSettings)

        // WHEN
        _ = sut.selectDownloadReason(reason)

        // THEN
        #expect(tutorialSettings.onboardingDownloadReason == reason)
    }

    @Test(
        "selectDownloadReason returns the reason-tailored steps",
        arguments: zip(
            [
                .browserPrivately,
                .privateAIChat,
                .noAI,
                .blockAds
            ] as [OnboardingDownloadReason],
            [
                [.setDefaultBrowser, .searchPrivacySettingsSelection, .searchExperienceSelection, .addressBarPositionSelection, .addToDockPromo, .appIconSelection, .duckAIQuerySelection],
                [.setDefaultBrowser, .aiModelSelection, .toggleInputModeSelection, .addressBarPositionSelection, .addToDockPromo, .appIconSelection, .duckAIQuerySelection],
                [.setDefaultBrowser, .aiSearchSettingsSelection, .keepDuckAISelection, .addressBarPositionSelection, .addToDockPromo, .appIconSelection, .duckAIQuerySelection],
                [.setDefaultBrowser, .duckPlayerSelection, .searchExperienceSelection, .addressBarPositionSelection, .addToDockPromo, .appIconSelection, .duckAIQuerySelection],
            ] as [[OnboardingIntroStep]]
        )
    )
    func selectDownloadReasonReturnsTailoredSteps(_ reason: OnboardingDownloadReason, _ expected: [OnboardingIntroStep]) {
        // GIVEN
        let sut = makeManager(cohort: .treatment)

        // WHEN
        let result = sut.selectDownloadReason(reason)

        // THEN
        #expect(result == expected)
    }

    // MARK: - Eligibility (new installers, iPhone)

    @Test("iPad users are not enrolled even in the treatment cohort")
    func iPadUsersAreNotEnrolled() {
        // GIVEN
        let sut = makeManager(cohort: .treatment, isIphone: false)

        // THEN
        #expect(sut.onboardingSteps == OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false))
    }

    @Test("Returning users are not enrolled even in the treatment cohort")
    func returningUsersAreNotEnrolled() {
        // GIVEN
        let sut = makeManager(cohort: .treatment, variantManager: OnboardingManagerVariants.returningUserVariantManagerMock)

        // THEN
        #expect(sut.onboardingSteps == OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true))
    }

    @Test("Ineligible users report the default pixel, not the tailored one")
    func ineligibleUsersReportDefaultPixel() {
        // GIVEN — iPad user is ineligible even in the treatment cohort.
        let sharedPixelStorage = makePixelStore()
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        let sut = OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: PrivacyConfig.MockFeatureFlagger(resolveCohortStub: Cohort.treatment),
            variantManager: OnboardingManagerVariants.newUserVariantManagerMock,
            isIphone: false,
            tutorialSettings: tutorialSettings,
            sharedPixelsStorage: sharedPixelStorage
        )

        // WHEN
        sut.configureOnboardingFlow(from: nil)

        // THEN
        #expect(sharedPixelStorage.onboardingFlow == .default)
    }

    // MARK: - Helpers

    private func makeTutorialSettings() -> MockTutorialSettings {
        let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
        tutorialSettings.onboardingFlowType = .default
        return tutorialSettings
    }

    private func makeManager(
        cohort: Cohort?,
        isIphone: Bool = true,
        variantManager: VariantManager = OnboardingManagerVariants.newUserVariantManagerMock,
        tutorialSettings: MockTutorialSettings? = nil
    ) -> OnboardingManager {
        OnboardingManager(
            appDefaults: AppSettingsMock(),
            featureFlagger: PrivacyConfig.MockFeatureFlagger(resolveCohortStub: cohort),
            variantManager: variantManager,
            isIphone: isIphone,
            tutorialSettings: tutorialSettings ?? makeTutorialSettings()
        )
    }

    private func makePixelStore() -> any KeyedStoring<OnboardingSharedPixelsKeys> {
        InMemoryKeyValueStore().keyedStoring()
    }
}
