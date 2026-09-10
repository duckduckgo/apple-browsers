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
        PixelKit.configureExperimentKit(featureFlagger: MockFeatureFlagger(),
                                        eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
                                        fire: { _, _, _ in })
        firedEvents = nil
    }

    func testSearchUnionWindowIncludesOnlyDaysOneThroughThree() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.treatment
        for day in [0, 1, 2, 3, 4] {
            firedEvents = []
            let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
            configureExperimentKit(cohort: cohort, featureFlagger: featureFlagger,
                                   enrollmentDate: Calendar.current.date(byAdding: .day, value: -day, to: Date())!)
            StatisticsLoader.fireOnboardingNonBlockingSearchRetentionExperimentPixel()
            let searchEvents = firedEvents.filter { $0.parameters?["metric"] == "search" }
            XCTAssertEqual(searchEvents.count, (1...3).contains(day) ? 1 : 0, "Day \(day)")
        }
    }

    func testEnrollCallsResolveCohort() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.treatment
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)

        experiment.enroll(buildType: ApplicationBuildTypeMock())

        XCTAssertEqual(experiment.cohort, cohort)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testInternalBuildsDoNotEnrollEvenWithTheFunctionalFlagEnabled() {
        for keyPath in [\ApplicationBuildTypeMock.isDebugBuild, \.isReviewBuild, \.isAlphaBuild] {
            let buildType = ApplicationBuildTypeMock()
            buildType[keyPath: keyPath] = true
            let flags = MockFeatureFlagger()
            flags.enabledFeatureFlags = [.onboardingAsync]
            let experiment = OnboardingNonBlockingExperiment(featureFlagger: flags)

            experiment.enroll(buildType: buildType)

            XCTAssertFalse(flags.didCallResolveCohort)
            XCTAssertFalse(NonBlockingOnboarding(featureFlagger: flags).isNonBlocking)
        }
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

    func testIsNonBlockingDependsOnlyOnTreatment() {
        let cases: [(FeatureFlag.OnboardingNonBlockingCohort?, Bool, Bool)] = [
            (nil, false, false), (nil, true, false),
            (.treatment, false, true), (.treatment, true, true),
            (.control, false, false), (.control, true, false)
        ]
        for (cohort, localFlag, expected) in cases {
            let featureFlagger = cohort.map { MockFeatureFlagger(resolveCohortStub: $0) } ?? MockFeatureFlagger()
            featureFlagger.enabledFeatureFlags = localFlag ? [.onboardingAsync] : []
            XCTAssertEqual(NonBlockingOnboarding(featureFlagger: featureFlagger).isNonBlocking, expected,
                           "Cohort: \(String(describing: cohort)), local flag: \(localFlag)")
        }
    }

    func testFireMetricDoesNotFireWhenNotEnrolled() {
        let featureFlagger = MockFeatureFlagger()
        let experiment = OnboardingNonBlockingExperiment(featureFlagger: featureFlagger)
        configureExperimentKit(cohort: nil, featureFlagger: featureFlagger)

        experiment.fireMetric(.importRequested)

        XCTAssertTrue(firedEvents.isEmpty)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testMetricsFireOnlyWithinTheirWindowsForBothCohorts() {
        for cohort in [FeatureFlag.OnboardingNonBlockingCohort.control, .treatment] {
            for day in [0, 1, 4, 5, 7, 8] {
                firedEvents = []
                let flags = MockFeatureFlagger(resolveCohortStub: cohort)
                configureExperimentKit(cohort: cohort, featureFlagger: flags,
                                       enrollmentDate: Calendar.current.date(byAdding: .day, value: -day, to: Date())!)
                let experiment = OnboardingNonBlockingExperiment(featureFlagger: flags)

                experiment.fireMetric(.importRequested)
                experiment.fireMetric(.addToDockRequested)
                experiment.fireMetric(.setAsDefaultEnabled)

                let expectedMetrics: Set<String> = day == 0 ? ["importRequested", "addToDockRequested"]
                    : (5...7).contains(day) ? ["setAsDefaultEnabled"] : []
                XCTAssertEqual(Set(firedEvents.compactMap { $0.parameters?["metric"] }), expectedMetrics, "Day \(day)")
                XCTAssertEqual(firedEvents.count, expectedMetrics.count)
            }
        }
    }

    func testActionMetricsUseOnlyDayZero() {
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.importRequested.conversionWindows, [0...0])
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.addToDockRequested.conversionWindows, [0...0])
    }

    func testConversionWindowsForSetAsDefaultEnabled() {
        XCTAssertEqual(OnboardingNonBlockingExperiment.Metric.setAsDefaultEnabled.conversionWindows, [5...7])
    }

}

private extension OnboardingNonBlockingExperimentTests {
    func configureExperimentKit(cohort: FeatureFlag.OnboardingNonBlockingCohort?,
                                featureFlagger: MockFeatureFlagger,
                                enrollmentDate: Date = Date()) {
        if let cohort {
            let subfeatureID = MacOSBrowserConfigSubfeature.onboardingNonBlocking.rawValue
            featureFlagger.allActiveExperiments = [
                subfeatureID: ExperimentData(
                    parentID: PrivacyFeature.macOSBrowserConfig.rawValue,
                    cohortID: cohort.rawValue,
                    enrollmentDate: enrollmentDate
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
