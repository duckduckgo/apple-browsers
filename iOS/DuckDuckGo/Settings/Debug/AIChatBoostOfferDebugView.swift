//
//  AIChatBoostOfferDebugView.swift
//  DuckDuckGo
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
import PrivacyConfig
import Core
import DebugServer
import FeatureFlags_iOS
import FoundationExtensions
import SwiftUI

/// Shows what Duck.ai receives for the bonus offer and changes the inputs, to test each state without waiting.
struct AIChatBoostOfferDebugView: View {
    @StateObject private var viewModel: AIChatBoostOfferDebugViewModel
    @ObservedObject private var serverState = AIChatBonusDebugServerState.shared
    private let featureFlagger: FeatureFlagger?
    private let messageLog: AIChatBonusMessageLog?

    init(featureFlagger: FeatureFlagger?, messageLog: AIChatBonusMessageLog?) {
        self.featureFlagger = featureFlagger
        self.messageLog = messageLog
        _viewModel = StateObject(wrappedValue: AIChatBoostOfferDebugViewModel(featureFlagger: featureFlagger))
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: "Changes here aren't pushed to open Duck.ai tabs. Reload Duck.ai to see them.")
                    .foregroundColor(.red)
            }

            Section(header: Text(verbatim: "Message Server"),
                    footer: Text(verbatim: "Shows the state and the messages exchanged with Duck.ai in a browser on the same network. Messages are recorded only while it runs.")) {
                if serverState.isRunning {
                    Text(verbatim: "Server running")
                        .foregroundColor(.green)
                    if let ip = serverState.localIPAddress {
                        Text(verbatim: "http://\(ip):\(AIChatBonusDebugServerState.port)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button(role: .destructive, action: serverState.stop) {
                        Text(verbatim: "Stop Server")
                    }
                } else {
                    if let error = serverState.errorMessage {
                        Text(verbatim: error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    Button {
                        serverState.start(featureFlagger: featureFlagger, messageLog: messageLog)
                    } label: {
                        Text(verbatim: "Start Server")
                    }
                }
            }

            Section(header: Text(verbatim: "State")) {
                row("Feature flag", viewModel.isFeatureFlagOn.map { $0 ? "On" : "Off" } ?? "Unknown")
                row("Duck.ai enabled", viewModel.isAIChatEnabled ? "Yes" : "No")
                row("New install", viewModel.isNewInstall ? "Yes" : "No")
                row("Install date", viewModel.installDateDescription)
                row("Days since install", viewModel.daysSinceInstallDescription)
                row("Install window", "\(AIChatBonusFactsProvider.defaultInstallWindowDays) days")
                row("Boost", viewModel.boostDescription)
            }

            Section(header: Text(verbatim: "Record")) {
                Text(verbatim: viewModel.recordDescription)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section(header: Text(verbatim: "Install"),
                    footer: Text(verbatim: "Other features read the install date and the returning user variant too, e.g. the onboarding and subscription promo cooldowns.")) {
                Stepper(value: $viewModel.installDaysAgo, in: 0...14) {
                    Text(verbatim: "Install date: \(viewModel.installDaysAgo) days ago")
                }
                Button(action: viewModel.applyInstallDate) {
                    Text(verbatim: "Set Install Date")
                }
                Button(action: viewModel.clearInstallDate) {
                    Text(verbatim: "Clear Install Date")
                }
                Toggle(isOn: Binding(get: { viewModel.isReturningUser }, set: viewModel.setReturningUser)) {
                    Text(verbatim: "Returning User")
                }
            }

            Section(header: Text(verbatim: "Record Actions")) {
                Button(action: viewModel.expireBoost) {
                    Text(verbatim: "Expire Boost Now")
                }
                .disabled(!viewModel.hasTerms)
                Button(action: viewModel.clearDismissedCampaign) {
                    Text(verbatim: "Clear Dismissed Campaign")
                }
                .disabled(!viewModel.hasDismissedCampaign)
                Button(role: .destructive, action: viewModel.deleteRecord) {
                    Text(verbatim: "Delete Record")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section(header: Text(verbatim: "Last Error")) {
                    Text(verbatim: errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Duck.ai Boost Offer"))
        .onAppear(perform: viewModel.refresh)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .foregroundColor(.secondary)
        }
    }
}

final class AIChatBoostOfferDebugViewModel: ObservableObject {
    @Published private(set) var isFeatureFlagOn: Bool?
    @Published private(set) var isAIChatEnabled = false
    @Published private(set) var isNewInstall = false
    @Published private(set) var installDateDescription = "None"
    @Published private(set) var daysSinceInstallDescription = "-"
    @Published private(set) var boostDescription = "None"
    @Published private(set) var recordDescription = "No record"
    @Published private(set) var hasTerms = false
    @Published private(set) var hasDismissedCampaign = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReturningUser = false
    @Published var installDaysAgo = 0

    // Reads and writes the file directly: the service keeps no copy, so its next read sees the change.
    private let store: AIChatBonusStoring = AIChatBonusStore()
    private let statisticsStore = StatisticsUserDefaults()
    private let aiChatSettings = AIChatSettings()
    private let featureFlagger: FeatureFlagger?

    init(featureFlagger: FeatureFlagger?) {
        self.featureFlagger = featureFlagger
    }

    func refresh() {
        let facts = AIChatBonusFactsProvider(statisticsStore: statisticsStore, aiChatSettings: aiChatSettings)
        isFeatureFlagOn = featureFlagger?.isFeatureOn(.aiChatLimitExtensionPromo)
        isAIChatEnabled = facts.isAIChatEnabled
        isNewInstall = facts.isNewInstall
        isReturningUser = statisticsStore.variant == VariantIOS.returningUser.name

        if let installDate = statisticsStore.installDate {
            installDateDescription = installDate.formatted(date: .abbreviated, time: .shortened)
            let daysSinceInstall = Calendar.current.numberOfDaysBetween(installDate, and: Date())
            daysSinceInstallDescription = daysSinceInstall.map(String.init) ?? "-"
            // Start the stepper from the stored date, so reopening the screen shows what was set.
            if let daysSinceInstall {
                installDaysAgo = min(max(daysSinceInstall, 0), 14)
            }
        } else {
            installDateDescription = "None"
            daysSinceInstallDescription = "-"
        }

        do {
            let record = try store.read()
            recordDescription = try record.map(Self.prettyJSON) ?? "No record"
            hasTerms = record?.terms != nil
            hasDismissedCampaign = record?.dismissedCampaignName != nil
            boostDescription = Self.boostDescription(for: record)
        } catch {
            recordDescription = "Can't read the record"
            hasTerms = false
            hasDismissedCampaign = false
            boostDescription = "Unknown"
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Install

    func applyInstallDate() {
        statisticsStore.installDate = Calendar.current.date(byAdding: .day, value: -installDaysAgo, to: Date())
        refresh()
    }

    func clearInstallDate() {
        statisticsStore.installDate = nil
        refresh()
    }

    func setReturningUser(_ isReturning: Bool) {
        statisticsStore.variant = isReturning ? VariantIOS.returningUser.name : nil
        refresh()
    }

    // MARK: - Record

    func expireBoost() {
        updateRecord { record in
            guard let terms = record.terms else { return }
            record.terms = AIChatBonusRecord.Terms(multiplier: terms.multiplier, expiresAt: Date().timeIntervalSince1970 - 1)
        }
    }

    func clearDismissedCampaign() {
        updateRecord { $0.dismissedCampaignName = nil }
    }

    func deleteRecord() {
        perform { try store.delete() }
    }

    private func updateRecord(_ change: (inout AIChatBonusRecord) -> Void) {
        perform {
            guard var record = try store.read() else { return }
            change(&record)
            try store.write(record)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
        refresh()
    }

    // MARK: - Formatting

    private static func prettyJSON(_ record: AIChatBonusRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(bytes: try encoder.encode(record), encoding: .utf8) ?? "Can't show the record"
    }

    private static func boostDescription(for record: AIChatBonusRecord?) -> String {
        guard let terms = record?.terms else {
            return record?.bonusId == nil ? "None" : "Pending"
        }
        let expiry = Date(timeIntervalSince1970: terms.expiresAt).formatted(date: .abbreviated, time: .shortened)
        return terms.expiresAt > Date().timeIntervalSince1970 ? "Active until \(expiry)" : "Expired \(expiry)"
    }
}

/// The bonus offer state for the Duck.ai storage debug dashboard, with the Bonus ID masked.
enum AIChatBoostOfferDebugState {

    static func snapshot(featureFlagger: FeatureFlagger?) -> [String: Any] {
        let statisticsStore = StatisticsUserDefaults()
        let facts = AIChatBonusFactsProvider(statisticsStore: statisticsStore, aiChatSettings: AIChatSettings())
        let isFlagOn = featureFlagger?.isFeatureOn(.aiChatLimitExtensionPromo)

        var state: [String: Any] = [
            "isNewInstall": facts.isNewInstall,
            "aiChatEnabled": facts.isAIChatEnabled,
            "installWindowDays": AIChatBonusFactsProvider.defaultInstallWindowDays,
            "isReturningUser": statisticsStore.variant == VariantIOS.returningUser.name
        ]
        // Native sends the flag's value as `supportsBonusOffer`.
        state["supportsBonusOffer"] = isFlagOn ?? NSNull()
        if let installDate = statisticsStore.installDate {
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
}

/// Owns the bonus offer debug server for the app session.
@MainActor
private final class AIChatBonusDebugServerState: ObservableObject {
    static let shared = AIChatBonusDebugServerState()
    static let port: UInt16 = 8474

    @Published private(set) var errorMessage: String?
    @Published private(set) var localIPAddress: String?
    @Published private(set) var isRunning = false

    private var server: AIChatBonusDebugServer? {
        didSet { isRunning = server != nil }
    }

    private init() {}

    func start(featureFlagger: FeatureFlagger?, messageLog: AIChatBonusMessageLog?) {
        guard let messageLog else {
            errorMessage = "The bonus message log is not available"
            return
        }

        do {
            let server = AIChatBonusDebugServer(
                stateProvider: { AIChatBoostOfferDebugState.snapshot(featureFlagger: featureFlagger) },
                messageLog: messageLog,
                port: Self.port
            )
            server.stateDidChange = { [weak self] state in
                DispatchQueue.main.async {
                    guard case .failed(let message) = state else { return }
                    self?.errorMessage = message
                    self?.server = nil
                    self?.localIPAddress = nil
                }
            }
            try server.start()
            self.server = server
            errorMessage = nil
            localIPAddress = DebugServerNetworkInterface.wiFiAddress()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        server?.stop()
        server = nil
        localIPAddress = nil
    }
}
