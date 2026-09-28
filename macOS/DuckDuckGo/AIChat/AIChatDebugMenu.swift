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

            NSMenuItem(title: "Sidebar Debugging").submenu(AIChatSidebarDebugMenu())

            NSMenuItem.separator()

            usageWarningsMenuItem

            NSMenuItem.separator()

            storageServerMenuItem

#if DEBUG
            NSMenuItem.separator()

            NSMenuItem(title: "Browser Tools Panel…", action: #selector(openBrowserToolsPanel))
                .targetting(self)
            browserToolPermissionsMenuItem
#endif
        }
    }

#if DEBUG

    // MARK: - Browser Tools

    private var browserToolsPanel: BrowserToolsDebugPanel?

    @MainActor
    @objc func openBrowserToolsPanel() {
        let panel = browserToolsPanel
            ?? BrowserToolsDebugPanel(windowControllersManager: NSApp.delegateTyped.windowControllersManager)
        browserToolsPanel = panel
        panel.showWindow(nil)
        panel.window?.makeKeyAndOrderFront(nil)
    }

    private lazy var browserToolPermissionsMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "Browser Tool Permissions")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.submenu = menu
        return item
    }()

    @MainActor
    @objc private func resetBrowserToolPermission(_ sender: NSMenuItem) {
        guard let toolName = sender.representedObject as? String else { return }
        NSApp.delegateTyped.aiChatBrowserToolsService.permissions.setState(.ask, forToolNamed: toolName)
    }

    @MainActor
    @objc private func resetAllBrowserToolPermissions() {
        NSApp.delegateTyped.aiChatBrowserToolsService.permissions.clearAll()
    }

#endif

    // MARK: - Duck.ai Usage Warnings

    /// Seeds the same entry the web app writes, so the real read path drives the message.
    private var usageWarningsMenuItem: NSMenuItem {
        let item = NSMenuItem(title: "Duck.ai Usage Warnings")
        let submenu = NSMenu()

        submenu.addItem(sectionHeader("Free"))
        addSeeds(DuckAiUsageSnapshotSeed.freeSeeds, to: submenu)
        submenu.addItem(.separator())
        submenu.addItem(sectionHeader("Paid"))
        addSeeds(DuckAiUsageSnapshotSeed.paidSeeds, to: submenu)
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

        writeUsageSnapshot(seed)
    }

    @objc private func clearUsageSnapshot() {
        guard let handler = storageHandlerOrAlert() else { return }
        try? handler.deleteEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue)
    }

    /// Brings back a message dismissed with its close button, and one whose CTA has been run.
    @objc private func clearUsageDismissals() {
        let store = DuckAiUsageWarningDismissalStore()
        DuckAiUsageWindow.allCases.forEach { store.setDismissal(nil, for: $0) }
        store.setActedSnapshot(nil)
    }

    private func writeUsageSnapshot(_ seed: DuckAiUsageSnapshotSeed) {
        guard let handler = storageHandlerOrAlert() else { return }

        guard NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatUsageWarnings) else {
            showAlert("The usage-warnings flag is off",
                      "Turn on aiChatUsageWarnings in Debug → Feature Flags. The snapshot was not written.")
            return
        }

        // From the live model list, so the switch CTAs offer something the picker can select.
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

    /// Resolved against the free tier: every account can select those, so a seeded switch never
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

    /// Same alert as the storage server, the other item needing the bridge.
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

#if DEBUG
extension AIChatDebugMenu: NSMenuDelegate {

    /// Rebuilt on every open so it always shows the decisions currently stored.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === browserToolPermissionsMenuItem.submenu else { return }
        menu.removeAllItems()

        let decisions = NSApp.delegateTyped.aiChatBrowserToolsService.permissions.storedDecisions
        if decisions.isEmpty {
            let none = NSMenuItem(title: "No stored decisions")
            none.isEnabled = false
            menu.addItem(none)
        }
        for (toolName, state) in decisions.sorted(by: { $0.key < $1.key }) {
            let item = NSMenuItem(title: "Reset \(toolName) (\(state.rawValue))",
                                  action: #selector(resetBrowserToolPermission(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = toolName
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let resetAll = NSMenuItem(title: "Reset All", action: #selector(resetAllBrowserToolPermissions), keyEquivalent: "")
        resetAll.target = self
        resetAll.isEnabled = !decisions.isEmpty
        menu.addItem(resetAll)
    }
}
#endif

// MARK: - Sidebar Debugging

enum AIChatSidebarDebugSettings {

    enum RevealPolicy: String, CaseIterable {
        case immediately, afterCommit, afterFirstPaint, afterFinish

        var title: String {
            switch self {
            case .immediately: return "Immediately (current behavior)"
            case .afterCommit: return "After Commit"
            case .afterFirstPaint: return "After First Paint"
            case .afterFinish: return "After Finish"
            }
        }
    }

    enum UnderPageColor: String, CaseIterable {
        case system, blue, black, red

        var title: String { rawValue.capitalized }

        var color: NSColor? {
            switch self {
            case .system: return nil
            case .blue: return .systemBlue
            case .black: return .black
            case .red: return .systemRed
            }
        }
    }

    static let loadDelayOptions: [Int] = [0, 1, 3, 5, 10]

    private static let defaults = UserDefaults.standard
    private static let prefix = "aiChatSidebarDebug."

    private static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        defaults.object(forKey: prefix + key) as? Bool ?? defaultValue
    }

    static var showTimelineOverlay: Bool {
        get { bool("showTimelineOverlay") }
        set { defaults.set(newValue, forKey: prefix + "showTimelineOverlay") }
    }

    static var tintLayers: Bool {
        get { bool("tintLayers") }
        set { defaults.set(newValue, forKey: prefix + "tintLayers") }
    }

    static var webViewDrawsBackground: Bool {
        get { bool("webViewDrawsBackground", default: true) }
        set { defaults.set(newValue, forKey: prefix + "webViewDrawsBackground") }
    }

    static var underPageColor: UnderPageColor {
        get { defaults.string(forKey: prefix + "underPageColor").flatMap(UnderPageColor.init) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: prefix + "underPageColor") }
    }

    static var revealPolicy: RevealPolicy {
        get { defaults.string(forKey: prefix + "revealPolicy").flatMap(RevealPolicy.init) ?? .immediately }
        set { defaults.set(newValue.rawValue, forKey: prefix + "revealPolicy") }
    }

    static var slowMotionOpen: Bool {
        get { bool("slowMotionOpen") }
        set { defaults.set(newValue, forKey: prefix + "slowMotionOpen") }
    }

    static var autoOpenInspector: Bool {
        get { bool("autoOpenInspector") }
        set { defaults.set(newValue, forKey: prefix + "autoOpenInspector") }
    }

    static var loadDelaySeconds: Int {
        get { defaults.integer(forKey: prefix + "loadDelaySeconds") }
        set { defaults.set(newValue, forKey: prefix + "loadDelaySeconds") }
    }

    static var lastTimeline: String {
        get { defaults.string(forKey: prefix + "lastTimeline") ?? "" }
        set { defaults.set(newValue, forKey: prefix + "lastTimeline") }
    }

    static func reset() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

final class AIChatSidebarDebugMenu: NSMenu, NSMenuDelegate {

    typealias Settings = AIChatSidebarDebugSettings

    init() {
        super.init(title: "")
        autoenablesItems = false
        delegate = self
        menuNeedsUpdate(self)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self else { return }
        removeAllItems()

        let note = NSMenuItem(title: "Changes apply the next time the sidebar opens")
        note.isEnabled = false
        addItem(note)
        addItem(.separator())

        addItem(toggle("Show Load Timeline Overlay", Settings.showTimelineOverlay, #selector(toggleTimelineOverlay)))
        addItem(action("Copy Last Load Timeline", #selector(copyLastTimeline), isEnabled: !Settings.lastTimeline.isEmpty))
        addItem(.separator())

        addItem(toggle("Tint Native Layers", Settings.tintLayers, #selector(toggleTintLayers)))
        let legend = NSMenuItem(title: "    magenta: sidebar container · red: sidebar root · green: web view container · blue: under-page")
        legend.isEnabled = false
        addItem(legend)
        addItem(toggle("Web View Draws Background", Settings.webViewDrawsBackground, #selector(toggleDrawsBackground)))
        addItem(choices("Under-Page Background Color",
                        Settings.UnderPageColor.allCases.map { ($0.title, $0.rawValue, $0 == Settings.underPageColor) },
                        #selector(selectUnderPageColor(_:))))
        addItem(.separator())

        addItem(choices("Reveal Web View",
                        Settings.RevealPolicy.allCases.map { ($0.title, $0.rawValue, $0 == Settings.revealPolicy) },
                        #selector(selectRevealPolicy(_:))))
        addItem(.separator())

        addItem(toggle("Slow-Motion Open (10×)", Settings.slowMotionOpen, #selector(toggleSlowMotion)))
        addItem(toggle("Auto-Open Web Inspector", Settings.autoOpenInspector, #selector(toggleAutoOpenInspector)))
        addItem(choices("Delay Load Start",
                        Settings.loadDelayOptions.map { ($0 == 0 ? "Off" : "\($0) s", $0, $0 == Settings.loadDelaySeconds) },
                        #selector(selectLoadDelay(_:))))
        addItem(.separator())

        addItem(action("Reset Sidebar Debug Settings", #selector(resetSettings)))
    }

    private func toggle(_ title: String, _ isOn: Bool, _ selector: Selector) -> NSMenuItem {
        let item = action(title, selector)
        item.state = isOn ? .on : .off
        return item
    }

    private func action(_ title: String, _ selector: Selector, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    private func choices(_ title: String, _ options: [(title: String, value: Any, isSelected: Bool)], _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for option in options {
            let optionItem = toggle(option.title, option.isSelected, selector)
            optionItem.representedObject = option.value
            submenu.addItem(optionItem)
        }
        item.submenu = submenu
        return item
    }

    @objc private func toggleTimelineOverlay() { Settings.showTimelineOverlay.toggle() }
    @objc private func toggleTintLayers() { Settings.tintLayers.toggle() }
    @objc private func toggleDrawsBackground() { Settings.webViewDrawsBackground.toggle() }
    @objc private func toggleSlowMotion() { Settings.slowMotionOpen.toggle() }
    @objc private func toggleAutoOpenInspector() { Settings.autoOpenInspector.toggle() }
    @objc private func resetSettings() { Settings.reset() }

    @objc private func selectUnderPageColor(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let color = Settings.UnderPageColor(rawValue: rawValue) else { return }
        Settings.underPageColor = color
    }

    @objc private func selectRevealPolicy(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let policy = Settings.RevealPolicy(rawValue: rawValue) else { return }
        Settings.revealPolicy = policy
    }

    @objc private func selectLoadDelay(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        Settings.loadDelaySeconds = seconds
    }

    @objc private func copyLastTimeline() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Settings.lastTimeline, forType: .string)
    }
}
