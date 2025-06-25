//
//  OnboardingManager+SetDefaultBrowserPipVideoExperimentTests.swift
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

@Suite("Set As Default Browser Picture In Picture Video Experiment Tests")
final class OnboardingManagerSetDefaultBrowserPipVideoExperimentTests {
    private static let isUnsupportedOSVersionForExperiment: Bool = {
        if #available(iOS 18.2, *) {
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
        "Check cohorts are not assigned to returning users",
        arguments: zip(
            [
                (VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: []), OnboardingSetAsDefaultBrowserPiPVideoCohort.control),
                (VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: []), OnboardingSetAsDefaultBrowserPiPVideoCohort.treatment),
                (VariantIOS.returningUser, .control),
                (VariantIOS.returningUser, .treatment)
            ],
            [
                OnboardingSetAsDefaultBrowserPiPVideoCohort.control,
                .treatment,
                nil,
                nil
            ]
        )
    )
    @available(iOS 18.2, *)
    func checkIsSetAsDefaultBrowserEnabledReturnsCorrectValue(_ variantContext: (variant: VariantIOS, cohortToAssign: OnboardingSetAsDefaultBrowserPiPVideoCohort?), expectedCohort: OnboardingSetAsDefaultBrowserPiPVideoCohort?) {
        variantManagerMock.currentVariant = variantContext.variant
        featureFlaggerMock.cohortToReturn = variantContext.cohortToAssign
        makeSUT()

        // WHEN
        let result = sut.resolveSetAsDefaultBrowserPipVideoExperimentCohort(isPictureInPictureSupported: true)

        // THEN
        #expect(result == expectedCohort)
    }

    @Test("Check Users should not be enrolled in experiment if iOS < 18.2", .enabled(if: Self.isUnsupportedOSVersionForExperiment))
    func checkIsSetAsDefaultBrowserDisabledForUnsupportedOSVersions() {
        // GIVEN
        variantManagerMock.currentVariant = VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: [])

        // WHEN
        let result = sut.isEnrolledInSetAsDefaultBrowserPipVideoExperiment

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
    @available(iOS 18.2, *)
    func checkCorrectExperimentEnrollment(_ context: (variant: VariantIOS, expectedResult: Bool)) {
        // GIVEN
        variantManagerMock.currentVariant = context.variant
        makeSUT()

        // WHEN
        _ = sut.resolveSetAsDefaultBrowserPipVideoExperimentCohort(isPictureInPictureSupported: true)

        // THEN
        #expect(featureFlaggerMock.didCallResolveCohort == context.expectedResult)
    }

    @Test("Check Cohort is not resolved if iOS < 18.2", .enabled(if: Self.isUnsupportedOSVersionForExperiment))
    func checkExperimentNotRunOnUnsupportedOSVersion() {
        // GIVEN
        variantManagerMock.currentVariant = VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: [])

        // WHEN
        _ = sut.resolveSetAsDefaultBrowserPipVideoExperimentCohort(isPictureInPictureSupported: true)

        // THEN
        #expect(!featureFlaggerMock.didCallResolveCohort)
    }

    @Test(
        "Check Users should not be enrolled in experiment if PiP is not supported",
        arguments: [
            OnboardingSetAsDefaultBrowserPiPVideoCohort.control,
            OnboardingSetAsDefaultBrowserPiPVideoCohort.treatment
        ],
        [
            true,
            false
        ]
    )
    @available(iOS 18.2, *)
    func checkIsSetAsDefaultBrowserDisabledForUnsupportedOSVersions(cohort: OnboardingSetAsDefaultBrowserPiPVideoCohort, isPictureInPictureSupported: Bool) {
        // GIVEN
        featureFlaggerMock.cohortToReturn = cohort
        variantManagerMock.currentVariant = VariantIOS(name: "zz", weight: 0, isIncluded: VariantIOS.When.always, features: [])

        // WHEN
        let result = sut.resolveSetAsDefaultBrowserPipVideoExperimentCohort(isPictureInPictureSupported: isPictureInPictureSupported)

        // THEN
        let expectedCohort = isPictureInPictureSupported ? cohort : nil
        #expect(result == expectedCohort)
    }

}
