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

/// The `subscriptionOnboardingSep2026` ABN test (control vs. treatment)
///
/// Click-through rate per step is not this file's concern — it's read from the existing
/// `SubscriptionOnboardingInstrumentation` step-funnel pixels, joined against this experiment's
/// `experiment_enroll_subscriptionOnboardingSep2026_{cohort}` pixel to split by cohort.
enum SubscriptionOnboardingExperiment {
    private static let subfeatureID = PrivacyProSubfeature.subscriptionOnboardingSep2026.rawValue
    private static let conversionWindowDays: ConversionWindow = 0...3

    private enum Metric {
        static let vpnActivated = "vpnActivated"
        static let duckAiPaidUsed = "duckAiPaidUsed"
    }

    /// Enrolls the device in the experiment if it isn't already, assigning and reporting a cohort.
    ///
    /// - Returns: The device's cohort, or `nil` if the experiment isn't active for this device.
    @discardableResult
    static func resolveCohort(using featureFlagger: FeatureFlagger, isOnFreeTrial: Bool, locale: Locale) -> FeatureFlag.SubscriptionOnboardingSep2026Cohort? {
        if let assigned = featureFlagger.assignedCohort(for: FeatureFlag.subscriptionOnboardingSep2026) as? FeatureFlag.SubscriptionOnboardingSep2026Cohort {
            return assigned
        }
        guard isOnFreeTrial, locale.isEnglishUnitedStates else { return nil }
        return featureFlagger.resolveCohort(for: FeatureFlag.subscriptionOnboardingSep2026) as? FeatureFlag.SubscriptionOnboardingSep2026Cohort
    }

    /// A read-only check for an already-enrolled device. Still subject to the
    /// experiment's remote kill switch
    static func isEnrolledInTreatment(using featureFlagger: FeatureFlagger) -> Bool {
        featureFlagger.assignedCohort(for: FeatureFlag.subscriptionOnboardingSep2026) as? FeatureFlag.SubscriptionOnboardingSep2026Cohort == .treatment
    }

    /// Whether the Settings re-entry point should show: the flow was already opened from post-checkout,
    /// the device is still enrolled in treatment, and the subscription still qualifies.
    static func isSettingsReEntryEnabled(using featureFlagger: FeatureFlagger, hasStartedFlow: Bool, hasActiveSubscription: Bool) -> Bool {
        hasStartedFlow && isEnrolledInTreatment(using: featureFlagger) && hasActiveSubscription
    }

    /// Reports that the VPN was activated while the customer had an active subscription, within the
    /// experiment's 0-3 day conversion window. No-ops for a device not enrolled in the experiment.
    static func fireVPNActivatedMetric(isSubscriptionActive: Bool) {
        guard isSubscriptionActive else { return }
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: Metric.vpnActivated, conversionWindowDays: conversionWindowDays, value: "1")
    }

    /// Reports that a paid Duck.ai chat was used while the customer had an active subscription, within
    /// the experiment's 0-3 day conversion window. No-ops for a device not enrolled in the experiment.
    static func fireDuckAIPaidUsedMetric(isSubscriptionActive: Bool) {
        guard isSubscriptionActive else { return }
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: Metric.duckAiPaidUsed, conversionWindowDays: conversionWindowDays, value: "1")
    }
}
