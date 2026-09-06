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

    func test_resolveCohort_eligibleForFreeTrialsAndNotYetEnrolled_enrollsAndReturnsControl() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.control, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(cohort, .control)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_eligibleForFreeTrialsAndNotYetEnrolled_enrollsAndReturnsTreatment() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(cohort, .treatment)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_eligibleForPaidSubsAndNotYetEnrolled_enrollsAndReturnsTreatment() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingPaidSubsSep2026Cohort.treatment, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.enUS)

        XCTAssertEqual(cohort, .treatment)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_notEnrolled_returnsNil() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertNil(cohort)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_localeIsNotEnUS_doesNotEnroll() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment, isAlreadyAssigned: false)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.nonEnUS)

        XCTAssertNil(cohort)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    /// An existing assignment always wins over current trial status — no re-enrollment on conversion.
    func test_resolveCohort_trialStatusChangedAfterEnrollment_returnsExistingCohort() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment)

        let cohort = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.nonEnUS)

        XCTAssertEqual(cohort, .treatment)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    // MARK: - Enrolled-in-treatment read

    func test_isEnrolledInTreatment_assignedTreatmentCohort_returnsTrue() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment)

        XCTAssertTrue(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func test_isEnrolledInTreatment_assignedControlCohort_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.control)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
    }

    func test_isEnrolledInTreatment_notEnrolled_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
    }

    // MARK: - Settings re-entry

    func test_isSettingsReEntryEnabled_allConditionsHold_returnsTrue() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment)

        XCTAssertTrue(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: true))
    }

    func test_isSettingsReEntryEnabled_flowNeverStarted_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: false, hasActiveSubscription: true))
    }

    func test_isSettingsReEntryEnabled_noLongerInTreatment_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.control)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: true))
    }

    func test_isSettingsReEntryEnabled_subscriptionNoLongerActive_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: false))
    }

    // MARK: - VPN activated metric

    func test_fireVPNActivatedMetric_subscriptionActiveAndEnrolled_fires() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsSep2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsSep2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "vpnActivated")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-7")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    /// Proves the window is per-experiment: paid-subs uses 0-30, not free-trials' 0-7.
    func test_fireVPNActivatedMetric_enrolledInPaidSubsExperiment_firesWithThirtyDayWindow() {
        seedActiveExperiment(.subscriptionOnboardingPaidSubsSep2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingPaidSubsSep2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-30")
    }

    func test_fireVPNActivatedMetric_subscriptionInactive_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsSep2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_fireVPNActivatedMetric_notEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.fireVPNActivatedMetric(isSubscriptionActive: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Duck.ai paid used metric

    func test_fireDuckAIPaidUsedMetric_subscriptionActiveAndEnrolled_fires() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsSep2026, cohort: "control")

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsSep2026_control")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "duckAiPaidUsed")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-7")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    func test_fireDuckAIPaidUsedMetric_subscriptionInactive_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsSep2026, cohort: "control")

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetric(isSubscriptionActive: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_fireDuckAIPaidUsedMetric_notEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetric(isSubscriptionActive: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - PIR activated metric

    func test_firePIRActivatedMetric_enrolledInFreeTrialsExperiment_firesWithSevenDayWindow() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsSep2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.firePIRActivatedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsSep2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "pirActivated")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-7")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    func test_firePIRActivatedMetric_enrolledInPaidSubsExperiment_firesWithThirtyDayWindow() {
        seedActiveExperiment(.subscriptionOnboardingPaidSubsSep2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.firePIRActivatedMetric(isSubscriptionActive: true)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingPaidSubsSep2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "pirActivated")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-30")
    }

    func test_firePIRActivatedMetric_subscriptionInactive_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsSep2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.firePIRActivatedMetric(isSubscriptionActive: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_firePIRActivatedMetric_notEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.firePIRActivatedMetric(isSubscriptionActive: true)

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

    /// Seeds a device enrolled in `subfeature` only — the other subfeature ID is left unseeded, so a fire
    /// attempted against it no-ops.
    private func seedActiveExperiment(_ subfeature: PrivacyProSubfeature, cohort: String) {
        let experimentData = ExperimentData(
            parentID: subfeature.parent.rawValue,
            cohortID: cohort,
            enrollmentDate: Date()
        )
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(
            allActiveExperiments: [subfeature.rawValue: experimentData]
        )
        configurePixelKit(featureFlagger: featureFlagger)
    }
}
