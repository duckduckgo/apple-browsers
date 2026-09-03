//
//  WebsitePermissionsView.swift
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
import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import PreferencesUI_macOS
import SwiftUI

struct WebsitePermissionsView: View {
    private enum Constants {
        static let cornerRadius: CGFloat = 12
        static let separatorHeight: CGFloat = 1
        static let rowHeight: CGFloat = 56
        static let rowPadding: CGFloat = 16
        static let iconSize: CGFloat = 16
        static let chevronSize: CGFloat = 12
        static let countSeparatorSize: CGFloat = 3
    }

    @ObservedObject
    var model: WebsitePermissionsViewModel

    var body: some View {
        PreferencePane(UserText.websitePermissions) {
            permissionsSection
        }
    }

    private var permissionsSection: some View {
        PreferencePaneSection(UserText.permissionsSection) {
            VStack(spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    permissionRow(row)

                    if index < model.rows.count - 1 {
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

    private func permissionRow(_ row: WebsitePermissionRow) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: row.category.icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundColor(Color(designSystemColor: .iconsSecondary))

            HStack(spacing: 6) {
                Text(row.category.title)
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

            Image(nsImage: .chevronRight12)
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
        .accessibilityIdentifier(row.category.accessibilityIdentifier)
    }
}

private extension WebsitePermissionCategory {
    var title: String {
        switch self {
        case .notifications:
            return UserText.permissionNotification
        case .location:
            return UserText.permissionGeolocation
        case .camera:
            return UserText.permissionCamera
        case .microphone:
            return UserText.permissionMicrophone
        case .externalApps:
            return UserText.permissionCenterExternalApps
        case .popups:
            return UserText.permissionPopups
        }
    }

    var icon: NSImage {
        switch self {
        case .notifications:
            return DesignSystemImages.Glyphs.Size16.permissionsNotification
        case .location:
            return DesignSystemImages.Glyphs.Size16.permissionsLocation
        case .camera:
            return DesignSystemImages.Glyphs.Size16.permissionCamera
        case .microphone:
            return DesignSystemImages.Glyphs.Size16.permissionMicrophone
        case .externalApps:
            return DesignSystemImages.Glyphs.Size16.openIn
        case .popups:
            return DesignSystemImages.Glyphs.Size16.popupBlocked
        }
    }

    var accessibilityIdentifier: String {
        "WebsitePermissions.\(self)"
    }
}

#if DEBUG
private final class PreviewWebsitePermissionManager: WebsitePermissionManaging {

    private let entries: [WebsitePermissionEntry]

    init(entries: [WebsitePermissionEntry]) {
        self.entries = entries
    }

    var persistedPermissionsPublisher: AnyPublisher<[WebsitePermissionEntry], Never> {
        Just(entries).eraseToAnyPublisher()
    }
}

@MainActor
private func previewModel(entries: [WebsitePermissionEntry] = []) -> WebsitePermissionsViewModel {
    WebsitePermissionsViewModel(permissionManager: PreviewWebsitePermissionManager(entries: entries))
}

private let previewEntries: [WebsitePermissionEntry] = [
    WebsitePermissionEntry(domain: "duckduckgo.com", permissionType: .notification, decision: .allow),
    WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .deny),
    WebsitePermissionEntry(domain: "maps.example.com", permissionType: .geolocation, decision: .allow),
    WebsitePermissionEntry(domain: "meet.example.com", permissionType: .camera, decision: .allow),
    WebsitePermissionEntry(domain: "meet.example.com", permissionType: .microphone, decision: .allow),
    WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow),
    WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .ask),
    WebsitePermissionEntry(domain: "shop.example.com", permissionType: .popups, decision: .deny),
]

#Preview("Website Permissions - Light") {
    WebsitePermissionsView(model: previewModel(entries: previewEntries))
        .frame(width: 544, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .preferredColorScheme(.light)
}

#Preview("Website Permissions - Dark") {
    WebsitePermissionsView(model: previewModel(entries: previewEntries))
        .frame(width: 544, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .preferredColorScheme(.dark)
}

#Preview("Website Permissions - No Saved Permissions") {
    WebsitePermissionsView(model: previewModel())
        .frame(width: 544, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
}
#endif
