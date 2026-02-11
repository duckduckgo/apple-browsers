//
//  TabSwitcherTrackerCountViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import BrowserServicesKit
import Core
import PrivacyConfig

@MainActor
final class TabSwitcherTrackerCountViewModel: ObservableObject {

    struct State: Equatable {
        let isVisible: Bool
        let title: String
        let subtitle: String

        static let hidden = State(isVisible: false, title: "", subtitle: "")
    }

    @Published private(set) var state: State

    private var settings: TabSwitcherSettings
    private let privacyStats: PrivacyStatsProviding
    private let featureFlagger: FeatureFlagger
    private var refreshTask: Task<Void, Never>?
    private var countAnimationTask: Task<Void, Never>?

    init(settings: TabSwitcherSettings, privacyStats: PrivacyStatsProviding, featureFlagger: FeatureFlagger, initialState: State) {
        self.state = initialState
        self.settings = settings
        self.privacyStats = privacyStats
        self.featureFlagger = featureFlagger
    }

    /// Returns whether the tracker count feature should be visible based on feature flag and settings.
    /// This is synchronous and can be used to provide initial state before async data is fetched.
    private var shouldShowTrackerCount: Bool {
        return featureFlagger.isFeatureOn(.tabSwitcherTrackerCount) &&
               settings.showTrackerCountInTabSwitcher
    }

    /// Calculates the initial state synchronously based on feature flags and settings.
    /// This should be called before presenting the tab switcher to ensure correct header sizing during transitions.
    static func calculateInitialState(featureFlagger: FeatureFlagger, settings: TabSwitcherSettings, privacyStats: PrivacyStatsProviding) async -> State {
        guard featureFlagger.isFeatureOn(.tabSwitcherTrackerCount),
              settings.showTrackerCountInTabSwitcher else {
            return .hidden
        }

        let count = await privacyStats.fetchPrivacyStatsTotalCount()
        guard count > 0 else {
            return .hidden
        }

        return State(
            isVisible: true,
            title: UserText.tabSwitcherTrackerCountTitle(count),
            subtitle: UserText.tabSwitcherTrackerCountSubtitle
        )
    }

    private func fetchAndUpdateState(shouldAnimate: Bool) async {
        let count = await privacyStats.fetchPrivacyStatsTotalCount()
        guard !Task.isCancelled else { return }

        guard count > 0 else {
            cancelCountAnimation()
            settings.lastTrackerCountInTabSwitcher = nil
            state = .hidden
            return
        }

        // Failure modes:
        // - Repeated fetches can happen while opening/returning to tab switcher.
        // - If count is unchanged, replaying the animation creates noisy UI updates.
        // - Count can still change between refreshes, which should keep animation enabled.
        let shouldAnimateForCount = shouldAnimate
            && settings.lastTrackerCountInTabSwitcher != count

        updateState(for: count, shouldAnimate: shouldAnimateForCount)
        settings.lastTrackerCountInTabSwitcher = count
    }

    func refresh() {
        guard shouldShowTrackerCount else {
            refreshTask?.cancel()
            refreshTask = nil
            cancelCountAnimation()
            state = .hidden
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.fetchAndUpdateState(shouldAnimate: true)
        }
    }

    @discardableResult
    func refreshAsync() async -> State {
        guard shouldShowTrackerCount else {
            refreshTask?.cancel()
            refreshTask = nil
            cancelCountAnimation()
            state = .hidden
            return state
        }

        refreshTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.fetchAndUpdateState(shouldAnimate: false)
        }
        refreshTask = task
        _ = await task.value
        return state
    }

    func hide() {
        refreshTask?.cancel()
        refreshTask = nil
        cancelCountAnimation()
        settings.showTrackerCountInTabSwitcher = false
        state = .hidden
    }

    private func updateState(for count: Int64, shouldAnimate: Bool) {
        cancelCountAnimation()

        let subtitle = UserText.tabSwitcherTrackerCountSubtitle
        let titleForCount: (Int64) -> String = { UserText.tabSwitcherTrackerCountTitle($0) }

        guard shouldAnimate,
              count >= CountAnimationParameters.minimumCountForAnimation else {
            state = State(isVisible: true, title: titleForCount(count), subtitle: subtitle)
            return
        }

        let startingCount = max(1, Int64(ceil(Double(count) * CountAnimationParameters.startPercent)))
        state = State(isVisible: true, title: titleForCount(startingCount), subtitle: subtitle)

        let totalDuration = CountAnimationParameters.totalDuration
        let animationRange = Int(ceil(Double(count) * (1.0 - CountAnimationParameters.startPercent)))
        let steps = max(
            CountAnimationParameters.steps,
            min(animationRange * CountAnimationParameters.rangeMultiplier, CountAnimationParameters.stepsPerNumber)
        )
        let stepDuration = totalDuration / Double(steps)

        countAnimationTask = Task { [weak self] in
            guard let self else { return }

            for i in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let progress = Double(i) / Double(steps)
                let easedProgress = self.easeOut(progress)
                let countProgress = CountAnimationParameters.startPercent
                    + (easedProgress * (1.0 - CountAnimationParameters.startPercent))
                let exactCount = Double(count) * countProgress
                let currentCount = min(Int64(floor(exactCount)), count)

                self.state = State(isVisible: true, title: titleForCount(currentCount), subtitle: subtitle)
            }
        }
    }

    private func cancelCountAnimation() {
        countAnimationTask?.cancel()
        countAnimationTask = nil
    }

    private func easeOut(_ t: Double) -> Double {
        return 1 - pow(1 - t, CountAnimationParameters.easeOutCurve)
    }
}

private enum CountAnimationParameters {
    static let minimumCountForAnimation: Int64 = 5
    static let startPercent: Double = 0.75
    static let stepsPerNumber: Int = 30
    static let steps: Int = 10
    static let rangeMultiplier: Int = 3
    static let easeOutCurve: Double = 4
    static let totalDuration: TimeInterval = 1.0
}
