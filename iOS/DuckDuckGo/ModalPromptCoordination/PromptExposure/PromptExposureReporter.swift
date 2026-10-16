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
    /// Time in the background that ends a session, so a quick app switch does not split one visit in two.
    private static let minimumBackgroundDurationToEndSession: TimeInterval = 60
    /// Share of ended sessions reported. Changing it requires bumping `PromptExposurePixel.version`.
    private static let sessionSampleRate = 0.05
    private static let secondsPerDay: TimeInterval = 86_400

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
        update { state, days, _ in
            self.exposure(id, state: &state, days: days)
        }
    }

    func reportRemoteMessageCardShown(messageID: String) {
        update { state, days, _ in
            guard state.reportedRemoteMessageIDs.insert(messageID).inserted else { return [] }
            return self.exposure(.remoteMessageCard, state: &state, days: days)
        }
    }

    func recordCoordinatedPromptFinished(_ type: PromptExposurePromptType) {
        update { state, days, now in
            let elapsed = state.lastCoordinatedPromptFinishedAt.map { now.timeIntervalSince($0) }
            state.lastCoordinatedPromptFinishedAt = now
            guard let bucket = PromptExposureBuckets.gap(elapsed) else { return [] }
            return [.gap(daysSinceInstall: PromptExposureBuckets.daysSinceInstall(days), gapBucket: bucket, promptType: type)]
        }
    }

    func appDidEnterForeground() {
        update(isForeground: true) { state, days, _ in
            guard self.onboardingCompletedProvider(), state.userWeekReportedIndex != state.weekIndex else { return [] }
            state.userWeekReportedIndex = state.weekIndex
            return [.userWeek(daysSinceInstall: PromptExposureBuckets.daysSinceInstall(days))]
        }
    }

    func reset() {
        do {
            // Keep the processed background date, so a later report cannot count time already spent active as time away.
            try storage.set(PromptExposureState(lastProcessedBackgroundDate: lastBackgroundDateProvider()), for: \.state)
        } catch {
            Logger.modalPrompt.error("Failed to reset prompt exposure state: \(error, privacy: .public)")
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

    /// Ends the previous session once the app has been away long enough. Every update runs this first, so a prompt reported
    /// before the foreground callback on launch cannot mark the previous session. The processed date makes it idempotent.
    private func endSessionIfAway(_ state: inout PromptExposureState, installDate: Date, now: Date, isForeground: Bool) -> [PromptExposurePixel] {
        guard let backgroundDate = lastBackgroundDateProvider(), backgroundDate != state.lastProcessedBackgroundDate else { return [] }
        guard now.timeIntervalSince(backgroundDate) >= Self.minimumBackgroundDurationToEndSession else {
            // Only the foreground consumes a short return, so time spent active later is not counted as time away.
            // A report while still in the background must not consume it, or the rest of that absence would be lost.
            if isForeground { state.lastProcessedBackgroundDate = backgroundDate }
            return []
        }
        state.lastProcessedBackgroundDate = backgroundDate
        let promptShown = state.sessionPromptShown
        state.sessionPromptShown = false
        guard randomSource() < Self.sessionSampleRate, onboardingCompletedProvider() else { return [] }
        let backgroundDays = Self.daysSinceInstall(installDate, at: backgroundDate)
        return [.session(daysSinceInstall: PromptExposureBuckets.daysSinceInstall(backgroundDays), promptShown: promptShown)]
    }

    private func update(isForeground: Bool = false, _ change: (inout PromptExposureState, Int, Date) -> [PromptExposurePixel]) {
        guard let installDate = installDateProvider() else { return }
        let now = dateProvider()
        let days = Self.daysSinceInstall(installDate, at: now)
        do {
            let previousState = try storedState()
            var state = previousState ?? PromptExposureState()
            state.rollIfNeeded(days / 7)
            let events = endSessionIfAway(&state, installDate: installDate, now: now, isForeground: isForeground)
                + change(&state, days, now)
            if state != previousState {
                try storage.set(state, for: \.state)
            }
            for event in events {
                pixel?.fire(event, frequency: .standard)
            }
        } catch {
            Logger.modalPrompt.error("Failed to update prompt exposure state: \(error, privacy: .public)")
        }
    }

    /// Synthesized decoding ignores default values, so a schema change or a corrupt record would otherwise fail every update.
    /// Start fresh on a decoding error; let storage errors propagate so the stored state is kept for the next attempt.
    private func storedState() throws -> PromptExposureState? {
        do {
            return try storage.value(for: \.state)
        } catch {
            guard error is DecodingError else { throw error }
            Logger.modalPrompt.error("Discarding undecodable prompt exposure state: \(error, privacy: .public)")
            return nil
        }
    }

    private static func daysSinceInstall(_ installDate: Date, at date: Date) -> Int {
        Int(floor(date.timeIntervalSince(installDate) / secondsPerDay))
    }
}
