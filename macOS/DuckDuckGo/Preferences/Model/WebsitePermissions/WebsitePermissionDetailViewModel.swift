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

@MainActor
final class WebsitePermissionDetailViewModel: ObservableObject {

    @Published
    private(set) var viewState: WebsitePermissionDetailViewState

    private let permissionManager: PermissionManagerProtocol
    private let featureFlagger: FeatureFlagger
    private var permissionsCancellable: AnyCancellable?

    init(
        category: WebsitePermissionCategory,
        permissionManager: PermissionManagerProtocol,
        featureFlagger: FeatureFlagger
    ) {
        viewState = WebsitePermissionDetailViewState(category: category)
        self.permissionManager = permissionManager
        self.featureFlagger = featureFlagger
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            setupObserver()

        case .setSearchQuery(let query):
            viewState.setSearchQuery(query)

        case .changeDecision(let row, let decision):
            guard let currentRow = currentRow(matching: row),
                  currentRow.permissionType.isUserEditable(forDomain: currentRow.domain, featureFlagger: featureFlagger),
                  currentRow.availableDecisions.contains(decision),
                  currentRow.decision != decision else { return }
            permissionManager.setPermission(decision, forDomain: currentRow.domain, permissionType: currentRow.permissionType)

        case .remove(let row):
            guard let currentRow = currentRow(matching: row),
                  currentRow.permissionType.isUserEditable(forDomain: currentRow.domain, featureFlagger: featureFlagger) else { return }
            permissionManager.removePermission(forDomain: currentRow.domain, permissionType: currentRow.permissionType)
        }
    }

    // MARK: - Private

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
        let category = viewState.category
        let sites = entries
            .filter {
                category.contains($0.permissionType) &&
                    $0.permissionType.isUserEditable(forDomain: $0.domain, featureFlagger: featureFlagger)
            }
            .map(makeSiteRow)
            .sorted(by: isOrderedBefore)

        viewState = WebsitePermissionDetailViewState(
            category: category,
            searchQuery: viewState.searchQuery,
            sites: sites
        )
    }

    private func makeSiteRow(from entry: WebsitePermissionEntry) -> WebsitePermissionDetailViewState.SiteRow {
        .init(
            domain: entry.domain,
            permissionType: entry.permissionType,
            decision: entry.displayedDecision,
            permissionTitle: permissionTitle(for: entry.permissionType),
            availableDecisions: entry.permissionType.editableDecisions
        )
    }

    private func permissionTitle(for permissionType: PermissionType) -> String? {
        guard permissionType.isExternalScheme else { return nil }
        return String(format: UserText.websitePermissionsExternalAppFormat, permissionType.localizedDescription)
    }

    private func isOrderedBefore(_ first: WebsitePermissionDetailViewState.SiteRow,
                                 _ second: WebsitePermissionDetailViewState.SiteRow) -> Bool {
        let domainComparison = first.domain.localizedCaseInsensitiveCompare(second.domain)
        if domainComparison != .orderedSame {
            return domainComparison == .orderedAscending
        }
        return first.permissionType.rawValue < second.permissionType.rawValue
    }

    private func currentRow(matching row: WebsitePermissionDetailViewState.SiteRow) -> WebsitePermissionDetailViewState.SiteRow? {
        viewState.sites.first { $0.id == row.id }
    }
}

extension WebsitePermissionDetailViewModel {
    enum Action {
        case onAppear
        case setSearchQuery(String)
        case changeDecision(WebsitePermissionDetailViewState.SiteRow, PersistedPermissionDecision)
        case remove(WebsitePermissionDetailViewState.SiteRow)
    }
}

struct WebsitePermissionDetailViewState: Equatable {
    let category: WebsitePermissionCategory
    private(set) var searchQuery: String
    let sites: [SiteRow]
    private(set) var visibleSites: [SiteRow]

    init(category: WebsitePermissionCategory, searchQuery: String = "", sites: [SiteRow] = []) {
        self.category = category
        self.searchQuery = searchQuery
        self.sites = sites
        visibleSites = Self.filteredSites(from: sites, matching: searchQuery)
    }

    var isEmpty: Bool {
        sites.isEmpty
    }

    var hasNoResults: Bool {
        !sites.isEmpty && visibleSites.isEmpty
    }

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func setSearchQuery(_ query: String) {
        searchQuery = query
        visibleSites = Self.filteredSites(from: sites, matching: query)
    }

    private static func filteredSites(from sites: [SiteRow], matching query: String) -> [SiteRow] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return sites }

        let foldedQuery = normalizedQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return sites.filter {
            $0.domain
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(foldedQuery)
        }
    }
}

extension WebsitePermissionDetailViewState {
    struct SiteRow: Identifiable, Equatable {
        let domain: String
        let permissionType: PermissionType
        let decision: PersistedPermissionDecision
        let permissionTitle: String?
        let availableDecisions: [PersistedPermissionDecision]

        var id: String {
            "\(domain)|\(permissionType.rawValue)"
        }

        var faviconURL: URL? {
            URL(string: "\(URL.NavigationalScheme.https.separated())\(domain)")
        }

        var accessibilityIdentifier: String {
            "WebsitePermissions.Detail.Row.\(id)"
        }
    }
}
