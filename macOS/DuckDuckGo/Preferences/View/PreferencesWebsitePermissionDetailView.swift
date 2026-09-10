//
//  PreferencesWebsitePermissionDetailView.swift
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
import DesignResourcesKitIcons
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

struct PreferencesWebsitePermissionDetailView: View {
    private enum Constants {
        static let chevronSize: CGFloat = 16
        static let searchWidth: CGFloat = 173
        static let searchHeight: CGFloat = 28
        static let searchCornerRadius: CGFloat = 7
        static let loadingRowHeight: CGFloat = 56
        static let backButtonSize: CGFloat = 32
        static let messageTopPadding: CGFloat = 4
        static let messageBottomPadding: CGFloat = 8
    }

    @ObservedObject var model: WebsitePermissionDetailViewModel
    let onBack: () -> Void

    var body: some View {
        PreferencePane(nil) {
            detailHeader
            websitesSection
        }
        .accessibilityIdentifier("WebsitePermissions.Detail")
        .task {
            model.send(action: .onAppear)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(nsImage: DesignSystemImages.Glyphs.Size24.chevronLeft)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))
                    .frame(width: Constants.backButtonSize, height: Constants.backButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UserText.websitePermissionsBack)
            .accessibilityIdentifier("WebsitePermissions.Detail.Back")

            TextMenuTitle(model.viewState.category.title)
                .accessibilityIdentifier("WebsitePermissions.Detail.Title")
        }
    }

    private var websitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextMenuItemHeader(UserText.websitePermissionsWebsites)
                Spacer()
                searchField
            }

            if model.viewState.isLoading {
                loadingState
            } else if model.viewState.isEmpty {
                emptyState
            } else if model.viewState.hasNoResults {
                noResultsState
            } else {
                PreferencesWebsitePermissionListContainer {
                    siteRows
                }
            }
        }
        .padding(.bottom, 16)
    }

    private var loadingState: some View {
        PreferencesWebsitePermissionListContainer {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: Constants.loadingRowHeight)
        }
        .accessibilityIdentifier("WebsitePermissions.Detail.Loading")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.searchFind)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundColor(Color(designSystemColor: .iconsTertiary))

            TextField(
                UserText.websitePermissionsSearchPlaceholder,
                text: Binding(
                    get: { model.viewState.searchQuery },
                    set: { model.send(action: .setSearchQuery($0)) }
                )
            )
            .textFieldStyle(.plain)

            if !model.viewState.searchQuery.isEmpty {
                Button {
                    model.send(action: .setSearchQuery(""))
                } label: {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.closeSmall)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundColor(Color(designSystemColor: .iconsTertiary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(UserText.websitePermissionsClearSearch)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(width: Constants.searchWidth, height: Constants.searchHeight)
        .background(Color(designSystemColor: .containerFillSecondary))
        .clipShape(RoundedRectangle(cornerRadius: Constants.searchCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Constants.searchCornerRadius, style: .continuous)
                .stroke(Color(designSystemColor: .containerBorderPrimary), lineWidth: 1)
        }
        .accessibilityIdentifier("WebsitePermissions.Detail.Search")
    }

    private var siteRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.viewState.visibleSites.enumerated()), id: \.element.id) { index, row in
                WebsitePermissionSiteRow(
                    domain: row.domain,
                    faviconURL: row.faviconURL,
                    permissionTitle: row.permissionTitle,
                    decision: row.decision,
                    availableDecisions: row.availableDecisions,
                    accessibilityIdentifier: row.accessibilityIdentifier,
                    onDecisionChanged: { model.send(action: .changeDecision(rowID: row.id, decision: $0)) },
                    onRemove: { model.send(action: .remove(rowID: row.id)) }
                )

                if index < model.viewState.visibleSites.count - 1 {
                    WebsitePermissionListSeparator()
                }
            }
        }
    }

    private var emptyState: some View {
        emptyMessage(UserText.websitePermissionsEmpty)
            .accessibilityIdentifier("WebsitePermissions.Detail.Empty")
    }

    private var noResultsState: some View {
        emptyMessage(UserText.websitePermissionsNoResults)
            .accessibilityIdentifier("WebsitePermissions.Detail.NoResults")
    }

    private func emptyMessage(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixMultilineScrollableText()
            .padding(.top, Constants.messageTopPadding)
            .padding(.bottom, Constants.messageBottomPadding)
    }
}
