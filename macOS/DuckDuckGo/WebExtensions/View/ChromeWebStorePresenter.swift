//
//  ChromeWebStorePresenter.swift
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

@MainActor
final class ChromeWebStorePresenter: NSObject, ChromeWebStorePresenting {
    private let windowProvider: () -> NSWindow?
    private var progressPanel: NSPanel?
    private var cancelDownload: (() -> Void)?

    init(windowProvider: @escaping () -> NSWindow?) {
        self.windowProvider = windowProvider
    }

    func showDownloadProgress(cancel: @escaping () -> Void) {
        cancelDownload = cancel
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 130),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = UserText.chromeWebStoreDownloadTitle
        let label = NSTextField(labelWithString: UserText.chromeWebStoreDownloadMessage)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let cancelButton = NSButton(title: UserText.cancel, target: self, action: #selector(cancelRequested))
        cancelButton.keyEquivalent = "\u{1b}" // Esc
        let stack = NSStackView(views: [label, spinner, cancelButton])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = panel.contentView {
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
        progressPanel = panel
        if let window = windowProvider(), window.attachedSheet == nil {
            window.beginSheet(panel)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func dismissDownloadProgress() {
        if let panel = progressPanel {
            panel.sheetParent?.endSheet(panel)
            panel.orderOut(nil)
        }
        progressPanel = nil
        cancelDownload = nil
    }

    func confirmRemoval(name: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(format: UserText.chromeWebStoreRemoveTitle, name)
        alert.informativeText = UserText.chromeWebStoreRemoveMessage
        alert.addButton(withTitle: UserText.chromeWebStoreRemoveButton)
        alert.addButton(withTitle: UserText.cancel)
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        return await present(alert) == .alertFirstButtonReturn
    }

    func showError(_ error: Error) async {
        let alert = NSAlert()
        alert.messageText = UserText.chromeWebStoreErrorTitle
        switch error {
        case ChromeWebStoreError.unsupportedManifest:
            alert.informativeText = UserText.chromeWebStoreUnsupportedMessage
        case ChromeWebStoreError.invalidPackage, ChromeWebStoreError.invalidSignature:
            alert.informativeText = UserText.chromeWebStoreInvalidPackageMessage
        default:
            alert.informativeText = UserText.chromeWebStoreErrorMessage
        }
        alert.addButton(withTitle: UserText.ok)
        _ = await present(alert)
    }

    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = windowProvider(), window.attachedSheet == nil {
            return await alert.beginSheetModal(for: window)
        }
        return await alert.runModal()
    }

    @objc private func cancelRequested() {
        cancelDownload?()
    }
}
