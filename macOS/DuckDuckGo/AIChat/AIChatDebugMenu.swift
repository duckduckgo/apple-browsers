//
//  AIChatDebugMenu.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AIChat
import AppKit
import Persistence

final class AIChatDebugMenu: NSMenu {
    private var storage = DefaultAIChatPreferencesStorage()
    private let customURLLabelMenuItem = NSMenuItem(title: "")
    private let debugStorage: any KeyedStoring<AIChatDebugURLSettings>

    init(debugStorage: (any KeyedStoring<AIChatDebugURLSettings>)? = nil) {
        self.debugStorage = if let debugStorage { debugStorage } else { UserDefaults.standard.keyedStoring() }
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Web Communication") {
                NSMenuItem(title: "Set Custom URL", action: #selector(setCustomURL))
                    .targetting(self)
                NSMenuItem(title: "Reset Custom URL", action: #selector(resetCustomURL))
                    .targetting(self)
                customURLLabelMenuItem
            }

            NSMenuItem.separator()

            NSMenuItem(title: "Toggle Popover") {
                NSMenuItem(title: "Show Toggle Popover", action: #selector(showTogglePopover))
                    .targetting(self)
                NSMenuItem(title: "Reset Toggle Popover Seen Flag", action: #selector(resetTogglePopoverSeenFlag))
                    .targetting(self)
            }

            NSMenuItem.separator()

            NSMenuItem(title: "Reset Toggle Animation", action: #selector(resetToggleAnimation))
                .targetting(self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateWebUIMenuItemsState()
    }

    @objc func setCustomURL() {
        showCustomURLAlert { [weak self] value in

            guard let value = value, let url = URL(string: value), url.isValid else { return false }

            self?.debugStorage.customURL = value
            return true
        }
    }

    @objc func resetCustomURL() {
        debugStorage.resetCustomURL()
        updateWebUIMenuItemsState()
    }

    @objc func resetToggleAnimation() {
        UserDefaults.standard.hasInteractedWithSearchDuckAIToggle = false
    }

    @MainActor @objc func showTogglePopover() {
        resetTogglePopoverSeenFlag()

        guard let mainWindowController = NSApp.delegateTyped.windowControllersManager.lastKeyMainWindowController,
              let addressBarButtonsVC = mainWindowController.mainViewController.navigationBarViewController.addressBarViewController?.addressBarButtonsViewController,
              let toggleControl = addressBarButtonsVC.searchModeToggleControl else {
            return
        }
        addressBarButtonsVC.aiChatTogglePopoverCoordinator?.showPopoverForDebug(relativeTo: toggleControl)
    }

    @MainActor @objc func resetTogglePopoverSeenFlag() {
        AIChatTogglePopoverCoordinator(windowControllersManager: NSApp.delegateTyped.windowControllersManager).clearPopoverSeenFlag()
        storage.userDidSeeToggleOnboarding = false
    }

    private func updateWebUIMenuItemsState() {
        customURLLabelMenuItem.title = "Custom URL: [\(debugStorage.customURL ?? "")]"
    }

    private func showCustomURLAlert(callback: @escaping (String?) -> Bool) {
        let alert = NSAlert()
        alert.messageText = "Enter URL"
        alert.addButton(withTitle: "Accept")
        alert.addButton(withTitle: "Cancel")

        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = inputTextField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if !callback(inputTextField.stringValue) {
                let invalidAlert = NSAlert()
                invalidAlert.messageText = "Invalid URL"
                invalidAlert.informativeText = "Please enter a valid URL."
                invalidAlert.addButton(withTitle: "OK")
                invalidAlert.runModal()
            }
        } else {
            _ = callback(nil)
        }
    }
}
