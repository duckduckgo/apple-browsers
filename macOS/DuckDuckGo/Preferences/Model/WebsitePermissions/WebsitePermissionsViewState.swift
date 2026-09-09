//
//  WebsitePermissionsViewState.swift
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
import Common
import DesignResourcesKitIcons

struct WebsitePermissionsViewState: Equatable {
    var recents: [RecentRow] = []
    var rows: [Row] = []

    var hasRecents: Bool {
        !recents.isEmpty
    }
}

extension WebsitePermissionsViewState {
    struct Row: Identifiable, Equatable {
        let category: WebsitePermissionCategory
        let count: Int

        var id: WebsitePermissionCategory { category }

        var title: String {
            switch category {
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
            switch category {
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
            "WebsitePermissions.\(category)"
        }
    }
}

extension WebsitePermissionsViewState {
    /// A single recently changed website permission. Display strings and the dropdown's options are
    /// resolved when the row is built, since `PermissionType.localizedDescription` consults
    /// `NSWorkspace` to name the handling app for external schemes.
    struct RecentRow: Identifiable, Equatable {
        let domain: String
        let permissionType: PermissionType
        let decision: PersistedPermissionDecision
        let permissionTitle: String
        let availableDecisions: [PersistedPermissionDecision]

        var id: String {
            "\(domain)|\(permissionType.rawValue)"
        }

        var faviconURL: URL? {
            URL(string: "\(URL.NavigationalScheme.https.separated())\(domain)")
        }

        var accessibilityIdentifier: String {
            "WebsitePermissions.Recent.\(id)"
        }
    }
}
