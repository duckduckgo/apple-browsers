//
//  OnboardingNonBlockingExperimentTests.swift
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
import PixelExperimentKit
import PixelKit
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingNonBlockingExperimentTests: XCTestCase {

    private var firedEvents: [PixelKit.Event]!

    override func setUp() {
        firedEvents = []
    }

    override func tearDown() {
        firedEvents = nil
    }

    func testEnrollCallsResolveCohort() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.treatment
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)

        experiment.enroll()

        XCTAssertEqual(experiment.cohort, cohort)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testCohortReadsAssignedCohortWithoutResolving() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.control
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)

        XCTAssertEqual(experiment.cohort, cohort)
        XCTAssertTrue(featureFlagger.didCallAssignedCohort)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testCohortIsNilWhenNotAssigned() {
        let featureFlagger = MockFeatureFlagger()
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)

        XCTAssertNil(experiment.cohort)
    }

    func testIsNonBlockingIsTrueWhenLocalFlagIsOn() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.onboardingAsync]
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)

        XCTAssertTrue(experiment.isNonBlocking)
    }

    func testIsNonBlockingIsTrueWhenCohortIsTreatment() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.treatment
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)

        XCTAssertTrue(experiment.isNonBlocking)
    }

    func testIsNonBlockingIsFalseOtherwise() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.control
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)

        XCTAssertFalse(experiment.isNonBlocking)
    }

    func testFireMetricDoesNotFireWhenNotEnrolled() {
        let featureFlagger = MockFeatureFlagger()
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)
        configureExperimentKit(cohort: nil, featureFlagger: featureFlagger)

        experiment.fireMetric(.onboardingCompleted)

        XCTAssertTrue(firedEvents.isEmpty)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testFireMetricFiresWhenEnrolled() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.control
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)
        configureExperimentKit(cohort: cohort, featureFlagger: featureFlagger)

        experiment.fireMetric(.onboardingCompleted)

        XCTAssertTrue(firedEvents.contains(where: { $0.parameters?["metric"] == "onboardingCompleted" }))
    }

    func testConversionWindowsForOneFiveSevenDayMetrics() {
        let expectedWindows: [ClosedRange<Int>] = [0...1, 0...5, 0...7]

        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.onboardingCompleted.conversionWindows, expectedWindows)
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.onboardingSkipped.conversionWindows, expectedWindows)
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.importRequested.conversionWindows, expectedWindows)
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.addToDockRequested.conversionWindows, expectedWindows)
    }

    func testConversionWindowsForBrowsingBeforeCompletion() {
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.browsingBeforeCompletion.conversionWindows, [0...7])
    }

    func testConversionWindowsForSetAsDefaultEnabled() {
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.setAsDefaultEnabled.conversionWindows, [5...7])
    }
}

private extension OnboardingNonBlockingExperimentTests {
    func configureExperimentKit(cohort: FeatureFlag.OnboardingNonBlockingCohort?,
                                featureFlagger: MockFeatureFlagger) {
        if let cohort {
            let subfeatureID = MacOSBrowserConfigSubfeature.onboardingNonBlocking.rawValue
            featureFlagger.allActiveExperiments = [
                subfeatureID: ExperimentData(
                    parentID: PrivacyFeature.macOSBrowserConfig.rawValue,
                    cohortID: cohort.rawValue,
                    enrollmentDate: Date()
                )
            ]
        } else {
            featureFlagger.allActiveExperiments = [:]
        }
        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
            fire: { [weak self] event, _, _ in self?.firedEvents?.append(event) }
        )
    }
}
