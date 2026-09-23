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

            if model.viewState.isEmpty {
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
        let groups = model.viewState.visibleGroups

        return VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                PreferencesWebsitePermissionDomainGroupView(
                    group: group,
                    onDecisionChanged: { model.send(action: .changeDecision(rowID: $0, decision: $1)) },
                    onRemove: { model.send(action: .remove(rowID: $0)) }
                )

                if index < groups.count - 1 {
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
