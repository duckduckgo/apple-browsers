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

import Testing
import class UIKit.UIDevice
@testable import Core
@testable import DuckDuckGo

struct OnboardingManagerTests {
    struct OnboardingStepsNewUser {
        let variantManagerMock = MockVariantManager(
            currentVariant: VariantIOS(
                name: "test_variant",
                weight: 0,
                isIncluded: VariantIOS.When.always,
                features: []
            )
        )

        @Test("Check correct onboarding steps are returned for iPhone, when onboardingSearchExperience flag is OFF")
        func checkOnboardingSteps_iPhone_onboardingSearchExperience_off() async throws {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)

            // WHEN
            let result = sut.newUserSteps(isIphone: true)

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPhone, when onboardingSearchExperience flag is ON")
        func checkOnboardingSteps_iPhone_onboardingSearchExperience_on() async throws {
            // GIVEN
            let featureFlagger = MockFeatureFlagger()
            featureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: featureFlagger, variantManager: variantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneStepsWithSearchExperience(isReturningUser: false)

            // WHEN
            let result = sut.newUserSteps(isIphone: true)

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad, when onboardingSearchExperience flag is OFF")
        func checkOnboardingSteps_iPad_onboardingSearchExperience_off() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: false)
            let expectedSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)

            // WHEN
            let result = sut.newUserSteps(isIphone: false)

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad, when onboardingSearchExperience flag is ON")
        func checkOnboardingSteps_iPad_onboardingSearchExperience_on() {
            // GIVEN
            let featureFlagger = MockFeatureFlagger()
            featureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: featureFlagger, variantManager: variantManagerMock, isIphone: false)
            let expectedSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)

            // WHEN
            let result = sut.newUserSteps(isIphone: false)

            // THEN
            #expect(result == expectedSteps)
        }

    }

    struct OnboardingStepsReturningUser {
        let variantManagerMock = MockVariantManager(
            currentVariant: VariantIOS(
                name: "ru",
                weight: 0,
                isIncluded: VariantIOS.When.always,
                features: []
            )
        )

        @Test("Check correct onboarding steps are returned for iPhone, when onboardingSearchExperience flag is OFF")
        func checkOnboardingSteps_iPhone_onboardingSearchExperience_off() async throws {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)

            // WHEN
            let result = sut.returningUserSteps(isIphone: true)

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPhone, when onboardingSearchExperience flag is ON")
        func checkOnboardingSteps_iPhone_onboardingSearchExperience_on() async throws {
            // GIVEN
            let featureFlagger = MockFeatureFlagger()
            featureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: featureFlagger, variantManager: variantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneStepsWithSearchExperience(isReturningUser: true)

            // WHEN
            let result = sut.returningUserSteps(isIphone: true)

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad, when onboardingSearchExperience flag is OFF")
        func checkOnboardingSteps_iPad_onboardingSearchExperience_off() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: false)
            let expectedSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: true)

            // WHEN
            let result = sut.returningUserSteps(isIphone: false)

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned for iPad, when onboardingSearchExperience flag is ON")
        func checkOnboardingSteps_iPad_onboardingSearchExperience_on() {
            // GIVEN
            let featureFlagger = MockFeatureFlagger()
            featureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: featureFlagger, variantManager: variantManagerMock, isIphone: false)
            let expectedSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: true)

            // WHEN
            let result = sut.returningUserSteps(isIphone: false)

            // THEN
            #expect(result == expectedSteps)
        }

    }

    struct OnboardingStepsCorrectFlow {
        let variantManagerMock = MockVariantManager(
            currentVariant: VariantIOS(
                name: "test_variant",
                weight: 0,
                isIncluded: VariantIOS.When.always,
                features: []
            )
        )

        let variantManagerMockRU = MockVariantManager(
            currentVariant: VariantIOS(
                name: "ru",
                weight: 0,
                isIncluded: VariantIOS.When.always,
                features: []
            )
        )

        @Test("Check correct onboarding steps are returned, new user")
        func checkOnboardingStepsNewUser() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: true)
            let expectedSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == expectedSteps)
        }

        @Test("Check correct onboarding steps are returned, returning user")
        func checkOnboardingStepsReturningUser() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMockRU, isIphone: true)
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
