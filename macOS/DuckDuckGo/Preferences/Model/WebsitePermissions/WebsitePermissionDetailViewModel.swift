//
//  WebsitePermissionDetailViewModel.swift
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

import Combine
import Foundation
import PrivacyConfig
import os.log

@MainActor
final class WebsitePermissionDetailViewModel: ObservableObject {
    @Published
    private(set) var viewState: WebsitePermissionDetailViewState

    private let permissionManager: PermissionManagerProtocol
    private let featureFlagger: FeatureFlagger
    private var permissionsCancellable: AnyCancellable?

    init(
        initialState: WebsitePermissionDetailViewState?,
        permissionManager: PermissionManagerProtocol,
        featureFlagger: FeatureFlagger
    ) {
        viewState = initialState ?? .init()
        self.permissionManager = permissionManager
        self.featureFlagger = featureFlagger
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            setupObserver()

        case .setSearchQuery(let query):
            viewState.searchQuery = query

        case .changeDecision(let rowID, let decision):
            changeDecision(decision, for: rowID)

        case .remove(let rowID):
            remove(rowID: rowID)
        }
    }

    // MARK: - Private

    private func changeDecision(_ decision: PersistedPermissionDecision, for rowID: WebsitePermissionDetailViewState.SiteRow.ID) {
        guard
            let siteRow = row(matchingID: rowID),
            siteRow.permissionType.isUserEditable(forDomain: siteRow.domain, featureFlagger: featureFlagger),
            siteRow.availableDecisions.contains(decision),
            siteRow.decision != decision
        else {
            Logger.general.debug("WebsitePermissionDetailViewModel: Ignored permission decision change for row \(rowID)")
            return
        }
        permissionManager.setPermission(decision, forDomain: siteRow.domain, permissionType: siteRow.permissionType)
    }

    private func remove(rowID: WebsitePermissionDetailViewState.SiteRow.ID) {
        guard
            let siteRow = row(matchingID: rowID),
            siteRow.permissionType.isUserEditable(forDomain: siteRow.domain, featureFlagger: featureFlagger)
        else {
            Logger.general.debug("WebsitePermissionDetailViewModel: Ignored permission removal for row \(rowID)")
            return
        }
        permissionManager.removePermission(forDomain: siteRow.domain, permissionType: siteRow.permissionType)
    }

    private func setupObserver() {
        guard permissionsCancellable == nil else { return }

        permissionsCancellable = permissionManager.persistedPermissionsPublisher
            .combineLatest(featureFlagger.updatesPublisher.prepend(()))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries, _ in
                self?.updateState(entries: entries)
            }
    }

    private func updateState(entries: [WebsitePermissionEntry]) {
        viewState = WebsitePermissionDetailViewState(
            category: viewState.category,
            searchQuery: viewState.searchQuery,
            entries: entries,
            featureFlagger: featureFlagger
        )
    }

    private func row(matchingID id: WebsitePermissionDetailViewState.SiteRow.ID) -> WebsitePermissionDetailViewState.SiteRow? {
        viewState.sites.first { $0.id == id }
    }
}

extension WebsitePermissionDetailViewModel {
    enum Action {
        case onAppear
        case setSearchQuery(String)
        case changeDecision(rowID: WebsitePermissionDetailViewState.SiteRow.ID, decision: PersistedPermissionDecision)
        case remove(rowID: WebsitePermissionDetailViewState.SiteRow.ID)
    }
}
