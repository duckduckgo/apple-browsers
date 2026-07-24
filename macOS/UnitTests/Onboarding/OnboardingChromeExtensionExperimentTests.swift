//
//  OnboardingChromeExtensionExperimentTests.swift
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

import FeatureFlags
import PixelExperimentKit
import PixelKit
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingChromeExtensionExperimentTests: XCTestCase {

    private var firedEvents: [PixelKitEvent]!

    override func setUp() {
        firedEvents = []
    }

    override func tearDown() {
        firedEvents = nil
    }

    func testEnrollCallsResolveCohort() {
        let cohort = FeatureFlag.OnboardingChromeExtensionCohort.treatment
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingChromeExtensionExperiment(featureFlagger: featureFlagger)

        experiment.enroll()

        XCTAssertEqual(experiment.cohort, cohort)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testCohortReadsAssignedCohortWithoutResolving() {
        let cohort = FeatureFlag.OnboardingChromeExtensionCohort.control
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingChromeExtensionExperiment(featureFlagger: featureFlagger)

        XCTAssertEqual(experiment.cohort, cohort)
        XCTAssertTrue(featureFlagger.didCallAssignedCohort)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testCohortIsNilWhenNotAssigned() {
        let featureFlagger = MockFeatureFlagger()
        let experiment = OnboardingChromeExtensionExperiment(featureFlagger: featureFlagger)

        XCTAssertNil(experiment.cohort)
    }

    func testFireMetricDoesNotFireWhenNotEnrolled() {
        let featureFlagger = MockFeatureFlagger()
        let experiment = OnboardingChromeExtensionExperiment(featureFlagger: featureFlagger)
        configureExperimentKit(cohort: nil, featureFlagger: featureFlagger)

        experiment.fireMetric(.setAsDefault)

        XCTAssertTrue(firedEvents.isEmpty)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testFireMetricFiresWhenEnrolled() {
        let cohort = FeatureFlag.OnboardingChromeExtensionCohort.control
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        let experiment = OnboardingChromeExtensionExperiment(featureFlagger: featureFlagger)
        configureExperimentKit(cohort: cohort, featureFlagger: featureFlagger)

        experiment.fireMetric(.setAsDefault)

        XCTAssertTrue(firedEvents.contains(where: { $0.parameters?["metric"] == "setAsDefault" }))
    }
}

private extension OnboardingChromeExtensionExperimentTests {
    func configureExperimentKit(cohort: FeatureFlag.OnboardingChromeExtensionCohort?,
                                featureFlagger: MockFeatureFlagger) {
        if let cohort {
            let subfeatureID = MacOSBrowserConfigSubfeature.onboardingChromeExtension.rawValue
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
            fire: { event, _, _ in self.firedEvents.append(event) }
        )
    }
}
