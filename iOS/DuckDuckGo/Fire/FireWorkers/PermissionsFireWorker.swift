//
//  PermissionsFireWorker.swift
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
import Foundation
import SitePermissions

struct PermissionsFireWorker: FireExecutorWorker {

    private let store: SitePermissionsStore
    private let fireproofing: Fireproofing
    private let dataClearingWideEventService: DataClearingWideEventService?

    init(store: SitePermissionsStore,
         fireproofing: Fireproofing,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.store = store
        self.fireproofing = fireproofing
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnNormalModeData() async {
        dataClearingWideEventService?.start(.clearPermissions)
        store.clearSitePermissions { fireproofing.isAllowed(fireproofDomain: $0) }
        dataClearingWideEventService?.update(.clearPermissions, result: .success(()))
    }

    @MainActor
    func burnFireModeData() async {
        // Site permissions use a single persistent store, so fire-mode clearing must not clear it.
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        await burnTabData(tabViewModel: tabViewModel, domainResult: .success(domains))
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domainResult: Result<[String], Error>) async {
        guard !tabViewModel.tab.fireTab else { return }

        dataClearingWideEventService?.start(.clearPermissions)
        let domains: [String]
        switch domainResult {
        case .success(let fetchedDomains):
            domains = fetchedDomains
        case .failure(let error):
            dataClearingWideEventService?.update(.clearPermissions, result: .failure(error))
            return
        }

        let sites = Set<SitePermissionKey>(domains.compactMap { domain in
            let urlHost = domain.contains(":") ? "[\(domain)]" : domain
            guard let url = URL(string: "https://\(urlHost)"),
                  let site = SitePermissionKey(committedURL: url),
                  !fireproofing.isAllowed(fireproofDomain: site.host) else {
                return nil
            }
            return site
        })
        store.removePermissions(for: sites)
        dataClearingWideEventService?.update(.clearPermissions, result: .success(()))
    }
}
