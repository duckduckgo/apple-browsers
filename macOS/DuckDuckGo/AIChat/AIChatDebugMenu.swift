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
import AIChatDebugServer
import DebugServer
import AppKit
import os.log
import Persistence

final class AIChatDebugMenu: NSMenu {
    private var storage = DefaultAIChatPreferencesStorage()
    private let customURLLabelMenuItem = NSMenuItem(title: "")
    private let debugStorage: any KeyedStoring<AIChatDebugURLSettings>

    private var storageDebugServer: DuckAiStorageDebugServer?
    /// So "re-seed" can rewrite the same case with fresh reset times, which is what a republish looks like.
    private var lastSeededCase: DuckAiUsageSnapshotSeed?
    private lazy var storageServerMenuItem = NSMenuItem(
        title: "Start Storage Server",
        action: #selector(toggleStorageServer),
        target: self
    )

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

            NSMenuItem(title: "Reset Toggle Animation", action: #selector(resetToggleAnimation))
                .targetting(self)

            NSMenuItem.separator()

            usageWarningsMenuItem

            NSMenuItem.separator()

            storageServerMenuItem
        }
    }

    // MARK: - Duck.ai Usage Warnings

    /// Seeds the reserved `usageLimits` entry — the same one the web app writes — so the real read
    /// path drives the message. Needs the `aiChatUsageWarnings` flag on; with the entries publisher
    /// wired, an open omnibar updates as soon as a seed lands.
    private var usageWarningsMenuItem: NSMenuItem {
        let item = NSMenuItem(title: "Duck.ai Usage Warnings")
        let submenu = NSMenu()

        submenu.addItem(sectionHeader("Free"))
        addSeeds(DuckAiUsageSnapshotSeed.freeSeeds, to: submenu)
        submenu.addItem(.separator())
        submenu.addItem(sectionHeader("Paid"))
        addSeeds(DuckAiUsageSnapshotSeed.paidSeeds, to: submenu)
        submenu.addItem(.separator())

        submenu.addItem(menuItem(title: "Re-seed the last case (simulates a republish)",
                                 action: #selector(reseedLastUsageSnapshot)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem(title: "Clear usage snapshot", action: #selector(clearUsageSnapshot)))
        submenu.addItem(menuItem(title: "Clear dismissals", action: #selector(clearUsageDismissals)))

        item.submenu = submenu
        return item
    }

    private func addSeeds(_ seeds: [DuckAiUsageSnapshotSeed], to menu: NSMenu) {
        for seed in seeds {
            let item = menuItem(title: seed.displayName, action: #selector(seedUsageSnapshot(_:)))
            item.representedObject = seed.rawValue
            item.toolTip = seed.expectation
            menu.addItem(item)
        }
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title)
        item.isEnabled = false
        return item
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func seedUsageSnapshot(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let seed = DuckAiUsageSnapshotSeed(rawValue: rawValue) else { return }

        lastSeededCase = seed
        writeUsageSnapshot(seed)
    }

    /// A fresh reset time makes a new signature, which is what releases a message the user has
    /// already acted on — and what a real republish from web looks like.
    @objc private func reseedLastUsageSnapshot() {
        guard let lastSeededCase else {
            showAlert("Nothing to re-seed", "Pick a case first.")
            return
        }
        writeUsageSnapshot(lastSeededCase)
    }

    @objc private func clearUsageSnapshot() {
        guard let handler = storageHandlerOrAlert() else { return }
        lastSeededCase = nil
        try? handler.deleteEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue)
    }

    /// Brings back a message dismissed with its close button, and one whose CTA has been run.
    @objc private func clearUsageDismissals() {
        let store = DuckAiUsageWarningDismissalStore()
        store.setDismissal(nil)
        store.setActedSnapshot(nil)
    }

    private func writeUsageSnapshot(_ seed: DuckAiUsageSnapshotSeed) {
        guard let handler = storageHandlerOrAlert() else { return }

        guard NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatUsageWarnings) else {
            showAlert("The usage-warnings flag is off",
                      "Turn on aiChatUsageWarnings in Debug → Feature Flags. The snapshot was not written.")
            return
        }

        // Resolved from the live model list, so the switch CTAs offer something the picker can
        // actually select. Async, because the models come from the network.
        Task { @MainActor in
            let models = await accessibleModelIds()
            let selectedModelId = NSApp.delegateTyped.aiChatPreferencesPersistor.selectedModelId
            let targets = models.filter { $0 != selectedModelId }

            do {
                try handler.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue,
                                     value: seed.entryValue(switchTargets: targets, selectedModelId: selectedModelId))
            } catch {
                showAlert("Failed to seed the usage snapshot", error.localizedDescription)
                return
            }

            if targets.isEmpty {
                showAlert("Seeded without model targets",
                          "The models list could not be fetched, so any switch button will be hidden — "
                          + "which is the \"already on the cheapest model\" case. Everything else in the "
                          + "message renders normally.")
            }
        }
    }

    /// Best effort: an empty list seeds the hidden-button case rather than failing the seed. Resolved
    /// against the *free* tier deliberately — every account can select those, so a seeded switch never
    /// offers a model the picker would refuse.
    private func accessibleModelIds() async -> [String] {
        do {
            let service = AIChatModelsService(accessTokenProvider: NSApp.delegateTyped.subscriptionManager)
            let response = try await service.fetchModels()
            return response.models
                .map { AIChatModel(remoteModel: $0, userTier: .free) }
                .filter(\.entityHasAccess)
                .map(\.id)
        } catch {
            Logger.aiChat.error("Usage-warning seed: models fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Same unavailable-handler alert as the storage server, which is the other item needing the bridge.
    private func storageHandlerOrAlert() -> DuckAiNativeStorageHandling? {
        guard let handler = NSApp.delegateTyped.duckAiNativeStorageHandler else {
            showAlert("Native storage is not available",
                      "The duckAiNativeStorage feature flag may be disabled.")
            return nil
        }
        return handler
    }

    private func showAlert(_ messageText: String, _ informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    @objc func toggleStorageServer() {
        if let server = storageDebugServer {
            server.stop()
            storageDebugServer = nil
            storageServerMenuItem.title = "Start Storage Server"
        } else {
            guard let handler = NSApp.delegateTyped.duckAiNativeStorageHandler else {
                let alert = NSAlert()
                alert.messageText = "Native storage is not available"
                alert.informativeText = "The duckAiNativeStorage feature flag may be disabled."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            do {
                let server = DuckAiStorageDebugServer(storageHandler: handler)
                server.stateDidChange = { [weak self] state in
                    Task { @MainActor in
                        self?.handleStorageServerStateChange(state)
                    }
                }
                try server.start()
                storageDebugServer = server
                storageServerMenuItem.title = "Starting Storage Server…"
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to start storage server"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @MainActor
    private func handleStorageServerStateChange(_ state: ServerState) {
        switch state {
        case .running(let port):
            storageServerMenuItem.title = "Stop Storage Server (localhost:\(port))"
            if let url = URL(string: "http://localhost:\(port)") {
                Application.appDelegate.windowControllersManager.showTab(with: .url(url, source: .ui))
            }
        case .failed(let message):
            storageDebugServer = nil
            storageServerMenuItem.title = "Start Storage Server"
            let alert = NSAlert()
            alert.messageText = "Storage server failed"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        default:
            break
        }
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
