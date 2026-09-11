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
@_spi(Testing) import Persistence
import PixelExperimentKit
import PixelKit
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingNonBlockingExperimentTests: XCTestCase {

    private var firedEvents: [PixelKit.Event]!
    private var firedFrequencies: [PixelKit.Frequency]!

    override func setUp() {
        firedEvents = []
        firedFrequencies = []
    }

    override func tearDown() {
        PixelKit.configureExperimentKit(featureFlagger: MockFeatureFlagger(),
                                        eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
                                        fire: { _, _, _ in })
        firedEvents = nil
        firedFrequencies = nil
    }

    func testSearchUnionWindowIncludesOnlyDaysOneThroughThree() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.treatment
        for day in [0, 1, 2, 3, 4] {
            firedEvents = []
            let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
            configureExperimentKit(cohort: cohort, featureFlagger: featureFlagger,
                                   enrollmentDate: Calendar.current.date(byAdding: .day, value: -day, to: Date())!)
            StatisticsLoader.fireOnboardingNonBlockingSearchRetentionExperimentPixel(featureFlagger: featureFlagger,
                                                                                    persistor: makePersistor())
            let searchEvents = firedEvents.filter { $0.parameters?["metric"] == "search" }
            XCTAssertEqual(searchEvents.count, (1...3).contains(day) ? 1 : 0, "Day \(day)")
            let segmentEvents = firedEvents.filter { $0.parameters?["metric"]?.hasPrefix("search_onboarding_") == true }
            XCTAssertEqual(segmentEvents.count, (1...3).contains(day) ? 1 : 0, "Day \(day)")
        }
    }

    func testSearchRetentionSegmentFollowsOnboardingOutcomeForBothCohorts() {
        for cohort in [FeatureFlag.OnboardingNonBlockingCohort.control, .treatment] {
            for outcome in [NonBlockingOnboardingPersistor.Outcome?.none, .skipped, .completed] {
                firedEvents = []
                let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
                configureExperimentKit(cohort: cohort, featureFlagger: featureFlagger,
                                       enrollmentDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
                let persistor = makePersistor()
                if let outcome { persistor.record(outcome) }

                StatisticsLoader.fireOnboardingNonBlockingSearchRetentionExperimentPixel(featureFlagger: featureFlagger,
                                                                                        persistor: persistor)

                // Control cannot search before finishing onboarding, so it always counts as completed.
                let isCompleted = cohort == .control || outcome == .completed
                let expectedSegment = isCompleted ? "search_onboarding_completed" : "search_onboarding_not_completed"
                XCTAssertEqual(Set(firedEvents.compactMap { $0.parameters?["metric"] }), ["search", expectedSegment],
                               "\(cohort) \(String(describing: outcome))")
                XCTAssertTrue(firedEvents.allSatisfy { $0.parameters?["conversionWindowDays"] == "1-3" && $0.parameters?["value"] == "1" })
            }
        }
    }

    /// Once-per-window is enforced by PixelKit's frequency, not by the caller, so both segments can
    /// reach PixelKit for a user who completes onboarding between two searches in the window.
    func testSearchRetentionSegmentsFollowTheCurrentOutcomeAndAreUniqueByParameters() {
        let cohort = FeatureFlag.OnboardingNonBlockingCohort.treatment
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        configureExperimentKit(cohort: cohort, featureFlagger: featureFlagger,
                               enrollmentDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)
        let persistor = makePersistor()

        StatisticsLoader.fireOnboardingNonBlockingSearchRetentionExperimentPixel(featureFlagger: featureFlagger, persistor: persistor)
        persistor.record(.completed)
        StatisticsLoader.fireOnboardingNonBlockingSearchRetentionExperimentPixel(featureFlagger: featureFlagger, persistor: persistor)

        let metrics = firedEvents.compactMap { $0.parameters?["metric"] }
        XCTAssertEqual(metrics, ["search", "search_onboarding_not_completed", "search", "search_onboarding_completed"])
        XCTAssertTrue(firedFrequencies.allSatisfy { $0 == .uniqueByNameAndParameters })
    }

    func testSearchRetentionSegmentsDoNotFireWhenNotEnrolled() {
        let featureFlagger = MockFeatureFlagger()
        configureExperimentKit(cohort: nil, featureFlagger: featureFlagger)

        StatisticsLoader.fireOnboardingNonBlockingSearchRetentionExperimentPixel(featureFlagger: featureFlagger,
                                                                                persistor: makePersistor())

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testEnrollAssignsACohort() {
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)

        OnboardingNonBlockingExperiment(featureFlagger: featureFlagger).enroll()

        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    /// Reading the mode must never enroll: it is checked on searches, tab updates and prompt eligibility,
    /// which would otherwise pull existing users into the experiment.
    func testIsNonBlockingReadsTheAssignedCohortWithoutEnrolling() {
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)

        XCTAssertTrue(OnboardingNonBlockingExperiment(featureFlagger: featureFlagger).isNonBlocking)
        XCTAssertTrue(featureFlagger.didCallAssignedCohort)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
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
    func makePersistor() -> NonBlockingOnboardingPersistor {
        NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
    }

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
            fire: { [weak self] event, frequency, _ in
                self?.firedEvents?.append(event)
                self?.firedFrequencies?.append(frequency)
            }
        )
    }
}
