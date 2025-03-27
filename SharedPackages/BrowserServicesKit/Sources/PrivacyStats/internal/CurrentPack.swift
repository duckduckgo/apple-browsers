//
//  CurrentPack.swift
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

import Combine
import Foundation
import os.log

/**
 * This actor provides thread-safe access to an instance of `PrivacyStatsPack`.
 *
 * It's used by `PrivacyStats` class to record blocked trackers that can possibly
 * come from multiple open tabs (web views) at the same time.
 */
actor CurrentPack {
    /**
     * Current stats pack.
     */
    private(set) var pack: PrivacyStatsPack

    /**
     * Publisher that fires events whenever tracker stats are ready to be persisted to disk.
     *
     * This happens after recording new blocked tracker, when no new tracker has been recorded for 1s.
     */
    nonisolated private(set) lazy var commitChangesPublisher: AnyPublisher<PrivacyStatsPack, Never> = commitChangesSubject.eraseToAnyPublisher()

    nonisolated private let commitChangesSubject = PassthroughSubject<PrivacyStatsPack, Never>()
    private var commitTask: Task<Void, Never>?
    private var commitDebounce: UInt64

    /// The `commitDebounce` parameter should only be modified in unit tests.
    init(pack: PrivacyStatsPack, commitDebounce: UInt64 = 1_000_000_000) {
        self.pack = pack
        self.commitDebounce = commitDebounce
    }

    deinit {
        commitTask?.cancel()
    }

    /**
     * This function is used when clearing app data, to clear any stats cached in memory.
     *
     * It sets a new empty pack with the current timestamp.
     */
    func resetPack() {
        resetStats(andSet: Date.currentPrivacyStatsPackTimestamp)
    }

    /**
     * This function increments trackers count for a given company name.
     *
     * Updates are kept in memory and scheduled for saving to persistent storage with 1s debounce.
     * This function also detects when the current pack becomes outdated (which happens
     * when current timestamp's day becomes greater than pack's timestamp's day), in which
     * case current pack is scheduled for persisting on disk and a new empty pack is
     * created for the new timestamp.
     */
    func recordBlockedTracker(_ companyName: String) {

        let currentTimestamp = Date.currentPrivacyStatsPackTimestamp
        if currentTimestamp != pack.timestamp {
            Logger.privacyStats.debug("New timestamp detected, storing trackers state and creating new pack")
            notifyChanges(for: pack, immediately: true)
            resetStats(andSet: currentTimestamp)
        }

        let count = pack.trackers[companyName] ?? 0
        pack.trackers[companyName] = count + 1

        notifyChanges(for: pack, immediately: false)
    }

    private func notifyChanges(for pack: PrivacyStatsPack, immediately shouldPublishImmediately: Bool) {
        commitTask?.cancel()

        if shouldPublishImmediately {

            commitChangesSubject.send(pack)

        } else {

            commitTask = Task {
                do {
                    // Note that this doesn't always sleep for the full debounce time, but the sleep is interrupted
                    // as soon as the task gets cancelled.
                    try await Task.sleep(nanoseconds: commitDebounce)

                    Logger.privacyStats.debug("Storing trackers state")
                    commitChangesSubject.send(pack)
                } catch {
                    // Commit task got cancelled
                }
            }
        }
    }

    private func resetStats(andSet newTimestamp: Date) {
        pack = PrivacyStatsPack(timestamp: newTimestamp, trackers: [:])
    }
}
