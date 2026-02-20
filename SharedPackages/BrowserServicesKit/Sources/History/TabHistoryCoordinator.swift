//
//  TabHistoryCoordinator.swift
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

import Common
import Foundation
import os.log

public protocol TabHistoryCoordinating {
    @MainActor func tabHistory(tabID: String) async throws -> [URL]
    @MainActor func addVisit(of url: URL, tabID: String?)
    @MainActor func removeVisits(for tabIDs: [String]) async throws
}

final public class TabHistoryCoordinator: TabHistoryCoordinating {

    let tabHistoryStoring: TabHistoryStoring
    let openTabIDsProvider: () -> [String]
    private var regularCleaningTimer: Timer?

    public init(tabHistoryStoring: TabHistoryStoring,
                openTabIDsProvider: @escaping () -> [String]) {
        self.tabHistoryStoring = tabHistoryStoring
        self.openTabIDsProvider = openTabIDsProvider

        Task { @MainActor in
            await cleanOrphanedEntries()
            scheduleRegularCleaning()
        }
    }

    deinit {
        regularCleaningTimer?.invalidate()
    }

    @MainActor
    public func tabHistory(tabID: String) async throws -> [URL] {
        return try await tabHistoryStoring.tabHistory(for: tabID)
    }

    @MainActor
    public func addVisit(of url: URL, tabID: String?) {
        guard let tabID else {
            return
        }
        Task {
            do {
                try await tabHistoryStoring.insertTabHistory(for: tabID, url: url)
            } catch {
                Logger.history.error("Failed to record visit: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    public func removeVisits(for tabIDs: [String]) async throws {
        try await tabHistoryStoring.removeTabHistory(for: tabIDs)
    }

    @MainActor
    func cleanOrphanedEntries() async {
        let openTabIDs = openTabIDsProvider()
        do {
            try await tabHistoryStoring.cleanOrphanedTabHistory(excludingTabIDs: openTabIDs)
            Logger.history.debug("Tab history orphan cleanup completed successfully")
        } catch {
            Logger.history.error("Failed to clean orphaned tab history: \(error.localizedDescription)")
        }
    }

    private func scheduleRegularCleaning() {
        let timer = Timer(fire: .startOfDayTomorrow,
                          interval: .day,
                          repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.cleanOrphanedEntries()
            }
        }
        RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
        regularCleaningTimer = timer
    }
}
