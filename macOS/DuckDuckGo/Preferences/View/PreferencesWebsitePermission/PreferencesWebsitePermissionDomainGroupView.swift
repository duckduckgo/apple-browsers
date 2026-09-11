//
//  PreferencesWebsitePermissionDomainGroupView.swift
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
import DesignResourcesKit
import SwiftUI

/// A domain and the permissions stored for it.
///
/// External App permissions are keyed by scheme, so a domain can hold several of them: those are listed as
/// labelled rows beneath the domain name. Every other category stores a single permission per domain, which
/// is shown inline with the domain.
struct PreferencesWebsitePermissionDomainGroupView: View {
    private enum Constants {
        static let padding: CGFloat = 16
        static let faviconSize: CGFloat = 16
        static let faviconSpacing: CGFloat = 10
        static let headerSpacing: CGFloat = 12
        static let permissionSpacing: CGFloat = 4
        static let permissionHeight: CGFloat = 28
        static let permissionLabelSpacing: CGFloat = 10
    }

    let group: WebsitePermissionDetailViewState.SiteGroup
    let onDecisionChanged: (WebsitePermissionDetailViewState.SiteRow.ID, PersistedPermissionDecision) -> Void
    let onRemove: (WebsitePermissionDetailViewState.SiteRow.ID) -> Void

    var body: some View {
        if group.showsDomainHeader {
            labelledPermissions
        } else if let row = group.rows.first {
            PreferencesWebsitePermissionSiteRowView(
                domain: row.domain,
                faviconURL: row.faviconURL,
                permissionTitle: row.permissionTitle,
                decision: row.decision,
                availableDecisions: row.availableDecisions,
                accessibilityIdentifier: row.accessibilityIdentifier,
                onDecisionChanged: { onDecisionChanged(row.id, $0) },
                onRemove: { onRemove(row.id) }
            )
        }
    }

    private var labelledPermissions: some View {
        VStack(alignment: .leading, spacing: Constants.headerSpacing) {
            domainHeader

            VStack(spacing: Constants.permissionSpacing) {
                ForEach(group.rows) { row in
                    permissionRow(row)
                }
            }
            // Lines the permissions up with the domain name rather than with its favicon.
            .padding(.leading, Constants.faviconSize + Constants.faviconSpacing)
        }
        .padding(Constants.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(group.accessibilityIdentifier)
    }

    private var domainHeader: some View {
        HStack(spacing: Constants.faviconSpacing) {
            FaviconView(url: group.faviconURL, size: Constants.faviconSize)

            Text(group.domain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func permissionRow(_ row: WebsitePermissionDetailViewState.SiteRow) -> some View {
        HStack(spacing: Constants.permissionLabelSpacing) {
            permissionLabel(row)

            Spacer(minLength: Constants.permissionLabelSpacing)

            PreferencesWebsitePermissionDecisionControlsView(
                decision: row.decision,
                availableDecisions: row.availableDecisions,
                accessibilityIdentifier: row.accessibilityIdentifier,
                domain: row.domain,
                onDecisionChanged: { onDecisionChanged(row.id, $0) },
                onRemove: { onRemove(row.id) }
            )
        }
        .frame(height: Constants.permissionHeight)
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }

    @ViewBuilder
    private func permissionLabel(_ row: WebsitePermissionDetailViewState.SiteRow) -> some View {
        let label = Text(row.subRowTitle)
            .font(.system(size: 13))
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .lineLimit(1)
            .truncationMode(.middle)

        if case .externalScheme(let scheme) = row.permissionType {
            label.help(Text(verbatim: "\(scheme)://"))
        } else {
            label
        }
    }
}
