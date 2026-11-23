//
//  OnboardingVPNDownloadReasonExperimentMetrics.swift
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
import PixelKit
import PixelExperimentKit
import PrivacyConfig

/// Experiment metrics for the onboarding VPN download-reason experiment, on top of the standard app use, search and
/// Duck.ai prompt metrics that every experiment gets. Metrics fired from onboarding screens live in
/// `OnboardingDownloadReasonExperimentMetric`.
///
/// Each metric goes out as `experiment_metrics_onboardingVPNDownloadReasonExperiment_<cohort>`. PixelKit drops it for
/// devices that aren't enrolled or are outside the metric's conversion window, so callers check neither.
/// Every metric name needs a matching entry in `native_experiments.json5`.
public struct OnboardingVPNDownloadReasonExperimentMetrics {

    public typealias FireExperimentPixel = (_ subfeatureID: SubfeatureID,
                                            _ metric: String,
                                            _ conversionWindowDays: ConversionWindow,
                                            _ value: String) -> Void
    public typealias FireExperimentPixelIfThresholdReached = (_ subfeatureID: SubfeatureID,
                                                              _ metric: String,
                                                              _ conversionWindowDays: ConversionWindow,
                                                              _ threshold: NumberOfCalls) -> Void

    enum Metric {
        static let searchOnly = "search_only"
        static let subscribed = "subscribed"
        static let subscriberAppUse = "subscriber_app_use"
        static let subscriberSearch = "subscriber_search"
        static let vpnActivated = "vpn_activated"
        static let vpnUse = "vpn_use"

        static func appUse(reasonToken: String) -> String { "download_reason_app_use_\(reasonToken)" }
        static func search(reasonToken: String) -> String { "download_reason_search_retention_\(reasonToken)" }
        static func searchOnly(reasonToken: String) -> String { "download_reason_search_only_\(reasonToken)" }
        static func aiPrompt(reasonToken: String) -> String { "download_reason_ai_prompt_\(reasonToken)" }
    }

    /// Thresholds (number of actions) mapped to the conversion windows they're reported for.
    typealias ThresholdWindows = [NumberOfCalls: [ConversionWindow]]

    enum Windows {
        /// Per download reason: the standard windows, limited to D0, D1, D5-7 and D8-14 as asked by the onboarding metrics
        /// objective. App use has no D0, like the standard `app_use`.
        static let appUseByReason: ThresholdWindows = [1: [1...1, 5...7, 8...14]]
        /// Also used for searches only, per reason.
        static let searchByReason: ThresholdWindows = [
            1: [0...0, 1...1, 5...7, 8...14],
            4: [5...7, 8...14],
            6: [5...7, 8...14],
            11: [5...7, 8...14],
            21: [5...7, 8...14],
            30: [5...7, 8...14]
        ]
        /// Matches the standard `duck_ai_prompt_sent` metric.
        static let aiPromptByReason: ThresholdWindows = [1: [0...0, 1...1, 5...7, 8...14]]
        /// Matches the standard `search` metric, so the two compare directly.
        static let searchOnly: ThresholdWindows = [
            1: [0...0, 1...1, 2...2, 3...3, 4...4, 5...5, 6...6, 7...7, 5...7, 8...14],
            4: [5...7, 8...14],
            6: [5...7, 8...14],
            11: [5...7, 8...14],
            21: [5...7, 8...14],
            30: [5...7, 8...14]
        ]
        static let subscriberAppUse: ThresholdWindows = [1: [5...7]]
        static let subscriberSearch: ThresholdWindows = [1: [5...7], 4: [5...7], 6: [5...7], 11: [5...7], 21: [5...7], 30: [5...7]]
        /// Purchases in this window make the user a subscriber, fixed before the D5-7 retention window opens.
        static let subscribed: ConversionWindow = 0...4
        static let vpnActivated: ConversionWindow = 0...7
        static let vpnUse: ConversionWindow = 8...14
    }

    static let subfeatureID = PrivacyProSubfeature.onboardingVPNDownloadReasonExperiment.rawValue
    static let isSubscriberKey = "com.duckduckgo.onboardingVPNDownloadReasonExperiment.isSubscriber"

    private let downloadReasonToken: () -> String?
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let fireExperimentPixel: FireExperimentPixel
    private let fireExperimentPixelIfThresholdReached: FireExperimentPixelIfThresholdReached

    public init(downloadReasonToken: @escaping () -> String?,
                userDefaults: UserDefaults,
                calendar: Calendar,
                fireExperimentPixel: @escaping FireExperimentPixel,
                fireExperimentPixelIfThresholdReached: @escaping FireExperimentPixelIfThresholdReached) {
        self.downloadReasonToken = downloadReasonToken
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.fireExperimentPixel = fireExperimentPixel
        self.fireExperimentPixelIfThresholdReached = fireExperimentPixelIfThresholdReached
    }

    /// Reads the stored download reason and subscriber flag from the app's defaults and fires through PixelKit.
    public static var live: OnboardingVPNDownloadReasonExperimentMetrics {
        OnboardingVPNDownloadReasonExperimentMetrics(
            downloadReasonToken: { OnboardingDownloadReasonStore.currentPixelToken(.app) },
            userDefaults: .app,
            // Follows time zone changes, as PixelKit's conversion windows do.
            calendar: .autoupdatingCurrent,
            fireExperimentPixel: PixelKit.fireExperimentPixel(for:metric:conversionWindowDays:value:),
            fireExperimentPixelIfThresholdReached: PixelKit.fireExperimentPixelIfThresholdReached(for:metric:conversionWindowDays:threshold:)
        )
    }

    // MARK: - Retention, next to the standard experiment metrics

    /// Call wherever the standard `app_use` metric fires.
    public func fireAppUseMetrics() {
        if let reasonToken = downloadReasonToken() {
            fire(Metric.appUse(reasonToken: reasonToken), Windows.appUseByReason)
        }
        if isSubscriber {
            fire(Metric.subscriberAppUse, Windows.subscriberAppUse)
        }
    }

    /// Call wherever the standard `search` metric fires, which counts searches and Duck.ai prompts together.
    public func fireSearchMetrics() {
        if let reasonToken = downloadReasonToken() {
            fire(Metric.search(reasonToken: reasonToken), Windows.searchByReason)
        }
        if isSubscriber {
            fire(Metric.subscriberSearch, Windows.subscriberSearch)
        }
    }

    /// Call for searches only, not for Duck.ai prompts.
    public func fireSearchOnlyMetrics() {
        fire(Metric.searchOnly, Windows.searchOnly)
        if let reasonToken = downloadReasonToken() {
            fire(Metric.searchOnly(reasonToken: reasonToken), Windows.searchByReason)
        }
    }

    /// Call wherever the standard Duck.ai prompt metric fires.
    public func fireAIPromptMetrics() {
        guard let reasonToken = downloadReasonToken() else { return }
        fire(Metric.aiPrompt(reasonToken: reasonToken), Windows.aiPromptByReason)
    }

    // MARK: - Events

    /// Call on every new subscription purchase, from any entry point. Restores and tier changes aren't new purchases.
    /// - Parameters:
    ///   - enrollmentDate: The device's enrollment date in the experiment, or `nil` if it isn't enrolled.
    ///   - now: The purchase date.
    public func recordSubscriptionPurchase(enrollmentDate: Date?, now: Date) {
        fireExperimentPixel(Self.subfeatureID, Metric.subscribed, Windows.subscribed, "1")
        guard let enrollmentDate, isWithinSubscribedWindow(enrollmentDate: enrollmentDate, now: now) else { return }
        userDefaults.set(true, forKey: Self.isSubscriberKey)
    }

    /// Call on the device's first VPN configuration install, from any entry point.
    public func fireVPNActivated() {
        fireExperimentPixel(Self.subfeatureID, Metric.vpnActivated, Windows.vpnActivated, "1")
    }

    /// Call when the app comes to the foreground with the VPN connected. The VPN extension can't send experiment
    /// metrics, so this is the closest the app gets to VPN use.
    public func fireVPNUse() {
        fireExperimentPixel(Self.subfeatureID, Metric.vpnUse, Windows.vpnUse, "1")
    }

    // MARK: - Private

    private var isSubscriber: Bool {
        userDefaults.bool(forKey: Self.isSubscriberKey)
    }

    private func isWithinSubscribedWindow(enrollmentDate: Date, now: Date) -> Bool {
        guard let windowEnd = calendar.date(byAdding: .day, value: Windows.subscribed.upperBound, to: enrollmentDate) else { return false }
        let today = calendar.startOfDay(for: now)
        return today >= calendar.startOfDay(for: enrollmentDate) && today <= calendar.startOfDay(for: windowEnd)
    }

    private func fire(_ metric: String, _ thresholdWindows: ThresholdWindows) {
        for (threshold, windows) in thresholdWindows {
            for window in windows {
                fireExperimentPixelIfThresholdReached(Self.subfeatureID, metric, window, threshold)
            }
        }
    }
}
