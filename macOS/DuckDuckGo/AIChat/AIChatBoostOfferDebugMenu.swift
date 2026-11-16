//
//  AIChatBoostOfferDebugMenu.swift
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

import AIChat
import AIChatDebugServer
import AppKit
import AppKitExtensions
import DebugServer
import FoundationExtensions

/// Shows what Duck.ai receives for the bonus offer and changes the inputs, to test each state without waiting.
/// Changes aren't pushed to open Duck.ai tabs: reload Duck.ai to see them.
final class AIChatBoostOfferDebugMenu: NSMenu {
    private static let serverPort: UInt16 = 8474
    private static let maxInstallDaysAgo = 14

    // Reads and writes the file directly: the service keeps no copy, so its next read sees the change.
    private let store: AIChatBonusStoring = AIChatBonusStore()
    private let messageLog: AIChatBonusMessageLog
    private var server: AIChatBonusDebugServer?

    private let flagItem = AIChatBoostOfferDebugMenu.infoItem()
    private let buildItem = AIChatBoostOfferDebugMenu.infoItem()
    private let aiChatEnabledItem = AIChatBoostOfferDebugMenu.infoItem()
    private let reinstallItem = AIChatBoostOfferDebugMenu.infoItem()
    private let installDateItem = AIChatBoostOfferDebugMenu.infoItem()
    private let newInstallItem = AIChatBoostOfferDebugMenu.infoItem()
    private let boostItem = AIChatBoostOfferDebugMenu.infoItem()

    private lazy var serverItem = NSMenuItem(title: "Start Message Server", action: #selector(toggleServer), target: self)
    private lazy var expireBoostItem = NSMenuItem(title: "Expire Boost Now", action: #selector(expireBoost), target: self)
    private lazy var clearDismissedItem = NSMenuItem(title: "Clear Dismissed Campaign", action: #selector(clearDismissedCampaign), target: self)

    /// - Parameter messageLog: The bonus messages the message server shows, shared with every Duck.ai tab.
    init(messageLog: AIChatBonusMessageLog = Application.appDelegate.aiChatBonusOffer.messageLog) {
        self.messageLog = messageLog
        super.init(title: "")
        autoenablesItems = false

        buildItems {
            Self.infoItem("Reload Duck.ai to see changes")

            NSMenuItem.separator()

            flagItem
            buildItem
            aiChatEnabledItem
            reinstallItem
            installDateItem
            newInstallItem
            boostItem

            NSMenuItem.separator()

            NSMenuItem(title: "Show Record…", action: #selector(showRecord), target: self)
            NSMenuItem(title: "Set Install Date…", action: #selector(setInstallDate), target: self)

            NSMenuItem.separator()

            expireBoostItem
            clearDismissedItem
            NSMenuItem(title: "Delete Record", action: #selector(deleteRecord), target: self)

            NSMenuItem.separator()

            serverItem
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State

    override func update() {
        super.update()
        let facts = AIChatBonusFactsProvider()
        let isFlagOn = NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatLimitExtensionPromo)
        let isSparkleBuild = StandardApplicationBuildType().isSparkleBuild

        flagItem.title = "Feature flag: \(isFlagOn ? "On" : "Off")"
        buildItem.title = "Build: \(isSparkleBuild ? "Sparkle" : "App Store (offer off)")"
        aiChatEnabledItem.title = "Duck.ai enabled: \(Self.yesNo(facts.isAIChatEnabled))"
        reinstallItem.title = "Reinstalling user: \(Self.yesNo(Self.isReinstallingUser))"
        newInstallItem.title = "New install: \(Self.yesNo(facts.isNewInstall))"
            + " (\(AIChatBonusFactsProvider.defaultInstallWindowDays)-day window)"

        if let installDate = LocalStatisticsStore().installDate {
            let days = Calendar.current.numberOfDaysBetween(installDate, and: Date()).map(String.init) ?? "-"
            installDateItem.title = "Install date: \(installDate.formatted(date: .abbreviated, time: .shortened)) (\(days) days ago)"
        } else {
            installDateItem.title = "Install date: None"
        }

        do {
            let record = try store.read()
            boostItem.title = "Boost: \(Self.boostDescription(for: record))"
            expireBoostItem.isEnabled = record?.terms != nil
            clearDismissedItem.isEnabled = record?.dismissedCampaignName != nil
        } catch {
            boostItem.title = "Boost: Can't read the record"
            expireBoostItem.isEnabled = false
            clearDismissedItem.isEnabled = false
        }
    }
}

// MARK: - Private

private extension AIChatBoostOfferDebugMenu {

    static var isReinstallingUser: Bool {
        DefaultReinstallUserDetection(keyValueStore: NSApp.delegateTyped.keyValueStore).isReinstallingUser
    }

    /// The bonus offer state for the message server dashboard, with the Bonus ID masked.
    static func snapshot() -> [String: Any] {
        let facts = AIChatBonusFactsProvider()
        let isSparkleBuild = StandardApplicationBuildType().isSparkleBuild
        let isFlagOn = NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatLimitExtensionPromo)

        var state: [String: Any] = [
            "isNewInstall": facts.isNewInstall,
            "aiChatEnabled": facts.isAIChatEnabled,
            "installWindowDays": AIChatBonusFactsProvider.defaultInstallWindowDays,
            "isReinstallingUser": isReinstallingUser,
            "isSparkleBuild": isSparkleBuild,
            // Native sends this as `supportsBonusOffer`.
            "supportsBonusOffer": isSparkleBuild && isFlagOn
        ]
        if let installDate = LocalStatisticsStore().installDate {
            state["installDate"] = ISO8601DateFormatter().string(from: installDate)
            state["daysSinceInstall"] = Calendar.current.numberOfDaysBetween(installDate, and: Date()) ?? NSNull()
        } else {
            state["installDate"] = NSNull()
        }
        do {
            let record = try AIChatBonusStore().read()
            state["record"] = record.flatMap(AIChatBonusMessageLog.maskedJSONObject(encoding:)) ?? NSNull()
        } catch {
            state["recordError"] = String(describing: error)
        }
        return state
    }

    // MARK: - Install

    @objc func setInstallDate() {
        let alert = NSAlert()
        alert.messageText = "Set Install Date"
        alert.informativeText = "Days ago, 0 to \(Self.maxInstallDaysAgo). "
            + "Other features read the install date too, e.g. promo cooldowns."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let daysAgo = Int(textField.stringValue.trimmingCharacters(in: .whitespaces)),
              (0...Self.maxInstallDaysAgo).contains(daysAgo) else {
            showAlert("Invalid number of days", "Enter a number from 0 to \(Self.maxInstallDaysAgo).")
            return
        }
        let statisticsStore = LocalStatisticsStore()
        statisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
    }

    // MARK: - Record

    @objc func showRecord() {
        let text: String
        do {
            text = try store.read().map(Self.prettyJSON) ?? "No record"
        } catch {
            text = "Can't read the record: \(error)"
        }
        showAlert("Boost Offer Record", text)
    }

    @objc func expireBoost() {
        updateRecord { record in
            guard let terms = record.terms else { return }
            record.terms = AIChatBonusRecord.Terms(multiplier: terms.multiplier, expiresAt: Date().timeIntervalSince1970 - 1)
        }
    }

    @objc func clearDismissedCampaign() {
        updateRecord { $0.dismissedCampaignName = nil }
    }

    @objc func deleteRecord() {
        perform { try store.delete() }
    }

    func updateRecord(_ change: (inout AIChatBonusRecord) -> Void) {
        perform {
            guard var record = try store.read() else { return }
            change(&record)
            try store.write(record)
        }
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            showAlert("Failed to change the record", String(describing: error))
        }
    }

    // MARK: - Message Server

    @MainActor
    @objc func toggleServer() {
        if let server {
            server.stop()
            self.server = nil
            serverItem.title = "Start Message Server"
            return
        }

        let server = AIChatBonusDebugServer(
            stateProvider: { DispatchQueue.main.sync { Self.snapshot() } },
            messageLog: messageLog,
            port: Self.serverPort
        )
        // Main-actor isolated, so it's Sendable and the server's @Sendable callback can hold it; the menu itself isn't.
        let handleStateChange: @MainActor (ServerState) -> Void = { [weak self] state in
            self?.handleServerStateChange(state)
        }
        server.stateDidChange = { state in
            Task { @MainActor in
                handleStateChange(state)
            }
        }
        do {
            try server.start()
            self.server = server
            serverItem.title = "Starting Message Server…"
        } catch {
            showAlert("Failed to start the message server", error.localizedDescription)
        }
    }

    @MainActor
    func handleServerStateChange(_ state: ServerState) {
        switch state {
        case .running(let port):
            serverItem.title = "Stop Message Server (localhost:\(port))"
            if let url = URL(string: "http://localhost:\(port)") {
                NSApp.delegateTyped.windowControllersManager.showTab(with: .url(url, source: .ui))
            }
        case .failed(let message):
            server = nil
            serverItem.title = "Start Message Server"
            showAlert("Message server failed", message)
        default:
            break
        }
    }

    // MARK: - Helpers

    static func infoItem(_ title: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title)
        item.isEnabled = false
        return item
    }

    static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    static func prettyJSON(_ record: AIChatBonusRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(bytes: try encoder.encode(record), encoding: .utf8) ?? "Can't show the record"
    }

    static func boostDescription(for record: AIChatBonusRecord?) -> String {
        guard let terms = record?.terms else {
            return record?.bonusId == nil ? "None" : "Pending"
        }
        let expiry = Date(timeIntervalSince1970: terms.expiresAt).formatted(date: .abbreviated, time: .shortened)
        return terms.expiresAt > Date().timeIntervalSince1970 ? "Active until \(expiry)" : "Expired \(expiry)"
    }

    func showAlert(_ messageText: String, _ informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
