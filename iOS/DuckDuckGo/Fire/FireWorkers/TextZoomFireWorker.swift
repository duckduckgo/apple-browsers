//
//  TextZoomFireWorker.swift
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

struct TextZoomFireWorker: FireExecutorWorker {

    private let fireproofing: Fireproofing
    private let textZoomCoordinatorProvider: TextZoomCoordinatorProviding
    private let dataClearingWideEventService: DataClearingWideEventService?

    init(fireproofing: Fireproofing,
         textZoomCoordinatorProvider: TextZoomCoordinatorProviding,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.fireproofing = fireproofing
        self.textZoomCoordinatorProvider = textZoomCoordinatorProvider
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnNormalModeData() async {
        dataClearingWideEventService?.start(.forgetTextZoom)
        let allowedDomains = fireproofing.allowedDomains
        let coordinator = textZoomCoordinatorProvider.coordinator(for: .normal)
        coordinator.resetTextZoomLevels(excludingDomains: allowedDomains)
        dataClearingWideEventService?.update(.forgetTextZoom, result: .success(()))
    }

    @MainActor
    func burnFireModeData() async {
        dataClearingWideEventService?.start(.forgetTextZoomFireMode)
        let coordinator = textZoomCoordinatorProvider.coordinator(for: .fireMode)
        coordinator.resetTextZoomLevels(excludingDomains: [])
        dataClearingWideEventService?.update(.forgetTextZoomFireMode, result: .success(()))
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        dataClearingWideEventService?.start(.forgetTextZoom)
        let allowedDomains = fireproofing.allowedDomains
        let coordinator = textZoomCoordinatorProvider.coordinator(for: tabViewModel.tab.textZoomContext)
        coordinator.resetTextZoomLevels(forVisitedDomains: domains, excludingDomains: allowedDomains)
        dataClearingWideEventService?.update(.forgetTextZoom, result: .success(()))
    }
}
