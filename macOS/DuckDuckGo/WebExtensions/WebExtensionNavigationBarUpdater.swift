//
//  WebExtensionNavigationBarUpdater.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import WebKit

@available(macOS 15.4, *)
@MainActor
final class WebExtensionNavigationBarUpdater {

    private let getContainer: @MainActor () -> NSStackView?
    private var buttons = Set<MouseOverButton>()
    private let webExtensionManager: WebExtensionManaging

    init(webExtensionManager: WebExtensionManaging, container getContainer: @escaping @autoclosure @MainActor () -> NSStackView?) {
        self.getContainer = getContainer
        self.webExtensionManager = webExtensionManager
    }

    /// Starts updating in the background.
    ///
    func startUpdating() async {
        Task {
            await runUpdateLoop()
        }
    }

    /// Runs the update loop.
    ///
    /// This won't return until updates end, so be very mindful of where this is called.
    ///
    func runUpdateLoop() async {
        // We run this once initially to make sure we're up to date
        if let container = getContainer() {
            updateLoadedExtensions(in: container)
        } else {
            return
        }

        for await _ in webExtensionManager.extensionUpdates {
            guard let container = getContainer() else { return }
            updateLoadedExtensions(in: container)
        }
    }

    private func updateLoadedExtensions(in container: NSStackView) {
        let loadedExtensions = webExtensionManager.loadedExtensions
        removeButtons(forExtensionsRemovedFrom: loadedExtensions)
        addButtons(to: container, forExtensionsAddedTo: loadedExtensions)

        container.needsDisplay = true
    }

    private func removeButtons(forExtensionsRemovedFrom loadedExtensions: Set<WKWebExtensionContext>) {
        for button in buttons {
            guard let identifier = button.identifier?.rawValue,
                  !loadedExtensions.contains(where: { $0.uniqueIdentifier == identifier }) else {

                continue
            }

            buttons.remove(button)
            button.removeFromSuperview()
        }
    }

    private func addButtons(to container: NSStackView, forExtensionsAddedTo loadedExtensions: Set<WKWebExtensionContext>) {
        let buttonIdentifiers = buttons.compactMap {
            $0.identifier?.rawValue
        }

        for (index, context) in loadedExtensions.enumerated() where !buttonIdentifiers.contains(context.uniqueIdentifier) {

            let newButton = webExtensionManager.toolbarButton(for: context)

            container.insertArrangedSubview(newButton, at: index)
            buttons.insert(newButton)
        }
    }
}
