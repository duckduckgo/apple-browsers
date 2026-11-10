//
//  WebExtensionPermissionPrompt.swift
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
import WebExtensions
import WebKit

@available(macOS 15.4, *)
@MainActor
final class WebExtensionPermissionPrompt: WebExtensionPermissionPrompting {
    private let windowProvider: () -> NSWindow?
    private let themeManager: ThemeManager
    private var pendingPrompt: Task<Void, Never>?

    init(windowProvider: @escaping () -> NSWindow?, themeManager: ThemeManager) {
        self.windowProvider = windowProvider
        self.themeManager = themeManager
    }

    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        let configuration = WebExtensionAlert.Configuration.installation(of: webExtension, permissionEntries: permissionMessages(for: permissions))

        let response = await enqueue { [windowProvider, themeManager] in
            guard let window = windowProvider() else { return WebExtensionAlert.Response.cancelled }
            return await withCheckedContinuation { continuation in
                WebExtensionAlert(configuration: configuration, themeManager: themeManager, onResponse: { continuation.resume(returning: $0) })
                    .show(in: window)
            }
        }
        guard case .confirmed(let isChecked) = response else { return .denied }
        return .granted(privateDataAccess: isChecked)
    }

    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        // Nothing to warn the user about, so nothing to ask: the alert would list no permissions above an Allow button.
        if permissionMessages(for: permissions).isEmpty {
            return .granted
        }

        let alert = makeAlert(for: context.webExtension, permissions: permissions)
        return await present(alert) == .alertFirstButtonReturn ? .granted : .denied
    }

    // Several extensions (or several requests from one extension) may prompt concurrently.
    private func enqueue<T>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = pendingPrompt
        let task = Task { @MainActor in
            _ = await previous?.value
            return await operation()
        }
        pendingPrompt = Task { _ = await task.value }
        return await task.value
    }

    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let accessory = alert.accessoryView {
            accessory.layoutSubtreeIfNeeded()
            accessory.setFrameSize(accessory.fittingSize)
        }
        alert.layout()
        if let stack = alert.accessoryView as? NSStackView,
           let scrollView = stack.arrangedSubviews.first as? NSScrollView,
           let document = scrollView.documentView {
            let top = document.isFlipped ? 0 : max(0, document.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        return await enqueue { [windowProvider] in
            if let window = windowProvider(), window.attachedSheet == nil {
                return await alert.beginSheetModal(for: window)
            }
            return await alert.runModal()
        }
    }

    private func makeAlert(for webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) -> NSAlert {
        let alert = NSAlert()
        let iconSize = NSSize(width: 64, height: 64)
        if let icon = webExtension.icon(for: iconSize) ?? webExtension.actionIcon(for: iconSize) {
            alert.icon = icon
        }
        alert.messageText = String(format: UserText.webExtensionPermissionTitle, webExtension.displayName ?? UserText.webExtensionUnnamedExtension)
        alert.informativeText = UserText.webExtensionPermissionExplanation
        alert.addButton(withTitle: UserText.webExtensionAllow)
        alert.addButton(withTitle: UserText.cancel)
        // Return must not approve a permission request the user hasn't read.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"

        let entries = permissionMessages(for: permissions)
        let label = NSTextField(wrappingLabelWithString: entries.isEmpty ? UserText.webExtensionNoPermissions : entries.map { "• \($0)" }.joined(separator: "\n"))
        label.isSelectable = true
        label.frame.size.width = 360
        label.frame.size.height = label.sizeThatFits(NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude)).height

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = label
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 380),
            scrollView.heightAnchor.constraint(equalToConstant: min(max(label.frame.height, 40), 240))
        ])

        let stack = NSStackView(views: [scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.frame.size.width = 380
        stack.widthAnchor.constraint(equalToConstant: 380).isActive = true
        alert.accessoryView = stack
        return alert
    }

}

// MARK: - Permission messages

@available(macOS 15.4, *)
private extension WebExtensionPermissionPrompt {

    /// The lines the prompt lists for a request: website access first, then one message per permission group.
    func permissionMessages(for request: WebExtensionPermissionRequest) -> [String] {
        let siteMessages = [websiteAccessMessage(for: request)]
            .compactMap { $0 }

        let apiMessages = apiPermissionMessages(for: request)
        let appMessages = appPermissionMessages(for: request)

        return siteMessages + apiMessages + appMessages
    }

    /// Website access as one line: all websites, up to three named hosts, or "a number of websites".
    private func websiteAccessMessage(for request: WebExtensionPermissionRequest) -> String? {
        if request.hasAllWebsitesAccess {
            return UserText.webExtensionAllWebsitesAccess
        }

        let hosts = Set(request.matchPatterns.compactMap(\.host) + request.urls.compactMap(\.host)).sorted()
        switch hosts.count {
        case 0:
            return nil
        case 1...3:
            return String(format: UserText.webExtensionWebsiteAccess, ListFormatter.localizedString(byJoining: hosts))
        default:
            return UserText.webExtensionManyWebsitesAccess
        }
    }

    /// One message per permission group, in `permissionsByMessage` order. Permissions without a message aren't listed.
    private func apiPermissionMessages(for request: WebExtensionPermissionRequest) -> [String] {
        var permissions = request.permissionsBeyondWebsiteAccess

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
        return messages
    }

    private func appPermissionMessages(for request: WebExtensionPermissionRequest) -> [String] {
        request.appPermissions.contains(.privacy) ? [UserText.webExtensionPrivacyPermission] : []
    }

    /// A message can repeat, for permissions that each warrant it on their own.
    private var permissionsByMessage: [(message: String, permissions: Set<WebExtensionManifestPermission>)] {
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
            (UserText.webExtensionTabGroupsPermission, [.tabGroups])
        ]
    }

}

@available(macOS 15.4, *)
private extension WebExtensionPermissionRequest {

    var hasAllWebsitesAccess: Bool {
        matchPatterns.contains { $0.matchesAllHosts || $0.matchesAllURLs }
    }

    /// Access to all websites already implies some permissions, so they aren't listed beside it.
    var permissionsBeyondWebsiteAccess: Set<WebExtensionManifestPermission> {
        let permissions = manifestPermissions.union(permissions.compactMap { WebExtensionManifestPermission(rawValue: $0.rawValue) })
        return hasAllWebsitesAccess
            ? permissions.subtracting([.tabs, .webNavigation, .declarativeNetRequest, .declarativeNetRequestFeedback, .topSites, .favicon])
            : permissions
    }
}
