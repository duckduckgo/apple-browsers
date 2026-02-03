//
//  HistoryMocks.swift
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
import XCTest
import BrowserServicesKit
import Persistence
import History
@testable import Core

class MockHistoryManager: HistoryManaging {
    
    var addVisitCalls = [URL]()
    var updateTitleIfNeededCalls = [(title: String, url: URL)]()
    var tabHistoryCalls: [String] = []
    var removeTabHistoryCalls: [[String]] = []
    var tabHistoryResult: [URL] = []
    var removeBrowsingHistoryCalls: [String] = []
    
    /// Expectation that is fulfilled when `removeTabHistory` is called
    var removeTabHistoryExpectation: XCTestExpectation?

    let historyCoordinator: HistoryCoordinating
    var isEnabledByUser: Bool
    var historyFeatureEnabled: Bool
    private(set) var removeAllHistoryCallCount = 0

    convenience init() {
        self.init(historyCoordinator: NullHistoryCoordinator(), isEnabledByUser: false, historyFeatureEnabled: false)
    }

    init(historyCoordinator: HistoryCoordinating, isEnabledByUser: Bool, historyFeatureEnabled: Bool) {
        self.historyCoordinator = historyCoordinator
        self.historyFeatureEnabled = historyFeatureEnabled
        self.isEnabledByUser = isEnabledByUser
    }

    func isHistoryFeatureEnabled() -> Bool {
        return historyFeatureEnabled
    }

    func removeAllHistory() async {
        removeAllHistoryCallCount += 1
    }

    func deleteHistoryForURL(_ url: URL) async {
    }
    
    @MainActor
    var history: History.BrowsingHistory? {
        historyCoordinator.history
    }
    
    func addVisit(of url: URL, tabID: String?) {
        addVisitCalls.append(url)
    }
    
    func updateTitleIfNeeded(title: String, url: URL) {
        updateTitleIfNeededCalls.append((title: title, url: url))
    }
    
    func commitChanges(url: URL) {
    }
    
    func tabHistory(tabID: String) async throws -> [URL] {
        tabHistoryCalls.append(tabID)
        return tabHistoryResult
    }
    
    func removeTabHistory(for tabIDs: [String]) async {
        removeTabHistoryCalls.append(tabIDs)
        removeTabHistoryExpectation?.fulfill()
    }
    
    func removeBrowsingHistory(tabID: String) async {
        removeBrowsingHistoryCalls.append(tabID)
    }

}

class MockTabHistoryCoordinating: TabHistoryCoordinating {
    var addVisitCalls: [(url: URL, tabID: String?)] = []
    var tabHistoryCalls: [String] = []
    var removeVisitsCalls: [[String]] = []
    var cleanOrphanedEntriesCalls: Int = 0
    var tabHistoryResult: [URL] = []

    func tabHistory(tabID: String) async throws -> [URL] {
        tabHistoryCalls.append(tabID)
        return tabHistoryResult
    }
    
    func addVisit(of url: URL, tabID: String?) {
        addVisitCalls.append((url, tabID))
    }
    
    func removeVisits(for tabIDs: [String]) async throws {
        removeVisitsCalls.append(tabIDs)
    }

    func cleanOrphanedEntries() async {
        cleanOrphanedEntriesCalls += 1
    }
}

class SpyHistoryCoordinator: NullHistoryCoordinator {
    var addVisitCalls: [(url: URL, tabID: String?)] = []
    
    override func addVisit(of url: URL, at date: Date, tabID: String?) -> Visit? {
        addVisitCalls.append((url, tabID))
        return nil
    }
}

class SpyBurnVisitsHistoryCoordinator: NullHistoryCoordinator {
    var burnVisitsForTabIDCalls: [String] = []

    override func burnVisits(for tabID: String) async throws {
        burnVisitsForTabIDCalls.append(tabID)
    }
}
