//
//  WebsiteDataFireWorker.swift
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
import BrowserServicesKit
import WKAbstractions

struct WebsiteDataFireWorker: FireExecutorWorker {
    private let websiteDataManager: WebsiteDataManaging
    private let dataStore: (any DDGWebsiteDataStore)?
    private let dataClearingWideEventService: DataClearingWideEventService?
    
    init(websiteDataManager: WebsiteDataManaging,
         dataStore: (any DDGWebsiteDataStore)?,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.websiteDataManager = websiteDataManager
        self.dataStore = dataStore
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnAllData() async {
        // If the user is on a version that uses containers, then we'll clear the current container, then migrate it. Otherwise
        //  this is the same as `WKWebsiteDataStore.default()`
        let storeToUse = dataStore ?? DDGWebsiteDataStoreProvider.current()
        
        let websiteDataResult = await websiteDataManager.clear(dataStore: storeToUse)
        updateWideEventWithWebsiteDataResults(websiteDataResult)
    }
    
    @MainActor
    func burnFireModeData() async {
        // TODO: - To be implemented
    }
    
    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        let timedPixel = TimedPixel(.singleTabDataCleared)

        // If the user is on a version that uses containers, then we'll clear the current container, then migrate it. Otherwise
        //  this is the same as `WKWebsiteDataStore.default()`
        let storeToUse = dataStore ?? DDGWebsiteDataStoreProvider.current()

        // Async tasks
        let websiteDataResult = await websiteDataManager.clear(dataStore: storeToUse, forDomains: domains)
        updateWideEventWithWebsiteDataResults(websiteDataResult)

    }
    
    private func updateWideEventWithWebsiteDataResults(_ result: WebsiteDataClearingResult) {
        dataClearingWideEventService?.update(.clearSafelyRemovableWebsiteData, actionResult: result.safelyRemovableData)
        dataClearingWideEventService?.update(.clearFireproofableDataForNonFireproofDomains, actionResult: result.fireproofableData)
        dataClearingWideEventService?.update(.clearCookiesForNonFireproofedDomains, actionResult: result.cookies)
        dataClearingWideEventService?.update(.removeObservationsData, actionResult: result.observationsData)
        if let removeContainersResult = result.removeAllContainersAfterDelay {
            dataClearingWideEventService?.update(.removeAllContainersAfterDelay, actionResult: removeContainersResult)
        }
    }
}
