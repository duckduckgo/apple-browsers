//
//  TopSitesPickerExperimentTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import FeatureFlags_macOS
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class TopSitesPickerExperimentTests: XCTestCase {

    func testShouldShowStep_WhenFewerThanFiveFavoritesAndResolvedToTreatment_EnrolsAndShowsStep() {
        let featureFlagger = flagger(cohort: .treatment, isAlreadyAssigned: false)
        let experiment = makeExperiment(featureFlagger: featureFlagger, favoritesCount: 4)

        let shouldShow = experiment.shouldShowStep()

        XCTAssertTrue(shouldShow)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testShouldShowStep_WhenResolvedToControl_HidesStep() {
        let featureFlagger = flagger(cohort: .control, isAlreadyAssigned: false)
        let experiment = makeExperiment(featureFlagger: featureFlagger, favoritesCount: 0)

        let shouldShow = experiment.shouldShowStep()

        XCTAssertFalse(shouldShow)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testShouldShowStep_WhenFiveFavorites_HidesStepWithoutEnrolling() {
        let featureFlagger = flagger(cohort: .treatment, isAlreadyAssigned: false)
        let experiment = makeExperiment(featureFlagger: featureFlagger, favoritesCount: 5)

        let shouldShow = experiment.shouldShowStep()

        XCTAssertFalse(shouldShow)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testShouldShowStep_WhenAlreadyAssigned_UsesAssignedCohortWithoutResolving() {
        let featureFlagger = flagger(cohort: .treatment, isAlreadyAssigned: true)
        let experiment = makeExperiment(featureFlagger: featureFlagger, favoritesCount: 5)

        let shouldShow = experiment.shouldShowStep()

        XCTAssertTrue(shouldShow)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testIsStepOffered_WhenFlagOffAndNoCohort_DoesNotOfferStep() {
        let featureFlagger = flagger(cohort: nil, isAlreadyAssigned: false, isFlagOn: false)
        let experiment = makeExperiment(featureFlagger: featureFlagger, favoritesCount: 0)

        let isOffered = experiment.isStepOffered

        XCTAssertFalse(isOffered)
    }

    func testIsStepOffered_WhenFlagTurnsOnWhileRunning_OffersStep() {
        let featureFlagger = flagger(cohort: nil, isAlreadyAssigned: false, isFlagOn: false)
        let experiment = makeExperiment(featureFlagger: featureFlagger, favoritesCount: 0)

        featureFlagger.featuresStub = [FeatureFlag.onboardingFavoritesStepExperiment.rawValue: true]

        XCTAssertTrue(experiment.isStepOffered)
    }

    func testIsStepOffered_WhenFlagTurnsOffAfterAssignment_KeepsOfferingStep() {
        let featureFlagger = flagger(cohort: .control, isAlreadyAssigned: true)
        let experiment = makeExperiment(featureFlagger: featureFlagger, favoritesCount: 0)

        featureFlagger.featuresStub = [:]

        XCTAssertTrue(experiment.isStepOffered)
    }
}

private extension TopSitesPickerExperimentTests {

    func flagger(
        cohort: FeatureFlag.OnboardingFavoritesStepCohort?,
        isAlreadyAssigned: Bool,
        isFlagOn: Bool = true
    ) -> MockFeatureFlagger {
        MockFeatureFlagger(
            featuresStub: [FeatureFlag.onboardingFavoritesStepExperiment.rawValue: isFlagOn],
            resolveCohortStub: cohort,
            isAlreadyAssigned: isAlreadyAssigned
        )
    }

    func makeExperiment(featureFlagger: MockFeatureFlagger, favoritesCount: Int) -> TopSitesPickerExperiment {
        let favorites = (0..<favoritesCount).map {
            Bookmark(id: UUID().uuidString, url: "https://site\($0).com/", title: "Site \($0)", isFavorite: true)
        }
        let bookmarkManager = MockBookmarkManager(list: BookmarkList(entities: favorites, favorites: favorites))
        return TopSitesPickerExperiment(featureFlagger: featureFlagger, bookmarkManager: bookmarkManager)
    }
}
