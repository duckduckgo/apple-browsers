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
        keyValueStore: ThrowingKeyValueStoring,
        remoteMessagingDebugHandler: RemoteMessagingDebugHandling? = nil
    ) {
        self._viewModel = StateObject(
            wrappedValue: WhatsNewDebugViewModel(
                diagnosticsProvider: diagnosticsProvider,
                cooldownResetter: cooldownResetter,
                keyValueStore: keyValueStore,
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

            Section {
                Picker("Main Button Action", selection: $viewModel.testPrimaryAction) {
                    ForEach(WhatsNewTestAction.allCases) { action in
                        Text(verbatim: action.rawValue).tag(action)
                    }
                }
                Button("Save Test Message") {
                    viewModel.saveTestMessage()
                }
                if let result = viewModel.testMessageResult {
                    Text(verbatim: result)
                }
            } header: {
                Text(verbatim: "Test Message")
            } footer: {
                Text(verbatim: "Includes navigation, URLs, sharing, App Store, survey handling, and display-only cards. The main button uses the selected action. Unimplemented navigation targets are listed without actions.")
                Text(verbatim: "Replaces the saved What’s New message. Return to Settings > What’s New to test it. If What’s New is hidden, turn on Internal User in Debug, then enable showWhatsNewPromptOnDemand.")
                Text(verbatim: "PIR uses your current subscription and scan state. To test the free scan landing page, sign out and use Force Freemium PIR Eligibility in Data Broker Protection Debug. Use a profile with no previous scan.")
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

private enum WhatsNewTestAction: String, CaseIterable, Identifiable {
    case dismiss = "Dismiss"
    case aiFeatures = "AI Features"
    case personalInformationRemoval = "Personal Information Removal"
    case importPasswords = "Import Passwords"
    case url = "Open URL in New Tab"
    case urlInContext = "Open Embedded URL"
    case share = "Share"
    case appStore = "App Store"
    case survey = "Survey"

    var id: Self { self }

    var action: RemoteAction {
        switch self {
        case .dismiss: .dismiss
        case .aiFeatures: .navigation(value: .duckAISettings)
        case .personalInformationRemoval: .navigation(value: .personalInformationRemoval)
        case .importPasswords: .navigation(value: .importPasswords)
        case .url: .url(value: "https://example.com/?rmf-test=url")
        case .urlInContext: .urlInContext(value: "https://example.com/?rmf-test=embedded")
        case .share: .share(value: "https://example.com/", title: "What’s New Test Message")
        case .appStore: .appStore
        case .survey: .survey(value: "https://example.com/?rmf-test=survey")
        }
    }

    var description: String {
        switch self {
        case .dismiss: "Close What’s New using the main button."
        case .aiFeatures: "Open Settings > AI Features."
        case .personalInformationRemoval: "Open PIR using your current eligibility and scan state."
        case .importPasswords: "Open the password import flow."
        case .url: "Close What’s New and open example.com in a browser tab."
        case .urlInContext: "Open example.com inside What’s New."
        case .share: "Open the share sheet with a sample URL."
        case .appStore: "Open DuckDuckGo’s App Store page. Requires App Store availability."
        case .survey: "Exercise survey URL handling with example.com. No real survey is used."
        }
    }

    var placeholder: RemotePlaceholder {
        switch self {
        case .aiFeatures: .aiChat
        case .personalInformationRemoval: .pir
        default: .announce
        }
    }
}

private enum WhatsNewTestMessage {
    static func make(primaryAction: WhatsNewTestAction) -> RemoteMessageModel {
        let navigationActions: [WhatsNewTestAction] = [.aiFeatures, .personalInformationRemoval, .importPasswords]
        let otherActions: [WhatsNewTestAction] = [.url, .urlInContext, .share, .appStore, .survey]
        let unavailableTargets: [NavigationTarget] = [.settings, .settingsGeneral, .appearance, .feedback, .sync, .softwareUpdate]

        let navigationItems = navigationActions.enumerated().map { index, action in
            item(id: "debug-navigation-\(index)", action: action, featured: action == .personalInformationRemoval)
        }
        let actionItems = otherActions.enumerated().map { index, action in
            item(id: "debug-action-\(index)", action: action, featured: action == .share)
        }
        let displayItems = [
            RemoteMessageModelType.ListItem(
                id: "debug-display-only",
                type: .twoLinesItem(titleText: "A card without an action",
                                    descriptionText: "This longer description wraps onto multiple lines to help check the row layout. This card has no disclosure arrow and does nothing when tapped.",
                                    placeholderImage: .announce,
                                    imageUrl: nil,
                                    action: nil),
                matchingRules: [],
                exclusionRules: []
            ),
            RemoteMessageModelType.ListItem(
                id: "debug-featured-display-only",
                type: .featuredTwoLinesSingleActionItem(titleText: "A featured card without an action",
                                                       descriptionText: "This card displays an illustration and text without an action button.",
                                                       placeholderImage: .ddgAnnounce,
                                                       imageUrl: nil,
                                                       primaryActionText: nil,
                                                       primaryAction: nil),
                matchingRules: [],
                exclusionRules: []
            )
        ]
        let unavailableItems = unavailableTargets.map { target in
            RemoteMessageModelType.ListItem(
                id: "debug-unavailable-\(target.rawValue)",
                type: .twoLinesItem(titleText: target.rawValue,
                                    descriptionText: "Navigation to this target is not implemented from What’s New. This card has no action.",
                                    placeholderImage: .announce,
                                    imageUrl: nil,
                                    action: nil),
                matchingRules: [],
                exclusionRules: []
            )
        }
        let items = [section(id: "navigation", title: "Navigation", items: navigationItems)] + navigationItems
            + [section(id: "actions", title: "Other Actions", items: actionItems)] + actionItems
            + [section(id: "display", title: "Display Only", items: displayItems)] + displayItems
            + [section(id: "unavailable", title: "Unimplemented Navigation", items: unavailableItems)] + unavailableItems

        return RemoteMessageModel(
            id: "debug-whats-new-test",
            surfaces: .modal,
            content: .cardsList(titleText: "What’s New — Test Message",
                                placeholder: .ddgAnnounce,
                                imageUrl: nil,
                                items: items,
                                primaryActionText: primaryAction == .dismiss ? "Done" : primaryAction.rawValue,
                                primaryAction: primaryAction.action),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
    }

    private static func item(id: String, action: WhatsNewTestAction, featured: Bool) -> RemoteMessageModelType.ListItem {
        let type: RemoteMessageModelType.ListItem.ListItemType
        if featured {
            type = .featuredTwoLinesSingleActionItem(titleText: action.rawValue,
                                                   descriptionText: action.description,
                                                   placeholderImage: action.placeholder,
                                                   imageUrl: nil,
                                                   primaryActionText: action == .personalInformationRemoval ? "Try for Free" : action.rawValue,
                                                   primaryAction: action.action)
        } else {
            type = .twoLinesItem(titleText: action.rawValue,
                                 descriptionText: action.description,
                                 placeholderImage: action.placeholder,
                                 imageUrl: nil,
                                 action: action.action)
        }
        return RemoteMessageModelType.ListItem(id: id, type: type, matchingRules: [], exclusionRules: [])
    }

    private static func section(id: String, title: String, items: [RemoteMessageModelType.ListItem]) -> RemoteMessageModelType.ListItem {
        RemoteMessageModelType.ListItem(id: "debug-section-\(id)",
                                        type: .titledSection(titleText: title, itemIDs: items.map(\.id)),
                                        matchingRules: [],
                                        exclusionRules: [])
    }
}

@MainActor
private final class WhatsNewDebugViewModel: ObservableObject {
    private let diagnosticsProvider: PromoCoordinationDiagnosticsProviding?
    private let cooldownResetter: PromoCoordinationCooldownResetting?
    private let remoteMessagingDebugHandler: RemoteMessagingDebugHandling?
    private let keyValueStore: ThrowingKeyValueStoring

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
    @Published var testPrimaryAction: WhatsNewTestAction = .dismiss
    @Published private(set) var testMessageResult: String?

    init(
        diagnosticsProvider: PromoCoordinationDiagnosticsProviding?,
        cooldownResetter: PromoCoordinationCooldownResetting?,
        keyValueStore: ThrowingKeyValueStoring,
        remoteMessagingDebugHandler: RemoteMessagingDebugHandling? = nil
    ) {
        self.diagnosticsProvider = diagnosticsProvider
        self.cooldownResetter = cooldownResetter
        self.remoteMessagingDebugHandler = remoteMessagingDebugHandler
        self.keyValueStore = keyValueStore
        self.database = Database.shared
        updateUI()
    }

    func resetCoolDownPeriod() {
        cooldownResetter?.resetModalCooldown()
        updateUI()
    }

    func saveTestMessage() {
        do {
            try DefaultWhatsNewMessageRepository.saveLastShownMessage(WhatsNewTestMessage.make(primaryAction: testPrimaryAction), in: keyValueStore)
            testMessageResult = "Saved. Open Settings > What’s New to test the message."
        } catch {
            testMessageResult = "Could not save the message: \(error.localizedDescription)"
        }
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
