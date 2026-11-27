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
import Combine
import PrivacyConfig
import PixelKit
import PixelExperimentKit
import FeatureFlags_iOS
@_spi(Testing) import Persistence
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
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.control, isAlreadyAssigned: false)

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(result.cohort, .control)
        XCTAssertTrue(result.isFreshlyEnrolled)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_eligibleForFreeTrialsAndNotYetEnrolled_enrollsAndReturnsTreatment() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment, isAlreadyAssigned: false)

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(result.cohort, .treatment)
        XCTAssertTrue(result.isFreshlyEnrolled)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_eligibleForPaidSubsAndNotYetEnrolled_enrollsAndReturnsTreatment() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingPaidSubsNov2026Cohort.treatment, isAlreadyAssigned: false)

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.enUS)

        XCTAssertEqual(result.cohort, .treatment)
        XCTAssertTrue(result.isFreshlyEnrolled)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_notEnrolled_returnsNil() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil, isAlreadyAssigned: false)

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertNil(result.cohort)
        XCTAssertFalse(result.isFreshlyEnrolled)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_localeIsNotEnUS_doesNotEnroll() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment, isAlreadyAssigned: false)

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.nonEnUS)

        XCTAssertNil(result.cohort)
        XCTAssertFalse(result.isFreshlyEnrolled)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    /// An existing assignment always wins over current trial status — no re-enrollment on conversion. Also
    /// the "already enrolled" case: a read of an existing assignment is never a fresh enrollment.
    func test_resolveCohort_trialStatusChangedAfterEnrollment_returnsExistingCohort() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment)

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.nonEnUS)

        XCTAssertEqual(result.cohort, .treatment)
        XCTAssertFalse(result.isFreshlyEnrolled)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_inOnboardingVPNExperimentControl_doesNotEnroll() {
        let featureFlagger = PerFlagCohortFeatureFlagger(
            assignedCohorts: [FeatureFlag.onboardingVPNDownloadReasonExperiment.rawValue: FeatureFlag.OnboardingVPNDownloadReasonExperimentCohort.control],
            resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsOct2026Cohort.treatment
        )

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertNil(result.cohort)
        XCTAssertFalse(result.isFreshlyEnrolled)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_inOnboardingVPNExperimentTreatment_doesNotEnroll() {
        let featureFlagger = PerFlagCohortFeatureFlagger(
            assignedCohorts: [FeatureFlag.onboardingVPNDownloadReasonExperiment.rawValue: FeatureFlag.OnboardingVPNDownloadReasonExperimentCohort.treatment],
            resolveCohortStub: FeatureFlag.SubscriptionOnboardingPaidSubsOct2026Cohort.treatment
        )

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.enUS)

        XCTAssertNil(result.cohort)
        XCTAssertFalse(result.isFreshlyEnrolled)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_notInOnboardingVPNExperiment_enrolls() {
        let featureFlagger = PerFlagCohortFeatureFlagger(
            assignedCohorts: [:],
            resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsOct2026Cohort.treatment
        )

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(result.cohort, .treatment)
        XCTAssertTrue(result.isFreshlyEnrolled)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    /// The exclusion only blocks fresh enrollment. A device that was already enrolled here keeps its cohort.
    func test_resolveCohort_alreadyEnrolledAndInOnboardingVPNExperiment_returnsExistingCohort() {
        let featureFlagger = PerFlagCohortFeatureFlagger(
            assignedCohorts: [
                FeatureFlag.subscriptionOnboardingFreeTrialsOct2026.rawValue: FeatureFlag.SubscriptionOnboardingFreeTrialsOct2026Cohort.control,
                FeatureFlag.onboardingVPNDownloadReasonExperiment.rawValue: FeatureFlag.OnboardingVPNDownloadReasonExperimentCohort.treatment
            ],
            resolveCohortStub: nil
        )

        let result = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(result.cohort, .control)
        XCTAssertFalse(result.isFreshlyEnrolled)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func test_resolveCohort_freeTrialAndNotYetEnrolled_enrollsInNov2026FreeTrialsOnly() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.control, isAlreadyAssigned: false)

        _ = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: true, locale: Self.enUS)

        XCTAssertEqual(featureFlagger.resolveCohortFlagRawValues, [FeatureFlag.subscriptionOnboardingFreeTrialsNov2026.rawValue])
    }

    func test_resolveCohort_paidAndNotYetEnrolled_enrollsInNov2026PaidSubsOnly() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingPaidSubsNov2026Cohort.control, isAlreadyAssigned: false)

        _ = SubscriptionOnboardingExperiment.resolveCohort(using: featureFlagger, isOnFreeTrial: false, locale: Self.enUS)

        XCTAssertEqual(featureFlagger.resolveCohortFlagRawValues, [FeatureFlag.subscriptionOnboardingPaidSubsNov2026.rawValue])
    }

    // MARK: - AI features disabled metric

    /// Must fire for control too — the metric compares both cohorts, so a control-only reader would be useless.
    func test_fireAIFeatureDisabledMetricIfNeeded_freshEnrollmentFreeTrialsAsControlWithAIChatDisabled_fires() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "control")

        SubscriptionOnboardingExperiment.fireAIFeatureDisabledMetricIfNeeded(isFreshlyEnrolled: true, isAIChatEnabled: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsNov2026_control")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "ai_features_disabled")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-1")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    func test_fireAIFeatureDisabledMetricIfNeeded_freshEnrollmentPaidSubsAsTreatmentWithAIChatDisabled_fires() {
        seedActiveExperiment(.subscriptionOnboardingPaidSubsNov2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireAIFeatureDisabledMetricIfNeeded(isFreshlyEnrolled: true, isAIChatEnabled: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingPaidSubsNov2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "ai_features_disabled")
    }

    func test_fireAIFeatureDisabledMetricIfNeeded_aiChatEnabled_doesNotFire() {
        SubscriptionOnboardingExperiment.fireAIFeatureDisabledMetricIfNeeded(isFreshlyEnrolled: true, isAIChatEnabled: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    /// A read of an already-assigned cohort is not enrollment, so it must never (re-)fire this metric.
    func test_fireAIFeatureDisabledMetricIfNeeded_notFreshlyEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.fireAIFeatureDisabledMetricIfNeeded(isFreshlyEnrolled: false, isAIChatEnabled: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_fireAIFeatureDisabledMetricIfNeeded_notEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.fireAIFeatureDisabledMetricIfNeeded(isFreshlyEnrolled: true, isAIChatEnabled: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Enrolled-in-treatment read

    func test_isEnrolledInTreatment_assignedTreatmentCohort_returnsTrue() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment)

        XCTAssertTrue(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func test_isEnrolledInTreatment_assignedControlCohort_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.control)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
    }

    func test_isEnrolledInTreatment_notEnrolled_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isEnrolledInTreatment(using: featureFlagger))
    }

    // MARK: - Settings re-entry

    func test_isSettingsReEntryEnabled_allConditionsHold_returnsTrue() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment)

        XCTAssertTrue(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: true))
    }

    func test_isSettingsReEntryEnabled_flowNeverStarted_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: false, hasActiveSubscription: true))
    }

    func test_isSettingsReEntryEnabled_noLongerInTreatment_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.control)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: true))
    }

    func test_isSettingsReEntryEnabled_subscriptionNoLongerActive_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment)

        XCTAssertFalse(SubscriptionOnboardingExperiment.isSettingsReEntryEnabled(using: featureFlagger, hasStartedFlow: true, hasActiveSubscription: false))
    }

    // MARK: - VPN activated metric

    func test_fireVPNActivatedMetricIfNeeded_onEnrollmentDay_firesDayOneBucket() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsNov2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "vpnActivated_d1")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-1")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    /// Proves the day-2-7 bucket is free-trials-specific: 3 days post-enrollment falls inside 2-7, outside 0-1.
    func test_fireVPNActivatedMetricIfNeeded_threeDaysAfterFreeTrialsEnrollment_firesDayTwoToSevenBucket() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment", enrollmentDate: daysAgo(3))

        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsNov2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "vpnActivated_d2_7")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "2-7")
    }

    /// Proves the day-2-30 bucket is paid-subs-specific: 10 days post-enrollment falls inside 2-30, outside 2-7.
    func test_fireVPNActivatedMetricIfNeeded_tenDaysAfterPaidSubsEnrollment_firesDayTwoToThirtyBucket() {
        seedActiveExperiment(.subscriptionOnboardingPaidSubsNov2026, cohort: "treatment", enrollmentDate: daysAgo(10))

        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingPaidSubsNov2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "vpnActivated_d2_30")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "2-30")
    }

    func test_fireVPNActivatedMetricIfNeeded_subscriptionInactive_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: false, isAlreadyActivated: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_fireVPNActivatedMetricIfNeeded_notEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_fireVPNActivatedMetricIfNeeded_alreadyActivated_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Duck.ai paid used metric

    func test_fireDuckAIPaidUsedMetricIfNeeded_onEnrollmentDay_firesDayOneBucket() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "control")

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: true, metricStore: MockSubscriptionOnboardingExperimentMetricStore())

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsNov2026_control")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "duckAiPaidUsed_d1")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-1")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    /// Proves the day-2-30 bucket is paid-subs-specific, mirroring the VPN metric's bucket split.
    func test_fireDuckAIPaidUsedMetricIfNeeded_tenDaysAfterPaidSubsEnrollment_firesDayTwoToThirtyBucket() {
        seedActiveExperiment(.subscriptionOnboardingPaidSubsNov2026, cohort: "control", enrollmentDate: daysAgo(10))

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: true, metricStore: MockSubscriptionOnboardingExperimentMetricStore())

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingPaidSubsNov2026_control")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "duckAiPaidUsed_d2_30")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "2-30")
    }

    func test_fireDuckAIPaidUsedMetricIfNeeded_subscriptionInactive_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "control")

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: false, metricStore: MockSubscriptionOnboardingExperimentMetricStore())

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_fireDuckAIPaidUsedMetricIfNeeded_notEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: true, metricStore: MockSubscriptionOnboardingExperimentMetricStore())

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_fireDuckAIPaidUsedMetricIfNeeded_notEnrolled_stillMarksMetricSent() {
        let metricStore = MockSubscriptionOnboardingExperimentMetricStore()

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: true, metricStore: metricStore)

        XCTAssertTrue(metricStore.hasSentDuckAIPaidUsed)
    }

    func test_fireDuckAIPaidUsedMetricIfNeeded_alreadyActivated_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "control")

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: true, metricStore: MockSubscriptionOnboardingExperimentMetricStore(hasSentDuckAIPaidUsed: true))

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - PIR activated metric

    func test_firePIRActivatedMetricIfNeeded_onEnrollmentDay_firesDayOneBucket() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.firePIRActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsNov2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "pirActivated_d1")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "0-1")
        XCTAssertEqual(firedEvents.first?.parameters?["value"], "1")
    }

    func test_firePIRActivatedMetricIfNeeded_threeDaysAfterFreeTrialsEnrollment_firesDayTwoToSevenBucket() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment", enrollmentDate: daysAgo(3))

        SubscriptionOnboardingExperiment.firePIRActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsNov2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "pirActivated_d2_7")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "2-7")
    }

    func test_firePIRActivatedMetricIfNeeded_tenDaysAfterPaidSubsEnrollment_firesDayTwoToThirtyBucket() {
        seedActiveExperiment(.subscriptionOnboardingPaidSubsNov2026, cohort: "treatment", enrollmentDate: daysAgo(10))

        SubscriptionOnboardingExperiment.firePIRActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingPaidSubsNov2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "pirActivated_d2_30")
        XCTAssertEqual(firedEvents.first?.parameters?["conversionWindowDays"], "2-30")
    }

    func test_firePIRActivatedMetricIfNeeded_subscriptionInactive_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.firePIRActivatedMetricIfNeeded(isSubscriptionActive: false, isAlreadyActivated: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_firePIRActivatedMetricIfNeeded_notEnrolled_doesNotFire() {
        SubscriptionOnboardingExperiment.firePIRActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func test_firePIRActivatedMetricIfNeeded_alreadyActivated_doesNotFire() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.firePIRActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Duck.ai metric marked sent only when it fires

    func test_fireDuckAIPaidUsedMetricIfNeeded_subscriptionInactive_doesNotMarkMetricSent() {
        let metricStore = MockSubscriptionOnboardingExperimentMetricStore()

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: false, metricStore: metricStore)

        XCTAssertFalse(metricStore.hasSentDuckAIPaidUsed)
    }

    func test_fireDuckAIPaidUsedMetricIfNeeded_enrolled_marksMetricSentOnce() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsNov2026, cohort: "treatment")
        let metricStore = MockSubscriptionOnboardingExperimentMetricStore()

        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: true, metricStore: metricStore)
        SubscriptionOnboardingExperiment.fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: true, metricStore: metricStore)

        XCTAssertTrue(metricStore.hasSentDuckAIPaidUsed)
        XCTAssertEqual(firedEvents.count, 1)
    }

    // MARK: - Legacy Oct2026 enrollments

    func test_fireVPNActivatedMetricIfNeeded_enrolledInLegacyFreeTrials_firesUnderLegacyExperiment() {
        seedActiveExperiment(.subscriptionOnboardingFreeTrialsOct2026, cohort: "treatment")

        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingFreeTrialsOct2026_treatment")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "vpnActivated_d1")
    }

    func test_fireVPNActivatedMetricIfNeeded_tenDaysAfterLegacyPaidSubsEnrollment_firesDayTwoToThirtyBucket() {
        seedActiveExperiment(.subscriptionOnboardingPaidSubsOct2026, cohort: "control", enrollmentDate: daysAgo(10))

        SubscriptionOnboardingExperiment.fireVPNActivatedMetricIfNeeded(isSubscriptionActive: true, isAlreadyActivated: false)

        XCTAssertEqual(firedEvents.count, 1)
        XCTAssertEqual(firedEvents.first?.name, "experiment_metrics_subscriptionOnboardingPaidSubsOct2026_control")
        XCTAssertEqual(firedEvents.first?.parameters?["metric"], "vpnActivated_d2_30")
    }

    // MARK: - Helpers

    private func configurePixelKit(featureFlagger: FeatureFlagger) {
        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(),
            fire: { [weak self] event, _, _ in self?.firedEvents.append(event) }
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    /// Seeds a device enrolled in `subfeature` only — the other subfeature ID is left unseeded, so a fire
    /// attempted against it no-ops.
    private func seedActiveExperiment(_ subfeature: PrivacyProSubfeature, cohort: String, enrollmentDate: Date = Date()) {
        let experimentData = ExperimentData(
            parentID: subfeature.parent.rawValue,
            cohortID: cohort,
            enrollmentDate: enrollmentDate
        )
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(
            allActiveExperiments: [subfeature.rawValue: experimentData]
        )
        configurePixelKit(featureFlagger: featureFlagger)
    }
}

/// Answers `assignedCohort` per flag. `PrivacyConfig.MockFeatureFlagger` returns the same stub for every flag, so it
/// can't express "enrolled in the onboarding VPN experiment but not in Subscription onboarding".
private final class PerFlagCohortFeatureFlagger: FeatureFlagger {

    let internalUserDecider: InternalUserDecider = PrivacyConfig.MockFeatureFlagger().internalUserDecider
    let localOverrides: FeatureFlagLocalOverriding? = nil
    let allActiveExperiments: Experiments = [:]
    var updatesPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    private let assignedCohorts: [String: any FeatureFlagCohortDescribing]
    private let resolveCohortStub: (any FeatureFlagCohortDescribing)?
    private(set) var didCallResolveCohort = false

    init(assignedCohorts: [String: any FeatureFlagCohortDescribing], resolveCohortStub: (any FeatureFlagCohortDescribing)?) {
        self.assignedCohorts = assignedCohorts
        self.resolveCohortStub = resolveCohortStub
    }

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        false
    }

    func resolveCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? {
        didCallResolveCohort = true
        return assignedCohorts[featureFlag.rawValue] ?? resolveCohortStub
    }

    func assignedCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? {
        assignedCohorts[featureFlag.rawValue]
    }
}

final class SubscriptionOnboardingExperimentMetricStoreTests: XCTestCase {

    private var keyValueStore: InMemoryThrowingKeyValueStore!
    private var sut: SubscriptionOnboardingExperimentMetricStore!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryThrowingKeyValueStore()
        sut = SubscriptionOnboardingExperimentMetricStore(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }

    func testWhenNothingWasMarkedThenDuckAIPaidUsedIsNotSent() {
        XCTAssertFalse(sut.hasSentDuckAIPaidUsed)
    }

    func testWhenMarkingDuckAIPaidUsedSentThenItIsSent() {
        sut.markDuckAIPaidUsedSent()

        XCTAssertTrue(sut.hasSentDuckAIPaidUsed)
    }

    func testWhenResettingAfterMarkingThenDuckAIPaidUsedIsNotSent() {
        sut.markDuckAIPaidUsedSent()

        sut.resetDuckAIPaidUsedSent()

        XCTAssertFalse(sut.hasSentDuckAIPaidUsed)
    }

    func testWhenTheChecklistAlreadyHasDuckAIThenTheDuckAIPaidUsedMetricIsNotMarkedSent() {
        var persistor = SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore)
        persistor.markComplete(.duckAI)

        XCTAssertFalse(sut.hasSentDuckAIPaidUsed)
    }
}
