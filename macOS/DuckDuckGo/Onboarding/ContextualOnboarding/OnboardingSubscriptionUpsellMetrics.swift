//
//  OnboardingSubscriptionUpsellMetrics.swift
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
import PixelExperimentKit
import PixelKit
import PrivacyConfig

/// Custom metrics for the onboarding subscription upsell experiment. The names and the `"1"` value
/// must match the Windows experiment so the two can be pooled — note that differs from the `"true"`
/// used by other macOS experiments.
enum OnboardingSubscriptionUpsellMetric: String {
    case upsellShown
    case tryForFreeClick
    case noThanksClick
    case upsellDismissed
    case trialStarted
}

protocol OnboardingSubscriptionUpsellMetricsReporting {
    func report(_ metric: OnboardingSubscriptionUpsellMetric)
}

struct OnboardingSubscriptionUpsellMetricsReporter: OnboardingSubscriptionUpsellMetricsReporting {

    private enum ConversionWindows {
        static let sameDay: ConversionWindow = 0...0
        static let firstWeek: ConversionWindow = 0...7
    }

    private static let subfeatureID = PrivacyProSubfeature.onboardingSubscriptionUpsellExperiment.rawValue
    private static let value = "1"

    /// No-ops for users with no active experiment — `fireExperimentPixel` checks that itself.
    func report(_ metric: OnboardingSubscriptionUpsellMetric) {
        for window in Self.conversionWindows(for: metric) {
            PixelKit.fireExperimentPixel(
                for: Self.subfeatureID,
                metric: metric.rawValue,
                conversionWindowDays: window,
                value: Self.value
            )
        }
    }

    private static func conversionWindows(for metric: OnboardingSubscriptionUpsellMetric) -> [ConversionWindow] {
        switch metric {
        case .trialStarted:
            // A subscription can complete after onboarding day, so it is measured over the first week too.
            [ConversionWindows.sameDay, ConversionWindows.firstWeek]
        case .upsellShown, .tryForFreeClick, .noThanksClick, .upsellDismissed:
            [ConversionWindows.sameDay]
        }
    }
}
