//
//  OnboardingNonBlockingExperiment.swift
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

import FeatureFlags_macOS
import Foundation
import PixelKit
import Persistence
import PrivacyConfig

struct OnboardingNonBlockingExperiment {

    private let featureFlagger: FeatureFlagger

    private static let subfeatureID = MacOSBrowserConfigSubfeature.onboardingNonBlocking.rawValue

    enum Metric: String {
        case onboardingCompleted
        /// Onboarding ended without completing: the tab was closed, navigated away from, removed in
        /// bulk, or its window was closed. Quitting is deliberately excluded — it records nothing,
        /// so onboarding shows again on the next launch just as it does today.
        case onboardingSkipped
        case browsingBeforeCompletion
        case contextualDismissed
        case importRequested
        case addToDockRequested
        case setAsDefaultEnabled

        var conversionWindows: [ClosedRange<Int>] {
            switch self {
            case .onboardingCompleted, .onboardingSkipped, .importRequested, .addToDockRequested:
                return [ConversionWindows.oneDay, ConversionWindows.fiveDays, ConversionWindows.sevenDays]
            case .browsingBeforeCompletion, .contextualDismissed:
                return [ConversionWindows.sevenDays]
            case .setAsDefaultEnabled:
                return [ConversionWindows.fiveToSevenDays]
            }
        }
    }

    private enum ConversionWindows {
        static let oneDay = 0...1
        static let fiveDays = 0...5
        static let sevenDays = 0...7
        static let fiveToSevenDays = 5...7
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    /// Assigns a cohort via `resolveCohort`. Caller must only invoke for eligible new installs.
    func enroll(buildType: ApplicationBuildType = StandardApplicationBuildType()) {
        guard !buildType.isDebugBuild, !buildType.isReviewBuild, !buildType.isAlphaBuild else { return }
        _ = featureFlagger.resolveCohort(for: FeatureFlag.onboardingNonBlocking)
    }

    /// Already-assigned cohort, or `nil` when not enrolled. Never assigns.
    var cohort: FeatureFlag.OnboardingNonBlockingCohort? {
        featureFlagger.assignedCohort(for: FeatureFlag.onboardingNonBlocking) as? FeatureFlag.OnboardingNonBlockingCohort
    }

    /// Whether onboarding should run non-blocking: the local debug flag forces it,
    /// and the treatment cohort gets it.
    var isNonBlocking: Bool {
        featureFlagger.isFeatureOn(.onboardingAsync) || cohort == .treatment
    }

    /// First-run onboarding can be resumed without restarting contextual onboarding.
    func initializeContextualOnboarding(_ updater: ContextualOnboardingStateUpdater,
                                       persistor: OnboardingExperimentPersistor = OnboardingExperimentPersistor()) {
        guard isNonBlocking, !persistor.contextualInitialized else { return }
        updater.state = .notStarted
        persistor.contextualInitialized = true
    }

    /// Tags a pixel that isn't one of this experiment's own metrics — the quit survey's, for
    /// instance — so its responses can be broken down by cohort. Empty for anyone who was never
    /// enrolled, which leaves their pixel exactly as it is today, and matches how the other
    /// cohort-tagged pixels here behave.
    var cohortParameters: [String: String] {
        guard let cohort else { return [:] }
        return [Self.cohortParameterKey: cohort.rawValue]
    }

    private static let cohortParameterKey = "onboardingNonBlockingCohort"

    func fireMetric(_ metric: Metric, value: String = "true") {
        guard cohort != nil else { return }
        for window in metric.conversionWindows {
            PixelKit.fireExperimentPixel(
                for: Self.subfeatureID,
                metric: metric.rawValue,
                conversionWindowDays: window,
                value: value
            )
        }
    }
}

/// The experiment's durable lifecycle data. Contextual progress remains in its existing storage.
final class OnboardingExperimentPersistor {
    enum Outcome: String {
        case completed
        case skipped
    }

    static let outcomeDidChange = Notification.Name("onboarding-experiment.outcome-did-change")

    private enum Key: String {
        case outcome = "onboarding-experiment.outcome"
        case contextualInitialized = "onboarding-experiment.contextual-initialized"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = Application.appDelegate.keyValueStore) {
        self.keyValueStore = keyValueStore
    }

    var contextualInitialized: Bool {
        get { (try? keyValueStore.object(forKey: Key.contextualInitialized.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.contextualInitialized.rawValue) }
    }

    var outcome: Outcome? {
        guard let value = try? keyValueStore.object(forKey: Key.outcome.rawValue) as? String else { return nil }
        return Outcome(rawValue: value)
    }

    /// Explicit debug reset starts a new first-run and contextual session.
    func reset() {
        try? keyValueStore.removeObject(forKey: Key.outcome.rawValue)
        try? keyValueStore.removeObject(forKey: Key.contextualInitialized.rawValue)
        NotificationCenter.default.post(name: Self.outcomeDidChange, object: nil)
    }

    @discardableResult
    func record(_ outcome: Outcome) -> Bool {
        guard self.outcome == nil else { return false }
        try? keyValueStore.set(outcome.rawValue, forKey: Key.outcome.rawValue)
        NotificationCenter.default.post(name: Self.outcomeDidChange, object: nil)
        return true
    }
}
