//
//  SubscriptionOnboardingExperiment.swift
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

import Foundation
import FoundationExtensions
import PrivacyConfig
import PixelKit
import PixelExperimentKit
import FeatureFlags_iOS

/// Two mutually exclusive ABN tests split by trial status: free-trials vs. paid-subs. Click-through per step
/// is reported separately via `SubscriptionOnboardingInstrumentation`, not here.
enum SubscriptionOnboardingExperiment {

    /// Unifies the two ABN tests' cohort types — callers only need "is this in treatment", not which test.
    enum Cohort: String, Equatable {
        case control
        case treatment
    }

    private static let freeTrialsFlag = FeatureFlag.subscriptionOnboardingFreeTrialsSep2026
    private static let paidSubsFlag = FeatureFlag.subscriptionOnboardingPaidSubsSep2026
    private static let flags: [FeatureFlag] = [freeTrialsFlag, paidSubsFlag]

    /// Per-experiment, not per-metric: every activation metric uses the same window within an experiment.
    private static let activationMetricTargets: [(subfeatureID: SubfeatureID, conversionWindowDays: ConversionWindow)] = [
        (PrivacyProSubfeature.subscriptionOnboardingFreeTrialsSep2026.rawValue, 0...7),
        (PrivacyProSubfeature.subscriptionOnboardingPaidSubsSep2026.rawValue, 0...30)
    ]

    private enum Metric {
        static let vpnActivated = "vpnActivated"
        static let duckAiPaidUsed = "duckAiPaidUsed"
        static let pirActivated = "pirActivated"
    }

    /// Enrolls in whichever ABN test matches trial status, unless already assigned to either — an existing
    /// assignment always wins, so a trial-to-paid conversion can't cause double-enrollment.
    /// - Returns: The device's cohort, or `nil` if neither experiment is active for this device.
    @discardableResult
    static func resolveCohort(using featureFlagger: FeatureFlagger, isOnFreeTrial: Bool, locale: Locale) -> Cohort? {
        if let assigned = assignedCohort(using: featureFlagger) {
            return assigned
        }
        guard locale.isEnglishUnitedStates else { return nil }
        let flag = isOnFreeTrial ? freeTrialsFlag : paidSubsFlag
        return featureFlagger.resolveCohort(for: flag).flatMap { Cohort(rawValue: $0.rawValue) }
    }

    /// Reads whichever experiment this device is already enrolled in, without enrolling it in either.
    private static func assignedCohort(using featureFlagger: FeatureFlagger) -> Cohort? {
        for flag in flags {
            if let cohort = featureFlagger.assignedCohort(for: flag), let mapped = Cohort(rawValue: cohort.rawValue) {
                return mapped
            }
        }
        return nil
    }

    /// A read-only check for an already-enrolled device. Still subject to each experiment's remote kill switch.
    static func isEnrolledInTreatment(using featureFlagger: FeatureFlagger) -> Bool {
        assignedCohort(using: featureFlagger) == .treatment
    }

    /// Whether the Settings re-entry point should show: the flow was already opened from post-checkout,
    /// the device is still enrolled in treatment, and the subscription still qualifies.
    static func isSettingsReEntryEnabled(using featureFlagger: FeatureFlagger, hasStartedFlow: Bool, hasActiveSubscription: Bool) -> Bool {
        hasStartedFlow && isEnrolledInTreatment(using: featureFlagger) && hasActiveSubscription
    }

    /// Reports VPN activation while the subscription is active. No-ops if not enrolled in either experiment.
    static func fireVPNActivatedMetric(isSubscriptionActive: Bool) {
        guard isSubscriptionActive else { return }
        fireActivationMetric(Metric.vpnActivated)
    }

    /// Reports a paid Duck.ai chat while the subscription is active. No-ops if not enrolled in either experiment.
    static func fireDuckAIPaidUsedMetric(isSubscriptionActive: Bool) {
        guard isSubscriptionActive else { return }
        fireActivationMetric(Metric.duckAiPaidUsed)
    }

    /// Reports PIR activation while the subscription is active. No-ops if not enrolled in either experiment.
    static func firePIRActivatedMetric(isSubscriptionActive: Bool) {
        guard isSubscriptionActive else { return }
        fireActivationMetric(Metric.pirActivated)
    }

    /// Fires `metric` against every experiment's subfeature ID, each with its own window; `fireExperimentPixel`
    /// no-ops for whichever one the device isn't enrolled in, so only one call ever actually records.
    private static func fireActivationMetric(_ metric: String) {
        for target in activationMetricTargets {
            PixelKit.fireExperimentPixel(for: target.subfeatureID, metric: metric, conversionWindowDays: target.conversionWindowDays, value: "1")
        }
    }
}
