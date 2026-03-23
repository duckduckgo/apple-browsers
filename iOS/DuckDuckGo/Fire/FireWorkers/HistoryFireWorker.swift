//
//  HistoryFireWorker.swift
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

import Core

struct HistoryFireWorker: FireExecutorWorker {

    private let historyManager: HistoryManaging
    private let dataClearingWideEventService: DataClearingWideEventService?

    init(historyManager: HistoryManaging,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.historyManager = historyManager
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnNormalModeData() async {
        dataClearingWideEventService?.start(.clearAllHistory)
        let result = await historyManager.removeAllHistory()
        dataClearingWideEventService?.update(.clearAllHistory, result: result)
    }

    @MainActor
    func burnFireModeData() async {
        // Fire mode does not persist browsing history, so there is nothing to clear
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        dataClearingWideEventService?.start(.clearAllHistory)
        let result = await historyManager.removeBrowsingHistory(tabID: tabViewModel.tab.uid)
        if let result {
            dataClearingWideEventService?.update(.clearAllHistory, actionResult: result)
        }
    }
}
