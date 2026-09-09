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
        static let cornerRadius: CGFloat = 12
        static let separatorHeight: CGFloat = 1
        static let rowHeight: CGFloat = 56
        static let rowPadding: CGFloat = 16
        static let iconSize: CGFloat = 16
        static let chevronSize: CGFloat = 12
        static let countSeparatorSize: CGFloat = 3
        static let faviconSize: CGFloat = 16
        static let removeButtonSize: CGFloat = 16
        static let dropdownWidth: CGFloat = 124
    }

    @ObservedObject
    var model: WebsitePermissionsViewModel

    var body: some View {
        PreferencePane(UserText.websitePermissions) {
            if model.viewState.hasRecents {
                recentsSection
            }
            permissionsSection
        }
        .task {
            model.send(action: .onAppear)
        }
    }

    private var recentsSection: some View {
        PreferencePaneSection(UserText.websitePermissionsRecentsSection) {
            VStack(spacing: 0) {
                ForEach(Array(model.viewState.recents.enumerated()), id: \.element.id) { index, row in
                    recentRow(row)

                    if index < model.viewState.recents.count - 1 {
                        Rectangle()
                            .fill(Color(designSystemColor: .containerBorderPrimary))
                            .frame(height: Constants.separatorHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(designSystemColor: .containerFillSecondary))
            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius, style: .continuous))
        }
    }

    private func recentRow(_ row: WebsitePermissionsViewState.RecentRow) -> some View {
        HStack(spacing: 10) {
            FaviconView(url: row.faviconURL, size: Constants.faviconSize)

            Text(row.domain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 10)

            Text(row.permissionTitle)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .lineLimit(1)

            Picker(selection: Binding(
                get: { row.decision },
                set: { model.send(action: .changeRecentDecision(row, $0)) }),
                   label: EmptyView()) {
                ForEach(row.availableDecisions, id: \.self) { decision in
                    Text(decision.websitePermissionsLabel).tag(decision)
                }
            }
            .labelsHidden()
            .frame(width: Constants.dropdownWidth)
            .accessibilityIdentifier("\(row.accessibilityIdentifier).Decision")

            Button {
                model.send(action: .removeRecent(row))
            } label: {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.closeSmall)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Constants.removeButtonSize, height: Constants.removeButtonSize)
                    .foregroundColor(Color(designSystemColor: .iconsTertiary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UserText.websitePermissionsRemovePermission)
            .accessibilityIdentifier("\(row.accessibilityIdentifier).Remove")
        }
        .padding(Constants.rowPadding)
        .frame(height: Constants.rowHeight)
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }

    private var permissionsSection: some View {
        PreferencePaneSection(UserText.permissionsSection) {
            VStack(spacing: 0) {
                ForEach(Array(model.viewState.rows.enumerated()), id: \.element.id) { index, row in
                    permissionRow(row)

                    if shouldShowSeparator(afterRowAt: index) {
                        Rectangle()
                            .fill(Color(designSystemColor: .containerBorderPrimary))
                            .frame(height: Constants.separatorHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(designSystemColor: .containerFillSecondary))
            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius, style: .continuous))
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
