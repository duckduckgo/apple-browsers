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
import AIChat

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

    private static let freeTrialsSubfeatureID = PrivacyProSubfeature.subscriptionOnboardingFreeTrialsSep2026.rawValue
    private static let paidSubsSubfeatureID = PrivacyProSubfeature.subscriptionOnboardingPaidSubsSep2026.rawValue

    private static let d1Window: ConversionWindow = 0...1

    private static let activationMetricTargets: [(subfeatureID: SubfeatureID, suffix: String, window: ConversionWindow)] = [
        (freeTrialsSubfeatureID, "_d2_7", 2...7),
        (paidSubsSubfeatureID, "_d2_30", 2...30)
    ]

    private enum Metric {
        static let vpnActivated = "vpnActivated"
        static let duckAiPaidUsed = "duckAiPaidUsed"
        static let pirActivated = "pirActivated"
        static let aiFeaturesDisabled = "ai_features_disabled"
    }

    /// Enrolls in whichever ABN test matches trial status, unless already assigned to either.
    /// - Returns: The device's cohort (`nil` if neither experiment is active for this device), and whether
    ///   this call is the one that freshly enrolled it (`false` for a read of an existing assignment). 
    static func resolveCohort(using featureFlagger: FeatureFlagger, isOnFreeTrial: Bool, locale: Locale) -> (cohort: Cohort?, isFreshlyEnrolled: Bool) {
        if let assigned = assignedCohort(using: featureFlagger) {
            return (assigned, false)
        }
        guard locale.isEnglishUnitedStates else { return (nil, false) }
        let flag = isOnFreeTrial ? freeTrialsFlag : paidSubsFlag
        let cohort = featureFlagger.resolveCohort(for: flag).flatMap { Cohort(rawValue: $0.rawValue) }
        return (cohort, cohort != nil)
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

    /// Reports VPN activation while the subscription is active, unless already recorded. No-ops if not
    /// enrolled in either experiment.
    static func fireVPNActivatedMetricIfNeeded(isSubscriptionActive: Bool, isAlreadyActivated: Bool) {
        guard isSubscriptionActive, !isAlreadyActivated else { return }
        fireActivationMetric(Metric.vpnActivated)
    }

    /// Reports a paid Duck.ai chat while the subscription is active, unless already recorded. No-ops if not
    /// enrolled in either experiment.
    static func fireDuckAIPaidUsedMetricIfNeeded(isSubscriptionActive: Bool, isAlreadyActivated: Bool) {
        guard isSubscriptionActive, !isAlreadyActivated else { return }
        fireActivationMetric(Metric.duckAiPaidUsed)
    }

    /// Reports PIR activation while the subscription is active, unless already recorded. No-ops if not
    /// enrolled in either experiment.
    static func firePIRActivatedMetricIfNeeded(isSubscriptionActive: Bool, isAlreadyActivated: Bool) {
        guard isSubscriptionActive, !isAlreadyActivated else { return }
        fireActivationMetric(Metric.pirActivated)
    }

    /// Reports whether Duck.ai was disabled in the app, unless this isn't the call that freshly enrolled the
    /// device (see `resolveCohort`). No-ops if not enrolled in either experiment.
    static func fireAIFeatureDisabledMetricIfNeeded(isFreshlyEnrolled: Bool, isAIChatEnabled: @autoclosure () -> Bool = AIChatSettings().isAIChatEnabled) {
        guard isFreshlyEnrolled, !isAIChatEnabled() else { return }
        for target in activationMetricTargets {
            PixelKit.fireExperimentPixel(for: target.subfeatureID, metric: Metric.aiFeaturesDisabled, conversionWindowDays: d1Window, value: "1")
        }
    }

    private static func fireActivationMetric(_ metric: String) {
        for target in activationMetricTargets {
            PixelKit.fireExperimentPixel(for: target.subfeatureID, metric: metric + "_d1", conversionWindowDays: d1Window, value: "1")
            PixelKit.fireExperimentPixel(for: target.subfeatureID, metric: metric + target.suffix, conversionWindowDays: target.window, value: "1")
        }
    }
}
