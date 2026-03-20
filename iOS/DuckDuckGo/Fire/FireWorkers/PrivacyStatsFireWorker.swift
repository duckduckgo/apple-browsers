//
//  PrivacyStatsFireWorker.swift
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

struct PrivacyStatsFireWorker: FireExecutorWorker {

    private let privacyStats: PrivacyStatsProviding?
    private let dataClearingWideEventService: DataClearingWideEventService?

    init(privacyStats: PrivacyStatsProviding?,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.privacyStats = privacyStats
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnNormalModeData() async {
        dataClearingWideEventService?.start(.clearPrivacyStats)
        let result = await privacyStats?.clearPrivacyStats() ?? .success(())
        dataClearingWideEventService?.update(.clearPrivacyStats, result: result)
    }

    @MainActor
    func burnFireModeData() async {
        // Privacy stats are aggregated globally and not scoped to browsing mode
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        // Privacy stats are aggregated globally and not scoped to individual tabs
    }
}
