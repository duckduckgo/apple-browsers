//
//  OnboardingManager+SetDefaultBrowserExperimentTests.swift
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
@testable import Core
@testable import DuckDuckGo

@Suite("Set As Default Browser Experiment Tests")
final class OnboardingManagerSetDefaultBrowserExperimentTests {
    private static let isUnsupportedOSVersionForExperiment: Bool = {
        if #available(iOS 18.3, *) {
            false
        } else {
            true
        }
    }()

    private var sut: OnboardingManager!
    private var featureFlaggerMock: MockFeatureFlagger!
    private var variantManagerMock: MockVariantManager!

    init() {
        featureFlaggerMock = MockFeatureFlagger()
        variantManagerMock = MockVariantManager()
        makeSUT()
    }

    func makeSUT() {
        sut = OnboardingManager(
            featureFlagger: featureFlaggerMock,
            variantManager: variantManagerMock,
            isIphone: true
        )
    }

    @Test(
        "Check isSetAsDefaultBrowserEnabled returns correct value based on cohort",
        arguments: zip(
            [
                (VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: []), OnboardingSetAsDefaultBrowserCohort.control),
                (VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: []), OnboardingSetAsDefaultBrowserCohort.treatment),
                (VariantIOS.returningUser, .control),
                (VariantIOS.returningUser, .treatment)
            ],
            [
                OnboardingSetAsDefaultBrowserCohort.control,
                .treatment,
                nil,
                nil
            ]
        )
    )
    @available(iOS 18.3, *)
    func checkIsSetAsDefaultBrowserEnabledReturnsCorrectValue(_ variantContext: (variant: VariantIOS, cohortToAssign: OnboardingSetAsDefaultBrowserCohort?), expectedCohort: OnboardingSetAsDefaultBrowserCohort?) {
        variantManagerMock.currentVariant = variantContext.variant
        featureFlaggerMock.cohortToReturn = variantContext.cohortToAssign
        makeSUT()

        // WHEN
        let result = sut.resolveSetAsDefaultBrowserExperimentCohort()

        // THEN
        #expect(result == expectedCohort)
    }

    @Test("Check isSetAsDefaultBrowserEnabled returns false for iOS < 18.3", .enabled(if: Self.isUnsupportedOSVersionForExperiment))
    func checkIsSetAsDefaultBrowserDisabledForUnsupportedOSVersions() {
        // GIVEN
        variantManagerMock.currentVariant = VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: [])

        // WHEN
        let result = sut.isEnrolledInSetAsDefaultBrowserExperiment

        // THEN
        #expect(!result)
    }

    @Test(
        "Check Cohort is resolved for new users only",
        arguments: [
            (VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: []), true),
            (VariantIOS.returningUser, false),
        ]
    )
    @available(iOS 18.3, *)
    func checkCorrectExperimentEnrollment(_ context: (variant: VariantIOS, expectedResult: Bool)) {
        // GIVEN
        variantManagerMock.currentVariant = context.variant
        makeSUT()

        // WHEN
        _ = sut.resolveSetAsDefaultBrowserExperimentCohort()

        // THEN
        #expect(featureFlaggerMock.didCallResolveCohort == context.expectedResult)
    }

    @Test("Check Experiment is not run for iOS < 18.3", .enabled(if: Self.isUnsupportedOSVersionForExperiment))
    func checkExperimentNotRunOnUnsupportedOSVersion() {
        // GIVEN
        variantManagerMock.currentVariant = VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: [])

        // WHEN
        _ = sut.resolveSetAsDefaultBrowserExperimentCohort()

        // THEN
        #expect(!featureFlaggerMock.didCallResolveCohort)
    }

    @Test(
        "Check Right Settings URL is returned",
        arguments: [
            (OnboardingSetAsDefaultBrowserCohort.control, UIApplication.openSettingsURLString),
            (.treatment, UIApplication.openDefaultApplicationsSettingsURLString),
            (nil, UIApplication.openSettingsURLString)
        ]
    )
    @available(iOS 18.3, *)
    func checkCorrectSettingsURLIsReturned(_ context: (cohort: OnboardingSetAsDefaultBrowserCohort?, expectedURLPath: String)) {
        // GIVEN
        featureFlaggerMock.cohortToReturn = context.cohort

        // WHEN
        let result = sut.settingsURLPath

        // THEN
        #expect(result == context.expectedURLPath)
    }

    @Test("Check Default Settings URL is returned for iOS < 18.3", .enabled(if: Self.isUnsupportedOSVersionForExperiment))
    func checkDefaultSettingsURLIsReturnedForUnsupportedOSVersion() {
        // GIVEN
        let expectedURLString = UIApplication.openSettingsURLString

        // WHEN
        let result = sut.settingsURLPath

        // THEN
        #expect(result == expectedURLString)
    }

}
