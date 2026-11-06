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
        let configuration = WebExtensionAlert.Configuration.installation(of: webExtension, permissionEntries: permissionEntries(for: permissions))

        let response = await enqueue { [windowProvider, themeManager] in
            guard let window = windowProvider() else { return WebExtensionAlert.Response.cancelled }
            return await withCheckedContinuation { continuation in
                WebExtensionAlert(configuration: configuration, themeManager: themeManager, onResponse: continuation.resume(returning:))
                    .show(in: window)
            }
        }
        guard case .confirmed(let isChecked) = response else { return .denied }
        return .granted(privateDataAccess: isChecked)
    }

    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
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

        let entries = permissionEntries(for: permissions)
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

    private func permissionEntries(for permissions: WebExtensionPermissionRequest) -> [String] {
        var entries = [String]()
        if let websiteEntry = websiteAccessEntry(for: permissions) {
            entries.append(websiteEntry)
        }

        if permissions.matchPatterns.contains(where: matchesLocalFiles) || permissions.urls.contains(where: \.isFileURL) {
            entries.append(UserText.webExtensionLocalFilesAccess)
        }

        let descriptions = Set((permissions.permissions.map(\.rawValue) + permissions.appPermissions.map(\.rawValue)).map { permissionDescription($0) })
        entries.append(contentsOf: descriptions.sorted())

        return entries
    }

    /// Groups website access like Chrome: all websites, up to three named sites, or "a number of websites".
    private func websiteAccessEntry(for permissions: WebExtensionPermissionRequest) -> String? {
        let patterns = permissions.matchPatterns.filter { !matchesLocalFiles($0) }
        let urls = permissions.urls.filter { !$0.isFileURL }
        if patterns.contains(where: { $0.matchesAllHosts || $0.matchesAllURLs }) {
            return UserText.webExtensionAllWebsitesAccess
        }

        // Hostless entries fall back to their full text, so every requested origin is still disclosed.
        let sites = Set(patterns.map { $0.host ?? $0.string } + urls.map { $0.host ?? $0.absoluteString }).sorted()
        switch sites.count {
        case 0:
            return nil
        case 1...3:
            return String(format: UserText.webExtensionWebsiteAccess, sites.joined(separator: ", "))
        default:
            return UserText.webExtensionManyWebsitesAccess
        }
    }

    /// True for every `file:` pattern whatever its path; `<all_urls>` doesn't match file URLs in WebKit.
    private func matchesLocalFiles(_ pattern: WKWebExtension.MatchPattern) -> Bool {
        pattern.matches(URL(fileURLWithPath: "/"), options: .ignorePaths)
    }

    private func permissionDescription(_ permission: String) -> String {
        switch permission {
        case "tabs", "webNavigation", "history": return UserText.webExtensionHistoryPermission
        case "activeTab": return UserText.webExtensionActiveTabPermission
        case "clipboardRead", "clipboardWrite": return UserText.webExtensionClipboardPermission
        case "cookies": return UserText.webExtensionCookiesPermission
        case "downloads": return UserText.webExtensionDownloadsPermission
        case "storage", "unlimitedStorage": return UserText.webExtensionStoragePermission
        case "nativeMessaging": return UserText.webExtensionNativeMessagingPermission
        case "privacy": return UserText.webExtensionPrivacyPermission
        default: return String(format: UserText.webExtensionOtherPermission, permission)
        }
    }

}
