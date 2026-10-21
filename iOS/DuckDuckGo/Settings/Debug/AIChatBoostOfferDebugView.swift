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
import PrivacyConfig
import Core
import FeatureFlags_iOS
import FoundationExtensions
import SwiftUI

/// Shows what Duck.ai receives for the bonus offer and changes the inputs, to test each state without waiting.
struct AIChatBoostOfferDebugView: View {
    @StateObject private var viewModel: AIChatBoostOfferDebugViewModel

    init(featureFlagger: FeatureFlagger?) {
        _viewModel = StateObject(wrappedValue: AIChatBoostOfferDebugViewModel(featureFlagger: featureFlagger))
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: "Changes here aren't pushed to open Duck.ai tabs. Reload Duck.ai to see them.")
                    .foregroundColor(.red)
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
                Toggle(isOn: $viewModel.isReturningUser) {
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
    @Published var installDaysAgo = 0

    @Published var isReturningUser = false {
        didSet {
            guard !isRefreshing, isReturningUser != oldValue else { return }
            setReturningUser(isReturningUser)
        }
    }

    /// Set while `refresh()` mirrors the stored state, so the toggle's `didSet` doesn't write it back.
    private var isRefreshing = false

    /// The variant to restore when Returning User is turned off.
    private static let savedVariantKey = "com.duckduckgo.ios.debug.aichat-boost-offer.saved-variant"

    // Reads and writes the file directly: the service keeps no copy, so its next read sees the change.
    private let store: AIChatBonusStoring = AIChatBonusStore()
    private let statisticsStore = StatisticsUserDefaults()
    private let aiChatSettings = AIChatSettings()
    private let featureFlagger: FeatureFlagger?
    private let userDefaults = UserDefaults.standard

    init(featureFlagger: FeatureFlagger?) {
        self.featureFlagger = featureFlagger
    }

    func refresh() {
        let facts = AIChatBonusFactsProvider(statisticsStore: statisticsStore, aiChatSettings: aiChatSettings)
        isFeatureFlagOn = featureFlagger?.isFeatureOn(.aiChatLimitExtensionPromo)
        isAIChatEnabled = facts.isAIChatEnabled
        isNewInstall = facts.isNewInstall
        isRefreshing = true
        isReturningUser = statisticsStore.variant == VariantIOS.returningUser.name
        isRefreshing = false

        if let installDate = statisticsStore.installDate {
            installDateDescription = installDate.formatted(date: .abbreviated, time: .shortened)
            daysSinceInstallDescription = Calendar.current.numberOfDaysBetween(installDate, and: Date()).map(String.init) ?? "-"
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

    private func setReturningUser(_ isReturning: Bool) {
        if isReturning {
            if let variant = statisticsStore.variant {
                userDefaults.set(variant, forKey: Self.savedVariantKey)
            }
            statisticsStore.variant = VariantIOS.returningUser.name
        } else {
            statisticsStore.variant = userDefaults.string(forKey: Self.savedVariantKey)
            userDefaults.removeObject(forKey: Self.savedVariantKey)
        }
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
