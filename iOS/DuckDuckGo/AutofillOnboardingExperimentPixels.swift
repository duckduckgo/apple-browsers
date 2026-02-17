//
//  AutofillOnboardingExperimentPixels.swift
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

import BrowserServicesKit
import Foundation
import Persistence
import PixelExperimentKit
import PixelKit
import PrivacyConfig

// MARK: - Storage Keys

enum AutofillOnboardingExperimentStorageKeys: String, StorageKeyDescribing {
    case onboardingImpressionCount = "com-duckduckgo-autofill-onboarding-experiment-impression_count"
}

struct AutofillOnboardingExperimentKeys: StoringKeys {
    let onboardingImpressionCount = StorageKey<Int>(AutofillOnboardingExperimentStorageKeys.onboardingImpressionCount)
}

// MARK: - Instrumentation Facade

/// Instrumentation facade for the autofill onboarding A/B experiment.
///
/// Callers inject this protocol for testability; the default implementation
/// fires experiment pixels via `PixelKit` directly.
protocol AutofillOnboardingExperimentPixelFiring {

    // MARK: - Primary Metrics

    /// Fires once per user when they tap Save on the onboarding prompt.
    func fireSaveTap()

    /// Fires each time the user taps the dismiss button ("No Thanks").
    func fireDismissTap()

    /// Fires at threshold milestones (1, 2, 3, 5) when the user taps "Never ask for this site".
    func fireNeverAskTap()

    // MARK: - Secondary Metrics

    /// Fires when a password is saved, with the current account count bucketed (none, few, some, many, lots).
    /// Deduplication ensures each bucket value fires at most once per conversion window.
    func firePasswordsSaved()

    /// Fires when the user completes the data import flow.
    func fireImportCompleted()

    /// Fires when the main autofill setting is toggled on or off.
    func fireAutofillEnabled(_ enabled: Bool)

    /// Fires when sync is toggled on or off.
    func fireSyncEnabled(_ enabled: Bool)

    /// Fires when Autofill in Other Apps (credential provider extension) is toggled on or off.
    func fireAutofillInOtherAppsEnabled(_ enabled: Bool)

    // MARK: - Diagnostic Metrics

    /// Reports the bucketed number of onboarding prompt impressions at conversion time.
    func fireImpressionCount(_ count: Int)

    /// Reports the bucketed number of days between enrollment and save.
    func fireDaysToConversion(_ days: Int)
}

// MARK: - Impression Tracker

/// Tracks the number of onboarding prompt impressions for the experiment's `impression_count` diagnostic metric.
final class AutofillOnboardingExperimentImpressionTracker {

    private let storage: any KeyedStoring<AutofillOnboardingExperimentKeys>

    init(storage: (any KeyedStoring<AutofillOnboardingExperimentKeys>)? = nil) {
        self.storage = if let storage { storage } else { UserDefaults.standard.keyedStoring() }
    }

    /// The current impression count.
    var impressionCount: Int {
        storage.onboardingImpressionCount ?? 0
    }

    /// Call each time the onboarding save-password prompt is displayed.
    func recordImpression() {
        storage.onboardingImpressionCount = impressionCount + 1
    }
}

// MARK: - Default Implementation

final class AutofillOnboardingExperimentPixelReporter: AutofillOnboardingExperimentPixelFiring {

    private let subfeatureID: SubfeatureID = AutofillSubfeature.onboardingExperiment.rawValue

    // MARK: Metric Names

    private enum Metric {
        static let saveTap = "save_tap"
        static let dismissTap = "dismiss_tap"
        static let neverAskTap = "never_ask_tap"
        static let passwordsSaved = "passwords_saved"
        static let importCompleted = "import_completed"
        static let autofillEnabled = "autofill_enabled"
        static let syncEnabled = "sync_enabled"
        static let autofillOtherAppsEnabled = "autofill_other_apps_enabled"
        static let impressionCount = "impression_count"
        static let daysToConversion = "days_to_conversion"
    }

    // MARK: Conversion Windows

    private enum Window {
        static let sevenDay: ConversionWindow = 0...6
        static let fourteenDay: ConversionWindow = 0...13
        static let twentyEightDay: ConversionWindow = 0...27

        static let primary: [ConversionWindow] = [sevenDay]
        static let secondary: [ConversionWindow] = [sevenDay, fourteenDay, twentyEightDay]
    }

    // MARK: Thresholds

    private let neverAskThresholds: [Int] = [1, 2, 3, 5]

    // MARK: - Primary Metrics

    func fireSaveTap() {
        for window in Window.primary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.saveTap,
                conversionWindowDays: window,
                value: "1")
        }
    }

    func fireDismissTap() {
        for window in Window.primary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.dismissTap,
                conversionWindowDays: window,
                value: "1")
        }
    }

    func fireNeverAskTap() {
        for window in Window.primary {
            for threshold in neverAskThresholds {
                PixelKit.fireExperimentPixelIfThresholdReached(
                    for: subfeatureID,
                    metric: Metric.neverAskTap,
                    conversionWindowDays: window,
                    threshold: threshold)
            }
        }
    }

    // MARK: - Secondary Metrics

    func firePasswordsSaved() {
        guard let vault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter()),
              let count = try? vault.accountsCount() else { return }

        let bucket = AutofillPixelReporter.accountsBucketNameFrom(count: count)
        for window in Window.secondary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.passwordsSaved,
                conversionWindowDays: window,
                value: bucket)
        }
    }

    func fireImportCompleted() {
        for window in Window.secondary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.importCompleted,
                conversionWindowDays: window,
                value: "1")
        }
    }

    func fireAutofillEnabled(_ enabled: Bool) {
        for window in Window.secondary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.autofillEnabled,
                conversionWindowDays: window,
                value: String(enabled))
        }
    }

    func fireSyncEnabled(_ enabled: Bool) {
        for window in Window.secondary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.syncEnabled,
                conversionWindowDays: window,
                value: String(enabled))
        }
    }

    func fireAutofillInOtherAppsEnabled(_ enabled: Bool) {
        for window in Window.secondary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.autofillOtherAppsEnabled,
                conversionWindowDays: window,
                value: String(enabled))
        }
    }

    // MARK: - Diagnostic Metrics

    func fireImpressionCount(_ count: Int) {
        let bucket = impressionCountBucket(for: count)
        for window in Window.primary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.impressionCount,
                conversionWindowDays: window,
                value: bucket)
        }
    }

    func fireDaysToConversion(_ days: Int) {
        let bucket = daysToConversionBucket(for: days)
        for window in Window.primary {
            PixelKit.fireExperimentPixel(
                for: subfeatureID,
                metric: Metric.daysToConversion,
                conversionWindowDays: window,
                value: bucket)
        }
    }

    // MARK: - Bucketing

    /// Buckets impression count: 1, 2-3, 4-6, 7-10, 11+
    private func impressionCountBucket(for count: Int) -> String {
        switch count {
        case 1: return "1"
        case 2...3: return "2-3"
        case 4...6: return "4-6"
        case 7...10: return "7-10"
        default: return "11+"
        }
    }

    /// Buckets days to conversion: 0, 1, 2-3, 4-5, 6-7, 8+
    private func daysToConversionBucket(for days: Int) -> String {
        switch days {
        case 0: return "0"
        case 1: return "1"
        case 2...3: return "2-3"
        case 4...5: return "4-5"
        case 6...7: return "6-7"
        default: return "8+"
        }
    }
}
