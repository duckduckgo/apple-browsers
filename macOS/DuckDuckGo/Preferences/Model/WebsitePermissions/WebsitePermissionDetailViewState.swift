//
//  WebsitePermissionDetailViewState.swift
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

import Common
import Foundation

struct WebsitePermissionDetailViewState: Equatable {
    let category: WebsitePermissionCategory
    private(set) var searchQuery: String
    let sites: [SiteRow]
    private(set) var visibleSites: [SiteRow]

    init(category: WebsitePermissionCategory, searchQuery: String = "", sites: [SiteRow] = []) {
        self.category = category
        self.searchQuery = searchQuery
        self.sites = sites
        self.visibleSites = []
        self.visibleSites = filteredSites(from: sites, matching: searchQuery)
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
        visibleSites = filteredSites(from: sites, matching: query)
    }

    private func filteredSites(from sites: [SiteRow], matching query: String) -> [SiteRow] {
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
