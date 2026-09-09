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
@_spi(Testing) import Persistence
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

    @MainActor
    func testContextualInitializationSurvivesResumeAndPreservesProgressAndDismissal() {
        let store = MockKeyValueFileStore()
        let experiment = OnboardingNonBlockingExperiment(
            featureFlagger: MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment))
        let updater = MockContextualOnboardingState()
        experiment.initializeContextualOnboarding(updater, persistor: OnboardingExperimentPersistor(keyValueStore: store))
        XCTAssertEqual(updater.state, .notStarted)

        for state in [ContextualOnboardingState.ongoing, .onboardingCompleted] {
            updater.state = state
            experiment.initializeContextualOnboarding(updater, persistor: OnboardingExperimentPersistor(keyValueStore: store))
            XCTAssertEqual(updater.state, state)
        }
    }

    func testOutcomeIsDurableAndCannotChangeAfterSkip() {
        let store = MockKeyValueFileStore()
        let persistor = OnboardingExperimentPersistor(keyValueStore: store)
        XCTAssertTrue(persistor.record(.skipped))

        let restored = OnboardingExperimentPersistor(keyValueStore: store)
        XCTAssertEqual(restored.outcome, .skipped)
        XCTAssertFalse(restored.record(.completed))
        XCTAssertEqual(restored.outcome, .skipped)
    }

    func testFailedOutcomeWriteDoesNotReportSuccessOrNotifyObservers() {
        let store = MockKeyValueFileStore()
        store.shouldThrowOnSet = true
        let persistor = OnboardingExperimentPersistor(keyValueStore: store)
        let observer = NotificationCenter.default.addObserver(forName: OnboardingExperimentPersistor.outcomeDidChange,
                                                              object: nil, queue: nil) { _ in
            XCTFail("A failed write must not announce a stored outcome change")
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertFalse(persistor.record(.skipped))
        XCTAssertNil(persistor.outcome)
    }

    func testExplicitResetAllowsANewOnboardingSession() {
        let persistor = OnboardingExperimentPersistor(keyValueStore: MockKeyValueFileStore())
        persistor.contextualInitialized = true
        persistor.record(.skipped)

        persistor.reset()

        XCTAssertFalse(persistor.contextualInitialized)
        XCTAssertNil(persistor.outcome)
        XCTAssertTrue(persistor.record(.completed))
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

    func testInternalBuildsDoNotEnrollEvenWithTheLocalTreatmentEnabled() {
        for keyPath in [\ApplicationBuildTypeMock.isDebugBuild, \.isReviewBuild, \.isAlphaBuild] {
            let buildType = ApplicationBuildTypeMock()
            buildType[keyPath: keyPath] = true
            let flags = MockFeatureFlagger()
            flags.enabledFeatureFlags = [.onboardingAsync]
            let experiment = OnboardingNonBlockingExperiment(featureFlagger: flags)

            experiment.enroll(buildType: buildType)

            XCTAssertFalse(flags.didCallResolveCohort)
            XCTAssertTrue(experiment.isNonBlocking)
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

    func testContextualDismissalRecordsBooleanMarkerWithoutEnrollingUsers() {
        let flags = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        configureExperimentKit(cohort: .treatment, featureFlagger: flags)
        OnboardingNonBlockingExperiment(featureFlagger: flags).fireMetric(.contextualDismissed)
        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "contextualDismissed")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "true")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-7")
        XCTAssertFalse(flags.didCallResolveCohort)
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
