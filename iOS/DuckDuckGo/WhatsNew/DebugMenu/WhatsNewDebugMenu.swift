//
//  WhatsNewDebugMenu.swift
//  DuckDuckGo
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

import SwiftUI
import Persistence
import CoreData
import Core
import RemoteMessaging
import BrowserServicesKit
import DesignResourcesKitIcons

struct WhatsNewDebugView: View {
    @StateObject private var viewModel: WhatsNewDebugViewModel
    @State private var isShowingExamplePrompt = false

    init(
        diagnosticsProvider: PromoCoordinationDiagnosticsProviding?,
        cooldownResetter: PromoCoordinationCooldownResetting?,
        remoteMessagingDebugHandler: RemoteMessagingDebugHandling? = nil
    ) {
        self._viewModel = StateObject(
            wrappedValue: WhatsNewDebugViewModel(
                diagnosticsProvider: diagnosticsProvider,
                cooldownResetter: cooldownResetter,
                remoteMessagingDebugHandler: remoteMessagingDebugHandler
            )
        )
    }

    var body: some View {
        List {
            Section {
                Text(viewModel.formattedCooldownPeriod)
                if viewModel.isCooldownPeriodActive {
                    Button("Reset Cooldown") {
                        viewModel.resetCoolDownPeriod()
                    }
                }
            } header: {
                Text(verbatim: "Prompt Cooldown")
            } footer: {
                if viewModel.isCooldownPeriodActive {
                    Text(verbatim: "Reset Cooldown period to allow modal prompt to show again.")
                        .foregroundColor(.red)
                }
            }

            Section(header: Text(verbatim: "Debug Tool")) {
                Button("Show Example Prompt") {
                    isShowingExamplePrompt = true
                }
                Button("Delete RMF Messages") {
                    viewModel.deleteAllMessages()
                }
            }
        }
        .sheet(isPresented: $isShowingExamplePrompt) {
            WhatsNewExamplePrompt {
                isShowingExamplePrompt = false
            }
        }
    }
}

private struct WhatsNewExamplePrompt: UIViewControllerRepresentable {
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> WhatsNewViewController {
        WhatsNewViewController(displayModel: .example, onCloseButton: onClose)
    }

    func updateUIViewController(_ uiViewController: WhatsNewViewController, context: Context) {}
}

private extension RemoteMessagingUI.CardsListDisplayModel {
    static var example: Self {
        let chevron = Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronRightSmall)

        return .init(
            screenTitle: "What’s New",
            icon: RemotePlaceholder.ddgAnnounce.rawValue,
            preloadedHeaderImage: nil,
            headerImageUrl: nil,
            loadHeaderImage: nil,
            onHeaderImageLoadSuccess: nil,
            onHeaderImageLoadFailed: nil,
            items: [
                .twoLinesCard(.init(
                    icon: RemotePlaceholder.aiChat.rawValue,
                    title: "Sync Duck.ai Chats Across Devices",
                    description: "Sync your chats across desktop and mobile by visiting Duck.ai Settings > Sync & Backup.",
                    disclosureIcon: chevron
                )),
                .twoLinesCard(.init(
                    icon: RemotePlaceholder.announce.rawValue,
                    title: "Browse With Fire Tabs",
                    description: "Use Fire Tabs to isolate your browsing from normal tabs and browse without saving local history.",
                    disclosureIcon: chevron,
                    cachedImage: { DesignSystemImages.Color.Size96.fire }
                )),
                .twoLinesCard(.init(
                    icon: RemotePlaceholder.subscription.rawValue,
                    title: "Explore More Subscription Options",
                    description: "Pick from two plans: Plus (for all four protections) or Pro (for more powerful AI functionality).",
                    disclosureIcon: chevron
                ))
            ],
            onAppear: nil,
            primaryAction: nil
        )
    }
}

@MainActor
private final class WhatsNewDebugViewModel: ObservableObject {
    private let diagnosticsProvider: PromoCoordinationDiagnosticsProviding?
    private let cooldownResetter: PromoCoordinationCooldownResetting?
    private let remoteMessagingDebugHandler: RemoteMessagingDebugHandling?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return formatter
    }()

    private let database: CoreDataDatabase

    @Published private(set) var isCooldownPeriodActive: Bool = false
    @Published private(set) var formattedCooldownPeriod: String = ""

    init(
        diagnosticsProvider: PromoCoordinationDiagnosticsProviding?,
        cooldownResetter: PromoCoordinationCooldownResetting?,
        remoteMessagingDebugHandler: RemoteMessagingDebugHandling? = nil
    ) {
        self.diagnosticsProvider = diagnosticsProvider
        self.cooldownResetter = cooldownResetter
        self.remoteMessagingDebugHandler = remoteMessagingDebugHandler
        self.database = Database.shared
        updateUI()
    }

    func resetCoolDownPeriod() {
        cooldownResetter?.resetModalCooldown()
        updateUI()
    }

    func deleteAllMessages() {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        context.refreshAllObjects()
        context.deleteAll(entityDescriptions: [
            RemoteMessageManagedObject.entity(in: context),
            RemoteMessagingConfigManagedObject.entity(in: context)
        ])

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save after delete all")
        }
        remoteMessagingDebugHandler?.refreshRemoteMessages()
    }

    private func updateUI() {
        let lastAppearance = diagnosticsProvider?.diagnosticSnapshot.cooldown.lastConfirmedModalAppearance
        isCooldownPeriodActive = lastAppearance != nil
        formattedCooldownPeriod = makeFormattedCooldownPeriod(lastAppearance)
    }

    private func makeFormattedCooldownPeriod(_ date: Date?) -> String {
        guard let date else {
            return "No Prompt Cooldown active."
        }

        return "Modal Prompt shown \(Self.dateFormatter.string(from: date))."
    }
}
