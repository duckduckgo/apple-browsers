//
//  AutoConsentFireWorker.swift
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

struct AutoConsentFireWorker: FireExecutorWorker {

    private let autoconsentManagementProvider: AutoconsentManagementProviding
    private let dataClearingWideEventService: DataClearingWideEventService?

    init(autoconsentManagementProvider: AutoconsentManagementProviding,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.autoconsentManagementProvider = autoconsentManagementProvider
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnNormalModeData() async {
        dataClearingWideEventService?.start(.clearAutoconsentManagementCache)
        let result = autoconsentManagementProvider.management(for: .normal).clearCache()
        dataClearingWideEventService?.update(.clearAutoconsentManagementCache, result: result)
    }

    @MainActor
    func burnFireModeData() async {
        dataClearingWideEventService?.start(.clearAutoconsentManagementCacheFireMode)
        let result = autoconsentManagementProvider.management(for: .fireMode).clearCache()
        dataClearingWideEventService?.update(.clearAutoconsentManagementCacheFireMode, result: result)
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        dataClearingWideEventService?.start(.clearAutoconsentManagementCache)
        let result = autoconsentManagementProvider.management(for: tabViewModel.tab.autoconsentContext).clearCache(forDomains: domains)
        dataClearingWideEventService?.update(.clearAutoconsentManagementCache, result: result)
    }
}
