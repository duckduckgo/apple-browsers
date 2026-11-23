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
            icon: webExtension.displayIcon(for: iconSize).map(Icon.extensionIcon),
            title: String(format: UserText.webExtensionInstallTitle, webExtension.displayName ?? UserText.webExtensionUnnamedExtension),
            message: entries.isEmpty ? UserText.webExtensionNoPermissions : UserText.webExtensionPermissionExplanation,
            details: entries,
            checkbox: .option(UserText.webExtensionAllowFireWindows, toolTip: UserText.webExtensionPrivateAccessExplanation),
            confirmTitle: UserText.webExtensionInstall,
            leadingButton: .cancel(UserText.cancel))
    }

    static func removal(of webExtension: WKWebExtension?, name: String) -> Self {
        Self(
            icon: webExtension?.displayIcon(for: iconSize).map(Icon.extensionIcon),
            title: String(format: UserText.chromeWebStoreRemoveTitle, name),
            confirmTitle: UserText.webExtensionRemoveButton,
            leadingButton: .cancel(UserText.cancel))
    }

    static func nativeMessagingUnavailable(for webExtension: WKWebExtension) -> Self {
        let name = webExtension.displayName ?? UserText.webExtensionUnnamedExtension
        return Self(
            icon: .illustration(NSImage(resource: .duckDuckGoResponseAlertFeature96)),
            title: UserText.webExtensionNativeMessagingUnavailableTitle(name),
            message: UserText.webExtensionNativeMessagingUnavailableMessage + "\n\n" + UserText.webExtensionNativeMessagingUnavailableMessageDownload,
            messageColor: .textPrimary,
            checkbox: .suppression(UserText.webExtensionNativeMessagingUnavailableDontShowAgain(name)),
            confirmTitle: UserText.ok,
            leadingButton: .secondary(UserText.learnMore))
    }
}
