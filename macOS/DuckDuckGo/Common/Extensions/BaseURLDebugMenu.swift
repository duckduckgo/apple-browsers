//
//  BaseURLDebugMenu.swift
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

import AppKit
import Persistence

/// Debug menu for configuring base URLs at runtime.
///
/// This menu allows internal users to override the default DuckDuckGo base URL
/// for testing purposes, such as pointing to local servers or dev instances.
///
/// ## Available Options
///
/// - **Set Custom BASE_URL**: Override the main DuckDuckGo base URL
/// - **Reset to Defaults**: Clear all custom overrides
///
/// ## Usage Notes
///
/// - Changes take effect immediately for new URL constructions
/// - The menu displays the current effective URLs
/// - A browser restart may be required for some cached URLs
final class BaseURLDebugMenu: NSMenu {
    private let debugSettings: any KeyedStoring<BaseURLDebugSettings>

    private let baseURLLabelMenuItem = NSMenuItem(title: "")
    private let helpURLLabelMenuItem = NSMenuItem(title: "")

    init(_ debugSettings: (any KeyedStoring<BaseURLDebugSettings>)? = nil) {
        self.debugSettings = if let debugSettings { debugSettings } else { UserDefaults.standard.keyedStoring() }
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Set Custom BASE_URL", action: #selector(setCustomBaseURL))
                .targetting(self)

            NSMenuItem.separator()

            NSMenuItem(title: "Reset to Defaults", action: #selector(resetToDefaults))
                .targetting(self)

            NSMenuItem.separator()

            baseURLLabelMenuItem
            helpURLLabelMenuItem

            NSMenuItem.separator()

            NSMenuItem(title: "⚠️ Changes take effect immediately", action: nil, target: nil)
            NSMenuItem(title: "⚠️ Some cached URLs may require browser restart", action: nil, target: nil)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateMenuItemsState()
    }

    private func updateMenuItemsState() {
        let baseURL = debugSettings.effectiveBaseURL
        let isBaseCustom = debugSettings.customBaseURL != nil && !debugSettings.customBaseURL!.isEmpty
        baseURLLabelMenuItem.title = "BASE_URL: \(baseURL)\(isBaseCustom ? " (custom)" : "")"

        let helpURL = debugSettings.effectiveHelpBaseURL
        helpURLLabelMenuItem.title = "HELP_BASE_URL: \(helpURL)"
    }

    // MARK: - Actions

    @objc func setCustomBaseURL() {
        showURLInputAlert(
            title: "Set Custom BASE_URL",
            message: "Enter the base URL for DuckDuckGo (e.g., http://localhost:8080)",
            currentValue: debugSettings.customBaseURL
        ) { [weak self] value in
            guard let value = value else { return false }

            if value.isEmpty {
                self?.debugSettings.customBaseURL = nil
                return true
            }

            guard let url = URL(string: value), url.isValid else { return false }

            self?.debugSettings.customBaseURL = value
            return true
        }
    }

    @objc func resetToDefaults() {
        debugSettings.reset()
        updateMenuItemsState()

        let alert = NSAlert()
        alert.messageText = "URLs Reset"
        alert.informativeText = "All custom URLs have been cleared. Default production URLs will be used."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Alert Helper

    private func showURLInputAlert(
        title: String,
        message: String,
        currentValue: String?,
        callback: @escaping (String?) -> Bool
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")

        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = currentValue ?? ""
        inputTextField.placeholderString = "https://duckduckgo.com"
        alert.accessoryView = inputTextField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if !callback(inputTextField.stringValue) {
                let invalidAlert = NSAlert()
                invalidAlert.messageText = "Invalid URL"
                invalidAlert.informativeText = "Please enter a valid URL or leave empty to reset."
                invalidAlert.addButton(withTitle: "OK")
                invalidAlert.runModal()
            }
        } else {
            _ = callback(nil)
        }
    }
}
