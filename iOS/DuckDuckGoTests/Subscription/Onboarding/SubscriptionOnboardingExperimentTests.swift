//
//  SubscriptionOnboardingExperimentTests.swift
//  DuckDuckGo
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

import XCTest
import PrivacyConfig
import PixelKit
import PixelExperimentKit
import FeatureFlags_iOS
@testable import DuckDuckGo

final class SubscriptionOnboardingExperimentTests: XCTestCase {

    private var firedEvents: [PixelKit.Event] = []

    override func setUp() {
        super.setUp()
        firedEvents = []
        configurePixelKit(featureFlagger: PrivacyConfig.MockFeatureFlagger())
    }

    override func tearDown() {
        firedEvents = []
        super.tearDown()
    }

    // MARK: - Cohort resolution

    func testResolveCohortReturnsControl() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingJul2026Cohort.control)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger)

        XCTAssertEqual(cohort, .control)
    }

    func testResolveCohortReturnsTreatment() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingJul2026Cohort.treatment)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger)

        XCTAssertEqual(cohort, .treatment)
    }

    func testResolveCohortReturnsNilWhenNotEnrolled() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger)

        XCTAssertNil(cohort)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    // MARK: - VPN activated metric

    func testFireVPNActivatedMetricFiresWhenSubscriptionActiveAndEnrolled() {
        seedActiveExperiment(cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingJul2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "vpnActivated")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-3")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    func testFireVPNActivatedMetricDoesNotFireWhenSubscriptionInactive() {
        seedActiveExperiment(cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testFireVPNActivatedMetricDoesNotFireWhenNotEnrolled() {
        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Duck.ai paid used metric

    func testFireDuckAIPaidUsedMetricFiresWhenSubscriptionActiveAndEnrolled() {
        seedActiveExperiment(cohort: "control")

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingJul2026_control")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "duckAiPaidUsed")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-3")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    func testFireDuckAIPaidUsedMetricDoesNotFireWhenSubscriptionInactive() {
        seedActiveExperiment(cohort: "control")

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetric(isSubscriptionActive: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testFireDuckAIPaidUsedMetricDoesNotFireWhenNotEnrolled() {
        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetric(isSubscriptionActive: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Helpers

    private func configurePixelKit(featureFlagger: FeatureFlagger) {
        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(),
            fire: { [weak self] event, _, _ in self?.firedEvents.append(event) }
        )
    }

    /// Seeds a device already enrolled in `subscriptionOnboardingJul2026`, enrolled today (inside the
    /// experiment's 0-3 day conversion window).
    private func seedActiveExperiment(cohort: String) {
        let experimentData = ExperimentData(
            parentID: PrivacyProSubfeature.subscriptionOnboardingJul2026.parent.rawValue,
            cohortID: cohort,
            enrollmentDate: Date()
        )
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(
            allActiveExperiments: [PrivacyProSubfeature.subscriptionOnboardingJul2026.rawValue: experimentData]
        )
        configurePixelKit(featureFlagger: featureFlagger)
    }
}
