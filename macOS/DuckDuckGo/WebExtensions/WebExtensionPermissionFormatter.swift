//
//  WebExtensionPermissionFormatter.swift
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

import Foundation
import WebExtensions
import WebKit

/// Turns extension permissions into the lines users see, mirroring the warnings CWS extensions get.
@available(macOS 15.4, *)
enum WebExtensionPermissionFormatter {

    /// Returns the lines a permission prompt lists for `request`: website access first, then one per permission group.
    static func messages(for request: WebExtensionPermissionRequest) -> [String] {
        messages(permissionNames: request.permissionNames, matchPatterns: request.matchPatterns, urls: request.urls)
    }

    /// Returns the same lines for what was saved at installation: permission names such as `"tabs"`
    /// and website patterns such as `"<all_urls>"`.
    static func messages(forPermissionNames names: [String], matchPatterns: [String]) -> [String] {
        messages(permissionNames: names, matchPatterns: Set(matchPatterns.compactMap { try? WKWebExtension.MatchPattern(string: $0) }), urls: [])
    }

}

// MARK: - Private

@available(macOS 15.4, *)
private extension WebExtensionPermissionFormatter {

    static func messages(permissionNames: [String], matchPatterns: Set<WKWebExtension.MatchPattern>, urls: Set<URL>) -> [String] {
        let hasAllWebsitesAccess = matchPatterns.contains { $0.matchesAllHosts || $0.matchesAllURLs }
        var permissions = Set(permissionNames.compactMap(WebExtensionManifestPermission.init(rawValue:)))

        // As for CWS extensions, access to all websites covers these, so they aren't listed beside it.
        if hasAllWebsitesAccess {
            permissions.subtract([.tabs, .webNavigation, .declarativeNetRequest, .declarativeNetRequestFeedback, .topSites, .favicon])
        }

        // As for CWS extensions, history access covers top sites and favicons, and changing history covers reading it.
        if permissions.isDisjoint(with: [.history, .tabs, .webNavigation, .declarativeNetRequestFeedback]) == false {
            permissions.subtract([.topSites, .favicon])
        }
        if permissions.contains(.history) {
            permissions.subtract([.tabs, .webNavigation, .declarativeNetRequestFeedback])
        }

        // As for CWS extensions, a message needs all its permissions, appears once, and claims them from later messages.
        var messages: [String] = []
        for (message, required) in permissionsByMessage where required.isSubset(of: permissions) && !messages.contains(message) {
            permissions.subtract(required)
            messages.append(message)
        }
        let hosts = Set(matchPatterns.compactMap(\.host) + urls.compactMap(\.host)).sorted()
        return [websiteAccessMessage(hasAllWebsitesAccess: hasAllWebsitesAccess, hosts: hosts)].compactMap { $0 } + messages
    }

    /// Website access as one line: all websites, up to three named hosts, or "a number of websites".
    static func websiteAccessMessage(hasAllWebsitesAccess: Bool, hosts: [String]) -> String? {
        if hasAllWebsitesAccess {
            return UserText.webExtensionAllWebsitesAccess
        }

        switch hosts.count {
        case 0:
            return nil
        case 1...3:
            return String(format: UserText.webExtensionWebsiteAccess, ListFormatter.localizedString(byJoining: hosts))
        default:
            return UserText.webExtensionManyWebsitesAccess
        }
    }

    /// A message can repeat, for permissions that each warrant it on their own.
    static var permissionsByMessage: [(message: String, permissions: Set<WebExtensionManifestPermission>)] {
        [
            (UserText.webExtensionDebuggerPermission, [.debugger]),
            (UserText.webExtensionGeolocationPermission, [.geolocation]),
            (UserText.webExtensionHistoryWritePermission, [.history]),
            (UserText.webExtensionHistoryPermission, [.tabs]),
            (UserText.webExtensionHistoryPermission, [.webNavigation]),
            (UserText.webExtensionHistoryPermission, [.declarativeNetRequestFeedback]),
            (UserText.webExtensionFaviconPermission, [.favicon]),
            (UserText.webExtensionTopSitesPermission, [.topSites]),
            (UserText.webExtensionDeclarativeNetRequestPermission, [.declarativeNetRequest]),
            (UserText.webExtensionNotificationsPermission, [.notifications]),
            (UserText.webExtensionBookmarksPermission, [.bookmarks]),
            (UserText.webExtensionReadingListPermission, [.readingList]),
            (UserText.webExtensionClipboardReadWritePermission, [.clipboardRead, .clipboardWrite]),
            (UserText.webExtensionClipboardReadPermission, [.clipboardRead]),
            (UserText.webExtensionClipboardPermission, [.clipboardWrite]),
            (UserText.webExtensionDesktopCapturePermission, [.desktopCapture]),
            (UserText.webExtensionDownloadsPermission, [.downloads]),
            (UserText.webExtensionDownloadsOpenPermission, [.downloadsOpen]),
            (UserText.webExtensionContentSettingsPermission, [.contentSettings]),
            (UserText.webExtensionManagementPermission, [.management]),
            (UserText.webExtensionNativeMessagingPermission, [.nativeMessaging]),
            (UserText.webExtensionPrivacyPermission, [.privacy]),
            (UserText.webExtensionTabGroupsPermission, [.tabGroups])
        ]
    }

}

@available(macOS 15.4, *)
private extension WebExtensionPermissionRequest {

    /// Every permission in the request by manifest name, whether WebKit, the manifest or the app provides it.
    var permissionNames: [String] {
        permissions.map(\.rawValue) + manifestPermissions.map(\.rawValue) + appPermissions.map(\.rawValue)
    }
}
