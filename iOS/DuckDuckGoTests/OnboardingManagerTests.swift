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

        @Test("Check correct onboarding steps are returned for iPhone")
        func checkOnboardingSteps_iPhone() async throws {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: true)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == OnboardingIntroStep.newUserSteps(isIphone: true))
        }

        @Test("Check correct onboarding steps are returned for iPad")
        func checkOnboardingSteps_iPad() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == OnboardingIntroStep.newUserSteps(isIphone: false))
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

        @Test("Check correct onboarding steps are returned for iPhone")
        func checkOnboardingSteps_iPhone() async throws {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: true)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == OnboardingIntroStep.returningUserSteps(isIphone: true))
        }

        @Test("Check correct onboarding steps are returned for iPad")
        func checkOnboardingSteps_iPad() {
            // GIVEN
            let sut = OnboardingManager(appDefaults: AppSettingsMock(), featureFlagger: MockFeatureFlagger(), variantManager: variantManagerMock, isIphone: false)

            // WHEN
            let result = sut.onboardingSteps

            // THEN
            #expect(result == OnboardingIntroStep.returningUserSteps(isIphone: false))
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
