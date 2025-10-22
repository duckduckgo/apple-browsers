//
//  PromptCooldownManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Information about the current cooldown period state.
struct PromptCooldownInfo {
    /// Whether prompts are currently in the cooldown period.
    let isInCooldownPeriod: Bool

    /// The date when a prompt was last presented, or `nil` if no prompt has been shown yet.
    let lastPresentationDate: Date?

    /// The date when the next prompt can be presented.
    /// If no prompt has been shown yet, this equals the current date.
    /// Otherwise, this equals `lastPresentationDate` + cooldown interval.
    let nextPresentationDate: Date
}

/// A type that manages prompt cooldown state.
protocol PromptCooldownManaging {
    /// Return a struct containing the information on the cooldown period.
    var cooldownInfo: PromptCooldownInfo { get }

    /// Records that a prompt was presented.
    /// This starts the cooldown period. No prompts should be shown until the cooldown interval has elapsed.
    func recordLastPromptPresentationTimestamp()
}

extension PromptCooldownManaging {

    /// Returns `true` if prompts are currently in the cooldown period, `false` otherwise.
    var isInCooldownPeriod: Bool {
        cooldownInfo.isInCooldownPeriod
    }
}

/// Generic prompt cooldown manager for any prompt type.
final class PromptCooldownManager: PromptCooldownManaging {
    private let presentationStore: PromptCooldownStore
    private let cooldownIntervalProvider: PromptCooldownIntervalProviding
    private let dateProvider: () -> Date

    private var cooldownInterval: TimeInterval {
        .hours(cooldownIntervalProvider.cooldownInterval)
    }

    /// Creates a new prompt cooldown manager.
    ///
    /// - Parameters:
    ///   - presentationStore: Store for tracking when prompts were last presented.
    ///   - cooldownIntervalProvider: Provider for the cooldown interval duration.
    ///   - dateProvider: Closure providing current date (defaults to Date.init for testability).
    init(
        presentationStore: PromptCooldownStore,
        cooldownIntervalProvider: PromptCooldownIntervalProviding,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.presentationStore = presentationStore
        self.cooldownIntervalProvider = cooldownIntervalProvider
        self.dateProvider = dateProvider
    }

    var cooldownInfo: PromptCooldownInfo {
        let now = dateProvider()
        let lastPresentationDate = presentationStore.lastPresentationTimestamp.flatMap(Date.init(timeIntervalSince1970:))
        let nextPresentationDate = lastPresentationDate?.addingTimeInterval(cooldownInterval) ?? now

        return PromptCooldownInfo(
            isInCooldownPeriod: isInCooldownPeriod,
            lastPresentationDate: lastPresentationDate,
            nextPresentationDate: nextPresentationDate
        )
    }

    var isInCooldownPeriod: Bool {
        // If last presentation timestamp is nil it means we never presented the modal so we're not in a cooldown period
        guard let lastPresentationDate = presentationStore.lastPresentationTimestamp else {
            return false
        }

        let currentTime = dateProvider().timeIntervalSince1970
        let timeSinceLastPresentation = currentTime - lastPresentationDate

        return timeSinceLastPresentation < cooldownInterval
    }

    func recordLastPromptPresentationTimestamp() {
        presentationStore.lastPresentationTimestamp = dateProvider().timeIntervalSince1970
    }
}
