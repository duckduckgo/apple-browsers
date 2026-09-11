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
    private let defaults: WebsitePermissionDefaultsProviding
    private var permissionsCancellable: AnyCancellable?

    init(
        initialState: WebsitePermissionDetailViewState?,
        permissionManager: PermissionManagerProtocol,
        featureFlagger: FeatureFlagger,
        defaults: WebsitePermissionDefaultsProviding
    ) {
        viewState = initialState ?? .init()
        self.permissionManager = permissionManager
        self.featureFlagger = featureFlagger
        self.defaults = defaults
        // Seed the default from storage so the radio group renders its real selection before the
        // permission observer delivers its first update.
        viewState.defaultDecision = defaults.defaultDecision(for: viewState.category)
        viewState.visibleSites = filteredSites(from: viewState.sites, matching: viewState.searchQuery)
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            setupObserver()

        case .setDefaultDecision(let decision):
            changeDefaultDecision(decision)

        case .setSearchQuery(let query):
            var state = viewState
            state.searchQuery = query
            state.visibleSites = filteredSites(from: state.sites, matching: query)
            viewState = state

        case .changeDecision(let rowID, let decision):
            changeDecision(decision, for: rowID)

        case .remove(let rowID):
            remove(rowID: rowID)
        }
    }

    // MARK: - Private

    private func changeDefaultDecision(_ decision: PersistedPermissionDecision) {
        let category = viewState.category
        guard WebsitePermissionDefaults.availableDecisions.contains(decision),
              decision != defaults.defaultDecision(for: category)
        else {
            Logger.general.debug("WebsitePermissionDetailViewModel: Ignored default change for \(String(describing: category))")
            return
        }

        defaults.setDefaultDecision(decision, for: category)

        // Read back rather than trusting the request: the write is a no-op while the feature flag is off.
        viewState.defaultDecision = defaults.defaultDecision(for: category)
    }

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
            .combineLatest(featureFlagger.updatesPublisher.prepend(()), defaults.defaultsPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries, _, defaultDecisions in
                self?.updateState(entries: entries, defaultDecisions: defaultDecisions)
            }
    }

    private func updateState(entries: [WebsitePermissionEntry],
                             defaultDecisions: [WebsitePermissionCategory: PersistedPermissionDecision]) {
        let category = viewState.category
        var state = WebsitePermissionDetailViewState(
            category: category,
            defaultDecision: defaultDecisions[category] ?? WebsitePermissionDefaults.fallbackDecision,
            searchQuery: viewState.searchQuery,
            entries: entries,
            featureFlagger: featureFlagger
        )
        state.visibleSites = filteredSites(from: state.sites, matching: state.searchQuery)
        viewState = state
    }

    private func filteredSites(
        from sites: [WebsitePermissionDetailViewState.SiteRow],
        matching query: String
    ) -> [WebsitePermissionDetailViewState.SiteRow] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return sites }

        let foldedQuery = foldedForSearch(trimmedQuery)
        return sites.filter { site in
            searchableValues(for: site).contains { value in
                foldedForSearch(value).contains(foldedQuery)
            }
        }
    }

    private func searchableValues(for site: WebsitePermissionDetailViewState.SiteRow) -> [String] {
        guard case .externalScheme(let scheme) = site.permissionType else {
            return [site.domain]
        }

        return [site.domain, "\(scheme)://", site.externalAppName].compactMap { $0 }
    }

    private func foldedForSearch(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func row(matchingID id: WebsitePermissionDetailViewState.SiteRow.ID) -> WebsitePermissionDetailViewState.SiteRow? {
        viewState.sites.first { $0.id == id }
    }
}

extension WebsitePermissionDetailViewModel {
    enum Action {
        case onAppear
        case setDefaultDecision(PersistedPermissionDecision)
        case setSearchQuery(String)
        case changeDecision(rowID: WebsitePermissionDetailViewState.SiteRow.ID, decision: PersistedPermissionDecision)
        case remove(rowID: WebsitePermissionDetailViewState.SiteRow.ID)
    }
}
