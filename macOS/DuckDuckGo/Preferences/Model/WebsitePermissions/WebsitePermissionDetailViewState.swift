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
import PrivacyConfig

struct WebsitePermissionDetailViewState: Equatable {
    var category: WebsitePermissionCategory = .notifications
    var searchQuery = ""
    var sites: [SiteRow] = []
    var visibleSites: [SiteRow] {
        filteredSites(from: sites, matching: searchQuery)
    }
    var visibleGroups: [SiteGroup] {
        groupedByDomain(visibleSites)
    }
    var isEmpty: Bool {
        sites.isEmpty
    }
    var hasNoResults: Bool {
        !sites.isEmpty && visibleSites.isEmpty
    }

    init(
        category: WebsitePermissionCategory = .notifications,
        searchQuery: String = "",
        sites: [SiteRow] = []
    ) {
        self.category = category
        self.searchQuery = searchQuery
        self.sites = sites
    }

    init(
        category: WebsitePermissionCategory,
        searchQuery: String = "",
        entries: [WebsitePermissionEntry],
        featureFlagger: FeatureFlagger
    ) {
        let sites = entries
            .filter {
                category.contains($0.permissionType) && $0.permissionType.isUserEditable(forDomain: $0.domain, featureFlagger: featureFlagger)
            }
            .map { entry in
                SiteRow(
                    domain: entry.domain,
                    permissionType: entry.permissionType,
                    decision: entry.displayedDecision,
                    permissionTitle: entry.permissionType.isExternalScheme
                        ? String(format: UserText.websitePermissionsExternalAppFormat, entry.permissionType.localizedDescription)
                        : nil,
                    availableDecisions: entry.permissionType.editableDecisions
                )
            }
            .sorted {
                let domainComparison = $0.domain.localizedCaseInsensitiveCompare($1.domain)
                if domainComparison != .orderedSame {
                    return domainComparison == .orderedAscending
                }
                return $0.permissionType.rawValue < $1.permissionType.rawValue
            }

        self.init(category: category, searchQuery: searchQuery, sites: sites)
    }

    /// Collapses rows into one group per domain, so a site holding several permissions is listed once.
    /// `sites` is sorted by domain, so each domain's rows are adjacent.
    private func groupedByDomain(_ rows: [SiteRow]) -> [SiteGroup] {
        rows.reduce(into: [SiteGroup]()) { groups, row in
            if let lastGroup = groups.last, lastGroup.domain == row.domain {
                groups[groups.endIndex - 1] = SiteGroup(domain: lastGroup.domain, rows: lastGroup.rows + [row])
            } else {
                groups.append(SiteGroup(domain: row.domain, rows: [row]))
            }
        }
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

        /// Label for the row when it is listed under a domain heading, which already names the site.
        var subRowTitle: String {
            permissionTitle ?? permissionType.localizedDescription
        }

        var accessibilityIdentifier: String {
            "WebsitePermissions.Detail.Row.\(id)"
        }
    }

    struct SiteGroup: Identifiable, Equatable {
        let domain: String
        let rows: [SiteRow]

        var id: String {
            domain
        }

        var faviconURL: URL? {
            rows.first?.faviconURL
        }

        /// External App permissions are keyed by scheme, so one domain can hold several of them: they are
        /// listed as labelled rows beneath the domain. Every other category has a single permission per
        /// domain, which reads better inline with the domain itself.
        var showsDomainHeader: Bool {
            rows.count > 1 || rows.contains { $0.permissionTitle != nil }
        }

        var accessibilityIdentifier: String {
            "WebsitePermissions.Detail.Group.\(domain)"
        }
    }
}
