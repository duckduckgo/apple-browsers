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
final class ChromeWebStorePresenter: ChromeWebStorePresenting {
    private let windowProvider: () -> NSWindow?

    init(windowProvider: @escaping () -> NSWindow?) {
        self.windowProvider = windowProvider
    }

    func confirmRemoval(name: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(format: UserText.chromeWebStoreRemoveTitle, name)
        alert.informativeText = UserText.chromeWebStoreRemoveMessage
        alert.addButton(withTitle: UserText.cancel)
        alert.addButton(withTitle: UserText.chromeWebStoreRemoveButton)
        alert.buttons[0].keyEquivalent = "\u{1b}"
        alert.buttons[1].keyEquivalent = "\r"
        return await present(alert) == .alertSecondButtonReturn
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
}
