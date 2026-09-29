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
    private var pendingPrompt: Task<NSApplication.ModalResponse, Never>?

    init(windowProvider: @escaping () -> NSWindow?) {
        self.windowProvider = windowProvider
    }

    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> Bool? {
        let alert = makeAlert(for: webExtension, permissions: permissions, isInstallation: true)
        let privateAccess = NSButton(checkboxWithTitle: UserText.webExtensionAllowFireWindows, target: nil, action: nil)
        privateAccess.state = .off
        privateAccess.toolTip = UserText.webExtensionPrivateAccessExplanation
        if let stack = alert.accessoryView as? NSStackView {
            stack.addArrangedSubview(privateAccess)
            let explanation = NSTextField(wrappingLabelWithString: UserText.webExtensionPrivateAccessExplanation)
            stack.addArrangedSubview(explanation)
        }
        guard await present(alert) == .alertFirstButtonReturn else { return nil }
        return privateAccess.state == .on
    }

    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> Bool {
        let alert = makeAlert(for: context.webExtension, permissions: permissions, isInstallation: false)
        return await present(alert) == .alertFirstButtonReturn
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
        // Several extensions (or several requests from one extension) may prompt concurrently.
        let previous = pendingPrompt
        let task = Task { @MainActor [windowProvider] in
            _ = await previous?.value
            if let window = windowProvider(), window.attachedSheet == nil {
                return await alert.beginSheetModal(for: window)
            }
            return await alert.runModal()
        }
        pendingPrompt = task
        return await task.value
    }

    private func makeAlert(for webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest, isInstallation: Bool) -> NSAlert {
        let alert = NSAlert()
        let iconSize = NSSize(width: 64, height: 64)
        if let icon = webExtension.icon(for: iconSize) ?? webExtension.actionIcon(for: iconSize) {
            alert.icon = icon
        }
        let title = isInstallation ? UserText.webExtensionInstallTitle : UserText.webExtensionPermissionTitle
        alert.messageText = String(format: title, webExtension.displayName ?? UserText.webExtensionUnnamedExtension)
        alert.informativeText = UserText.webExtensionPermissionExplanation
        alert.addButton(withTitle: isInstallation ? UserText.webExtensionInstall : UserText.webExtensionAllow)
        alert.addButton(withTitle: UserText.cancel)
        // Return must not approve a permission request the user hasn't read.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"

        var entries = permissions.permissions.map { "• \(permissionDescription($0.rawValue))" }.uniqued().sorted()
        entries += permissions.matchPatterns.map { "• \(String(format: UserText.webExtensionWebsiteAccess, $0.string))" }.sorted()
        entries += permissions.urls.map { "• \(String(format: UserText.webExtensionWebsiteAccess, $0.host ?? $0.absoluteString))" }.sorted()
        let label = NSTextField(wrappingLabelWithString: entries.isEmpty ? UserText.webExtensionNoPermissions : entries.joined(separator: "\n"))
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

    private func permissionDescription(_ permission: String) -> String {
        switch permission {
        case "tabs": return UserText.webExtensionTabsPermission
        case "activeTab": return UserText.webExtensionActiveTabPermission
        case "clipboardRead": return UserText.webExtensionClipboardReadPermission
        case "clipboardWrite": return UserText.webExtensionClipboardWritePermission
        case "cookies": return UserText.webExtensionCookiesPermission
        case "downloads": return UserText.webExtensionDownloadsPermission
        case "history": return UserText.webExtensionHistoryPermission
        case "webNavigation": return UserText.webExtensionNavigationPermission
        case "storage", "unlimitedStorage": return UserText.webExtensionStoragePermission
        case "nativeMessaging": return UserText.webExtensionNativeMessagingPermission
        default: return String(format: UserText.webExtensionOtherPermission, permission)
        }
    }

}
