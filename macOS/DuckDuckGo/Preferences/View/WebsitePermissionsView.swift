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

struct WebsitePermissionsView: View {

    @ObservedObject var model: WebsitePermissionsViewModel

    var body: some View {
        PreferencePane(UserText.websitePermissions) {
            PreferencePaneSection(UserText.permissionsSection) {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        WebsitePermissionRowView(row: row)

                        if index < model.rows.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color(designSystemColor: .containerFillSecondary))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct WebsitePermissionRowView: View {

    let row: WebsitePermissionRow

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: row.category.icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(Color(designSystemColor: .iconsSecondary))

            HStack(spacing: 6) {
                Text(row.category.title)
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                if row.count > 0 {
                    Text(verbatim: "•")
                        .foregroundColor(Color(designSystemColor: .textTertiary))
                    Text(verbatim: String(row.count))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
            }

            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: 56)
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
