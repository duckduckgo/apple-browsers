//
//  PreferencesWebsitePermissionsView.swift
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

import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons
import PreferencesUI_macOS
import SwiftUI

struct PreferencesWebsitePermissionsView: View {
    private enum Constants {
        static let rowHeight: CGFloat = 56
        static let rowPadding: CGFloat = 16
        static let iconSize: CGFloat = 16
        static let chevronSize: CGFloat = 12
        static let countSeparatorSize: CGFloat = 3
        static let faviconSize: CGFloat = 16
        static let removeButtonSize: CGFloat = 16
        static let minimumDropdownWidth: CGFloat = 124
    }

    @ObservedObject
    var model: WebsitePermissionsViewModel
    let onDetailNavigation: () -> Void

    init(model: WebsitePermissionsViewModel, onDetailNavigation: @escaping () -> Void = {}) {
        self.model = model
        self.onDetailNavigation = onDetailNavigation
    }

    var body: some View {
        Group {
            if let detailModel = model.viewState.detailModel {
                PreferencesWebsitePermissionDetailView(model: detailModel) {
                    model.send(action: .closeDetail)
                    onDetailNavigation()
                }
            } else {
                overview
            }
        }
        .task {
            model.send(action: .onAppear)
        }
    }

    private var overview: some View {
        PreferencePane(UserText.websitePermissions) {
            if model.viewState.hasRecents {
                recentsSection
            }
            permissionsSection
        }
    }

    private var recentsSection: some View {
        PreferencePaneSection(UserText.websitePermissionsRecentsSection) {
            PreferencesWebsitePermissionListContainer {
                VStack(spacing: 0) {
                    ForEach(Array(model.viewState.recents.enumerated()), id: \.element.id) { index, row in
                        recentRow(row)

                        if index < model.viewState.recents.count - 1 {
                            WebsitePermissionListSeparator()
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ row: WebsitePermissionsViewState.RecentRow) -> some View {
        PreferencesWebsitePermissionSiteRowView(
            domain: row.domain,
            faviconURL: row.faviconURL,
            permissionType: row.permissionType,
            permissionTitle: row.permissionTitle,
            decision: row.decision,
            availableDecisions: row.availableDecisions,
            accessibilityIdentifier: row.accessibilityIdentifier,
            onDecisionChanged: { model.send(action: .changeRecentDecision(row, $0)) },
            onRemove: { model.send(action: .removeRecent(row)) }
        )
    }

    private var permissionsSection: some View {
        PreferencePaneSection(UserText.permissionsSection) {
            PreferencesWebsitePermissionListContainer {
                VStack(spacing: 0) {
                    ForEach(Array(model.viewState.rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            model.send(action: .openDetail(row.category))
                            onDetailNavigation()
                        } label: {
                            permissionRow(row)
                        }
                        .buttonStyle(.plain)

                        if shouldShowSeparator(afterRowAt: index) {
                            WebsitePermissionListSeparator()
                        }
                    }
                }
            }
        }
    }

    private func shouldShowSeparator(afterRowAt index: Int) -> Bool {
        index < model.viewState.rows.count - 1
    }

    private func permissionRow(_ row: WebsitePermissionsViewState.Row) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: row.icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundColor(Color(designSystemColor: .iconsSecondary))

            HStack(spacing: 6) {
                Text(row.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                if row.count > 0 {
                    Circle()
                        .fill(Color(designSystemColor: .textTertiary))
                        .frame(width: Constants.countSeparatorSize, height: Constants.countSeparatorSize)

                    Text(verbatim: String(row.count))
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textTertiary))
                }
            }

            Spacer()

            Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                .foregroundColor(Color(designSystemColor: .iconsTertiary))
        }
        .padding(Constants.rowPadding)
        .frame(height: Constants.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }
}

#if DEBUG
import PrivacyConfig

@MainActor
private func previewModel(entries: [WebsitePermissionEntry] = []) -> WebsitePermissionsViewModel {
    let permissionManager = PermissionManagerMock()
    permissionManager.setPersistedPermissions(entries)
    return WebsitePermissionsViewModel(permissionManager: permissionManager, featureFlagger: MockFeatureFlagger())
}

private let previewEntries: [WebsitePermissionEntry] = [
    WebsitePermissionEntry(domain: "duckduckgo.com", permissionType: .notification, decision: .allow, lastModified: nil),
    WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .deny, lastModified: Date(timeIntervalSinceNow: -30)),
    WebsitePermissionEntry(domain: "maps.example.com", permissionType: .geolocation, decision: .allow, lastModified: nil),
    WebsitePermissionEntry(domain: "meet.example.com", permissionType: .camera, decision: .allow, lastModified: Date(timeIntervalSinceNow: -60)),
    WebsitePermissionEntry(domain: "meet.example.com", permissionType: .microphone, decision: .allow, lastModified: nil),
    WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow, lastModified: Date()),
    WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .ask, lastModified: nil),
    WebsitePermissionEntry(domain: "shop.example.com", permissionType: .popups, decision: .deny, lastModified: nil),
]

#Preview("Website Permissions - Light") {
    PreferencesWebsitePermissionsView(model: previewModel(entries: previewEntries))
        .frame(width: 544, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .preferredColorScheme(.light)
}

#Preview("Website Permissions - Dark") {
    PreferencesWebsitePermissionsView(model: previewModel(entries: previewEntries))
        .frame(width: 544, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .preferredColorScheme(.dark)
}

#Preview("Website Permissions - No Saved Permissions") {
    PreferencesWebsitePermissionsView(model: previewModel())
        .frame(width: 544, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
}
#endif
