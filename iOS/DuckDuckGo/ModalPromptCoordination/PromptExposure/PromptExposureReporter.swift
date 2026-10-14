//
//  PromptExposureReporter.swift
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
import Persistence
import PixelKit

@MainActor
protocol PromptExposureReporting: AnyObject {
    func reportPromptShown(_ id: PromptExposureID)
    func reportRemoteMessageCardShown(messageID: String)
    func recordCoordinatedPromptFinished(_ type: PromptExposurePromptType)
    func appDidEnterForeground()
    func reset()
}

private enum PromptExposureStorageKeys: String, StorageKeyDescribing {
    case state = "prompt-exposure-state"
}

struct PromptExposureKeys: StoringKeys {
    let state = StorageKey<PromptExposureState>(PromptExposureStorageKeys.state)
}

// Keep counts and deduplication in one write so a storage failure cannot split an exposure.
struct PromptExposureState: Codable, Equatable {
    var weekIndex: Int?
    var nthInWeek = 0
    var reportedRemoteMessageIDs: Set<String> = []
    var userWeekReportedIndex: Int?
    var lastCoordinatedPromptFinishedAt: Date?
    var sessionPromptShown = false
    var lastProcessedBackgroundDate: Date?

    mutating func rollIfNeeded(_ currentWeekIndex: Int) {
        if let weekIndex, currentWeekIndex <= weekIndex { return }
        weekIndex = currentWeekIndex
        nthInWeek = 0
        reportedRemoteMessageIDs.removeAll()
    }
}

@MainActor
final class PromptExposureReporter: PromptExposureReporting {
    private let storage: any ThrowingKeyedStoring<PromptExposureKeys>
    private let pixel: PixelFiring?
    private let dateProvider: () -> Date
    private let installDateProvider: () -> Date?
    private let onboardingCompletedProvider: () -> Bool
    private let lastBackgroundDateProvider: () -> Date?
    private let randomSource: () -> Double

    init(storage: any ThrowingKeyedStoring<PromptExposureKeys>,
         pixel: PixelFiring? = PixelKit.shared,
         dateProvider: @escaping () -> Date = Date.init,
         installDateProvider: @escaping () -> Date?,
         onboardingCompletedProvider: @escaping () -> Bool,
         lastBackgroundDateProvider: @escaping () -> Date?,
         randomSource: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.storage = storage
        self.pixel = pixel
        self.dateProvider = dateProvider
        self.installDateProvider = installDateProvider
        self.onboardingCompletedProvider = onboardingCompletedProvider
        self.lastBackgroundDateProvider = lastBackgroundDateProvider
        self.randomSource = randomSource
    }

    func reportPromptShown(_ id: PromptExposureID) {
        update { state, days, _, _ in
            self.exposure(id, state: &state, days: days)
        }
    }

    func reportRemoteMessageCardShown(messageID: String) {
        update { state, days, _, _ in
            guard state.reportedRemoteMessageIDs.insert(messageID).inserted else { return [] }
            return self.exposure(.remoteMessageCard, state: &state, days: days)
        }
    }

    func recordCoordinatedPromptFinished(_ type: PromptExposurePromptType) {
        update { state, days, _, now in
            let elapsed = state.lastCoordinatedPromptFinishedAt.map { now.timeIntervalSince($0) }
            state.lastCoordinatedPromptFinishedAt = now
            guard let bucket = PromptExposureBuckets.gap(elapsed) else { return [] }
            return [.gap(daysSinceInstall: PromptExposureBuckets.daysSinceInstall(days), gapBucket: bucket, promptType: type)]
        }
    }

    func appDidEnterForeground() {
        update { state, days, installDate, now in
            var events: [PromptExposurePixel] = []
            if let backgroundDate = self.lastBackgroundDateProvider(), backgroundDate != state.lastProcessedBackgroundDate {
                // Consume short returns too: a repeated foreground must not turn time spent active into time away.
                state.lastProcessedBackgroundDate = backgroundDate
                if now.timeIntervalSince(backgroundDate) >= 60 {
                    let promptShown = state.sessionPromptShown
                    state.sessionPromptShown = false
                    if self.randomSource() < 0.05, self.onboardingCompletedProvider() {
                        let backgroundDays = Self.daysSinceInstall(installDate, at: backgroundDate)
                        events.append(.session(daysSinceInstall: PromptExposureBuckets.daysSinceInstall(backgroundDays), promptShown: promptShown))
                    }
                }
            }
            if self.onboardingCompletedProvider(), state.userWeekReportedIndex != state.weekIndex {
                state.userWeekReportedIndex = state.weekIndex
                events.append(.userWeek(daysSinceInstall: PromptExposureBuckets.daysSinceInstall(days)))
            }
            return events
        }
    }

    func reset() {
        do {
            try storage.removeValue(for: \.state)
        } catch {
            Logger.modalPrompt.error("Failed to reset prompt exposure state.")
        }
    }

    private func exposure(_ id: PromptExposureID, state: inout PromptExposureState, days: Int) -> [PromptExposurePixel] {
        state.sessionPromptShown = true
        state.nthInWeek += 1
        let dayBucket = PromptExposureBuckets.daysSinceInstall(days)
        return [
            .exposure(daysSinceInstall: dayBucket, nthInWeek: PromptExposureBuckets.nthInWeek(state.nthInWeek)),
            .shown(daysSinceInstall: dayBucket, promptID: id)
        ]
    }

    private func update(_ change: (inout PromptExposureState, Int, Date, Date) -> [PromptExposurePixel]) {
        guard let installDate = installDateProvider() else { return }
        let now = dateProvider()
        let days = Self.daysSinceInstall(installDate, at: now)
        do {
            let previousState = try storage.value(for: \.state)
            var state = previousState ?? PromptExposureState()
            state.rollIfNeeded(days / 7)
            let events = change(&state, days, installDate, now)
            if state != previousState {
                try storage.set(state, for: \.state)
            }
            for event in events {
                pixel?.fire(event, frequency: .standard)
            }
        } catch {
            Logger.modalPrompt.error("Failed to update prompt exposure state.")
        }
    }

    private static func daysSinceInstall(_ installDate: Date, at date: Date) -> Int {
        Int(floor(date.timeIntervalSince(installDate) / 86_400))
    }
}
