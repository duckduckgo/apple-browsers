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

import Foundation

public protocol TabHistoryCoordinating {
    @MainActor func tabHistory(tabID: String) async throws -> [URL]
    @MainActor func addVisit(of url: URL, tabID: String?) async throws
    @MainActor func removeVisits(for tabIDs: [String]) async throws
}

final public class TabHistoryCoordinator: TabHistoryCoordinating {

    let tabHistoryStoring: TabHistoryStoring

    public init(tabHistoryStoring: TabHistoryStoring) {
        self.tabHistoryStoring = tabHistoryStoring
    }

    @MainActor
    public func tabHistory(tabID: String) async throws -> [URL] {
        return try await tabHistoryStoring.tabHistory(for: tabID)
    }

    @MainActor
    public func addVisit(of url: URL, tabID: String?) async throws {
        guard let tabID else {
            return
        }
        try await tabHistoryStoring.insertTabHistory(for: tabID, url: url)
    }

    @MainActor
    public func removeVisits(for tabIDs: [String]) async throws {
        try await tabHistoryStoring.removeTabHistory(for: tabIDs)
    }
}
