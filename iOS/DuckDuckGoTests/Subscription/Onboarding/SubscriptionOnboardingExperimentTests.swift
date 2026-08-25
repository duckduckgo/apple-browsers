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

    private static let enUS = Locale(identifier: "en_US")
    private static let nonEnUS = Locale(identifier: "fr_FR")

    func testResolveCohortEnrollsAndReturnsControlWhenEligibleAndNotYetEnrolled() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.control, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(cohort, .control)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testResolveCohortEnrollsAndReturnsTreatmentWhenEligibleAndNotYetEnrolled() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(cohort, .treatment)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testResolveCohortReturnsNilWhenNotEnrolled() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertNil(cohort)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testResolveCohortDoesNotEnrollWhenLocaleIsNotEnUS() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.nonEnUS)

        XCTAssertNil(cohort)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testResolveCohortDoesNotEnrollWhenNotOnFreeTrial() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.enUS)

        XCTAssertNil(cohort)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testResolveCohortReturnsExistingCohortEvenWhenNoLongerEligible() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.nonEnUS)

        XCTAssertEqual(cohort, .treatment)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    // MARK: - Enrolled-in-treatment read

    func testIsEnrolledInTreatmentReturnsTrueForAnAssignedTreatmentCohort() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment)

        XCTAssertTrue(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testIsEnrolledInTreatmentReturnsFalseForAnAssignedControlCohort() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.control)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
    }

    func testIsEnrolledInTreatmentReturnsFalseWhenNotEnrolled() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
    }

    // MARK: - Settings re-entry

    func testSettingsReEntryEnabledOnlyWhenAllThreeConditionsHold() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment)

        XCTAssertTrue(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: true))
    }

    func testSettingsReEntryDisabledWhenFlowNeverStarted() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: false, hasActiveSubscription: true))
    }

    func testSettingsReEntryDisabledWhenNoLongerInTreatment() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.control)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: true))
    }

    func testSettingsReEntryDisabledWhenSubscriptionNoLongerActive() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: false))
    }

    // MARK: - VPN activated metric

    func testFireVPNActivatedMetricFiresWhenSubscriptionActiveAndEnrolled() {
        seedActiveExperiment(cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingSep2026_treatment")
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
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingSep2026_control")
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

    /// Seeds a device already enrolled in `subscriptionOnboardingSep2026`, enrolled today (inside the
    /// experiment's 0-3 day conversion window).
    private func seedActiveExperiment(cohort: String) {
        let experimentData = ExperimentData(
            parentID: PrivacyProSubfeature.subscriptionOnboardingSep2026.parent.rawValue,
            cohortID: cohort,
            enrollmentDate: Date()
        )
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(
            allActiveExperiments: [PrivacyProSubfeature.subscriptionOnboardingSep2026.rawValue: experimentData]
        )
        configurePixelKit(featureFlagger: featureFlagger)
    }
}
