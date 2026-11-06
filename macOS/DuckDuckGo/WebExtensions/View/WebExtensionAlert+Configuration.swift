//
//  WebExtensionAlert+Configuration.swift
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
import WebKit

@available(macOS 15.4, *)
extension WebExtensionAlert.Configuration {

    private static let iconSize = NSSize(width: 64, height: 64)

    static func installation(of webExtension: WKWebExtension, permissionEntries entries: [String]) -> Self {
        Self(
            icon: webExtension.icon(for: iconSize) ?? webExtension.actionIcon(for: iconSize),
            title: String(format: UserText.webExtensionInstallTitle, webExtension.displayName ?? UserText.webExtensionUnnamedExtension),
            message: entries.isEmpty ? UserText.webExtensionNoPermissions : UserText.webExtensionPermissionExplanation,
            details: entries,
            checkbox: UserText.webExtensionAllowFireWindows,
            checkboxToolTip: UserText.webExtensionPrivateAccessExplanation,
            confirmTitle: UserText.webExtensionInstall,
            cancelTitle: UserText.cancel)
    }

    static func removal(of webExtension: WKWebExtension?, name: String) -> Self {
        Self(
            icon: webExtension?.icon(for: iconSize) ?? webExtension?.actionIcon(for: iconSize),
            title: String(format: UserText.chromeWebStoreRemoveTitle, name),
            confirmTitle: UserText.webExtensionRemoveButton,
            cancelTitle: UserText.cancel)
    }
}
