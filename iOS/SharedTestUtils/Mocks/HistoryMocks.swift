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

class MockHistoryCoordinator: NullHistoryCoordinator {

    var addVisitCalls = [URL]()
    var updateTitleIfNeededCalls = [(title: String, url: URL)]()

    override func addVisit(of url: URL) -> Visit? {
        addVisitCalls.append(url)
        return nil
    }

    override func updateTitleIfNeeded(title: String, url: URL) {
        updateTitleIfNeededCalls.append((title: title, url: url))
    }

}

class MockHistoryManager: HistoryManaging {

    let historyCoordinator: HistoryCoordinating
    var isEnabledByUser: Bool
    var historyFeatureEnabled: Bool

    convenience init() {
        self.init(historyCoordinator: MockHistoryCoordinator(), isEnabledByUser: false, historyFeatureEnabled: false)
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
    }

    func deleteHistoryForURL(_ url: URL) async {
    }

 }
