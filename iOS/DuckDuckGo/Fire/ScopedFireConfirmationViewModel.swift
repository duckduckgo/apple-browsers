//
//  ScopedFireConfirmationViewModel.swift
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

import Foundation
import Core
import Persistence

@MainActor
final class ScopedFireConfirmationViewModel: ObservableObject {

    // MARK: - Types

    struct FireConfirmationButton {
        enum Style { case primary, secondary, secondaryNeutral }

        let title: String
        let style: Style
        let action: () -> Void
        let accessibilityIdentifier: String
    }

    enum FireContext {
        /// Standard fire confirmation with "Delete All" and optional "Delete This Tab/Chat" buttons.
        case `default`(daxDialogsManager: DaxDialogsManaging)
        /// Contextual AI chat deletion with a single "Delete Chat" button.
        case contextualChat(onDelete: () -> Void)
        /// Duck.ai fire onboarding: single "Delete Chat" button scoped to the AI tab.
        case duckAIOnboarding
        /// New-tab-page escape hatch single-tab burn: one "Delete Tab" button scoped to the target tab.
        case singleTab
        /// Search Suggestions allow deleting History Entries
        case custom(title: String, subtitle: String, action: String)
        /// Duck.ai chat-history sheet "Delete All": title shows the count; `onDelete` is the
        /// caller-supplied action (dismiss + fire animation + burn), off the `burn(request:)` path.
        case deleteAllChats(count: Int, onDelete: () -> Void)
    }

    // MARK: - Constants

    private enum Keys {
        static let signOutWarningShowCount = "com.duckduckgo.fire.signOutWarningShowCount"
    }

    private enum AccessibilityIdentifiers {
        static let deleteAll = "alert.forget-data.confirm"
        static let thisTab = "Fire.Confirmation.Button.ThisTab"
    }

    private static let maxSubtitleShowCount = 2

    // MARK: - Public Properties

    /// The subtitle text to display. Computed once during initialization.
    @Published private(set) var subtitle: String?

    let headerTitle: String
    let showAnimation: Bool
    let buttons: [FireConfirmationButton]

    // MARK: - Private Variables

    private let fireContext: FireContext
    private let onCancel: () -> Void

    // MARK: - Initializer

    init(tabViewModel: TabViewModel?,
         source: FireRequest.Source,
         fireContext: FireContext,
         isSingleTab: Bool = false,
         downloadManager: DownloadManaging = AppDependencyProvider.shared.downloadManager,
         keyValueStore: KeyValueStoring = UserDefaults.standard,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         dataClearingCapability: DataClearingCapable = DataClearingCapability.create(using: AppDependencyProvider.shared.featureFlagger),
         browsingMode: BrowsingMode,
         onConfirm: @escaping (FireRequest) -> Void,
         onCancel: @escaping () -> Void) {
        self.fireContext = fireContext
        self.onCancel = onCancel

        let isRefinementsEnabled = dataClearingCapability.isFireButtonRefinementsEnabled
        let isSingleChatConfirmation = Self.isSingleChatConfirmation(fireContext: fireContext,
                                                                     isRefinementsEnabled: isRefinementsEnabled,
                                                                     tabViewModel: tabViewModel)
        let showDeleteAllOnlyForSingleTab = Self.showDeleteAllOnlyForSingleTab(fireContext: fireContext,
                                                                               isSingleTab: isSingleTab,
                                                                               isSingleChatConfirmation: isSingleChatConfirmation,
                                                                               tabViewModel: tabViewModel,
                                                                               dataClearingCapability: dataClearingCapability)

        self.headerTitle = Self.computeHeaderTitle(fireContext: fireContext,
                                                   isSingleChatConfirmation: isSingleChatConfirmation,
                                                   showDeleteAllOnlyForSingleTab: showDeleteAllOnlyForSingleTab,
                                                   browsingMode: browsingMode,
                                                   appSettings: appSettings)
        self.showAnimation = !(isRefinementsEnabled && appSettings.currentFireButtonAnimation == .none)
        self.buttons = Self.makeButtons(fireContext: fireContext,
                                        tabViewModel: tabViewModel,
                                        browsingMode: browsingMode,
                                        source: source,
                                        isRefinementsEnabled: isRefinementsEnabled,
                                        isSingleChatConfirmation: isSingleChatConfirmation,
                                        showDeleteAllOnlyForSingleTab: showDeleteAllOnlyForSingleTab,
                                        onConfirm: onConfirm,
                                        onCancel: onCancel)
        self.subtitle = Self.computeSubtitle(fireContext: fireContext,
                                             tabViewModel: tabViewModel,
                                             browsingMode: browsingMode,
                                             isSingleChatConfirmation: isSingleChatConfirmation,
                                             downloadManager: downloadManager,
                                             keyValueStore: keyValueStore,
                                             appSettings: appSettings)
    }

    // MARK: - Public Functions

    func cancel() {
        onCancel()
    }

    // MARK: - Button Building

    /// Returns `true` when the dialog should show only a single chat-delete button
    /// (contextual chat deletion, or AI tab with refinements enabled).
    private static func isSingleChatConfirmation(fireContext: FireContext,
                                                 isRefinementsEnabled: Bool,
                                                 tabViewModel: TabViewModel?) -> Bool {
        switch fireContext {
        case .contextualChat:
            return true
        case .custom:
            return true
        case .deleteAllChats:
            return true
        case .singleTab:
            return tabViewModel?.tab.isAITab == true
        case .duckAIOnboarding, .default:
            return isRefinementsEnabled && tabViewModel?.tab.isAITab == true
        }
    }

    /// Returns `true` when only one non-Duck.ai tab is open and the standard fire button is used.
    /// In that case "Delete This Tab" is equivalent to "Delete All", so the choice is dropped and
    /// only "Delete All" is shown. Gated behind the `fireButtonSingleTabDeleteAll` flag.
    private static func showDeleteAllOnlyForSingleTab(fireContext: FireContext,
                                                      isSingleTab: Bool,
                                                      isSingleChatConfirmation: Bool,
                                                      tabViewModel: TabViewModel?,
                                                      dataClearingCapability: DataClearingCapable) -> Bool {
        guard case .default = fireContext else { return false }
        guard dataClearingCapability.isSingleTabDeleteAllEnabled, isSingleTab else { return false }
        // Never override the Duck.ai single-chat confirmation.
        return !isSingleChatConfirmation && tabViewModel?.tab.isAITab != true
    }

    /// Builds the ordered list of action buttons for the confirmation sheet.
    ///
    /// - Contextual chat: single "Delete Chat" button
    /// - Duck.ai fire onboarding: single "Delete Chat" button (primary) for AI tabs only
    /// - AI tab + refinements: single "Delete This Chat" (tab-scoped)
    /// - Normal tab + refinements: "Delete This Tab" (primary) then "Delete All" (secondary)
    /// - Default: "Delete All" (primary), optionally "Delete This Tab" (secondary) if tab supports history
    private static func makeButtons(fireContext: FireContext,
                                    tabViewModel: TabViewModel?,
                                    browsingMode: BrowsingMode,
                                    source: FireRequest.Source,
                                    isRefinementsEnabled: Bool,
                                    isSingleChatConfirmation: Bool,
                                    showDeleteAllOnlyForSingleTab: Bool,
                                    onConfirm: @escaping (FireRequest) -> Void,
                                    onCancel: @escaping () -> Void) -> [FireConfirmationButton] {
        switch fireContext {
        case .contextualChat(let onDelete):
            // Single "Delete Chat" button calling contextual onDelete
            return [FireConfirmationButton(title: UserText.contextualChatDeleteConfirmationButton,
                               style: .primary,
                               action: onDelete,
                               accessibilityIdentifier: AccessibilityIdentifiers.deleteAll)]
        case .duckAIOnboarding:
            // Single "Delete Chat" button (primary) for AI tabs only
            if tabViewModel?.tab.isAITab == true {
                return [FireConfirmationButton(title: UserText.contextualChatDeleteConfirmationButton,
                                   style: .primary,
                                   action: { burnTab(tabViewModel: tabViewModel, options: [.aiChats], source: source, onConfirm: onConfirm) },
                                   accessibilityIdentifier: AccessibilityIdentifiers.thisTab)]
            }
            return []
        case .custom(_, _, let action):
            return [FireConfirmationButton(title: action,
                               style: .primary,
                               action: { performCustomRequest(source: source, onConfirm: onConfirm) },
                               accessibilityIdentifier: AccessibilityIdentifiers.thisTab)]
        case .deleteAllChats(_, let onDelete):
            // "Delete All" (destructive) over a neutral "Cancel". The caller supplies the burn
            // action; the chat-history sheet only surfaces persistent chats.
            return [
                FireConfirmationButton(title: UserText.scopedFireConfirmationDeleteChatsButton,
                                       style: .primary,
                                       action: onDelete,
                                       accessibilityIdentifier: AccessibilityIdentifiers.deleteAll),
                FireConfirmationButton(title: UserText.actionCancel,
                                       style: .secondaryNeutral,
                                       action: onCancel,
                                       accessibilityIdentifier: "Fire.Confirmation.Button.Cancel")
            ]

        case .singleTab:
            // Single "Delete Tab" button burning only the target tab
            let title = isSingleChatConfirmation ? UserText.scopedFireConfirmationDeleteThisChatButton : UserText.scopedFireConfirmationDeleteTabButton
            let options: FireRequest.Options = isSingleChatConfirmation ? [.aiChats, .tabs] : [.all]

            return [FireConfirmationButton(title: title,
                               style: .primary,
                               action: { burnTab(tabViewModel: tabViewModel, options: options, source: source, onConfirm: onConfirm) },
                               accessibilityIdentifier: AccessibilityIdentifiers.thisTab)]
        case .default:
            break
        }

        // AI tab + refinements: single "Delete This Chat" (tab-scoped burn)
        if isSingleChatConfirmation {
            return [FireConfirmationButton(title: UserText.scopedFireConfirmationDeleteThisChatButton,
                               style: .primary,
                               action: { burnTab(tabViewModel: tabViewModel, source: source, onConfirm: onConfirm) },
                               accessibilityIdentifier: AccessibilityIdentifiers.thisTab)]
        }

        let deleteAllAction = { burnAll(browsingMode: browsingMode, source: source, onConfirm: onConfirm) }

        // Single non-Duck.ai tab: "Delete This Tab" == "Delete All", so show only "Delete All".
        if showDeleteAllOnlyForSingleTab {
            return [FireConfirmationButton(title: UserText.scopedFireConfirmationDeleteAllButton,
                       style: .primary,
                       action: deleteAllAction,
                       accessibilityIdentifier: AccessibilityIdentifiers.deleteAll)]
        }

        let canBurnTab = tabViewModel?.tab.supportsTabHistory == true

        // Refinements enabled: "Delete This Tab" (primary) then "Delete All" (secondary)
        if isRefinementsEnabled && canBurnTab {
            return [
                FireConfirmationButton(title: UserText.scopedFireConfirmationDeleteThisTabButton,
                           style: .primary,
                           action: { burnTab(tabViewModel: tabViewModel, source: source, onConfirm: onConfirm) },
                           accessibilityIdentifier: AccessibilityIdentifiers.thisTab),
                FireConfirmationButton(title: UserText.scopedFireConfirmationDeleteAllButton,
                           style: .secondary,
                           action: deleteAllAction,
                           accessibilityIdentifier: AccessibilityIdentifiers.deleteAll)
            ]
        }

        // Default: "Delete All" (primary), optionally "Delete This Tab" (secondary)
        var buttons = [FireConfirmationButton(title: UserText.scopedFireConfirmationDeleteAllButton,
                                  style: .primary,
                                  action: deleteAllAction,
                                  accessibilityIdentifier: AccessibilityIdentifiers.deleteAll)]
        if canBurnTab {
            buttons.append(FireConfirmationButton(title: UserText.scopedFireConfirmationDeleteThisTabButton,
                                      style: .secondary,
                                      action: { burnTab(tabViewModel: tabViewModel, source: source, onConfirm: onConfirm) },
                                      accessibilityIdentifier: AccessibilityIdentifiers.thisTab))
        }
        return buttons
    }

    private static func burnAll(browsingMode: BrowsingMode, source: FireRequest.Source, onConfirm: (FireRequest) -> Void) {
        let scope: FireRequest.Scope = browsingMode == .fire ? .fireMode : .all
        let request = FireRequest(options: .all, trigger: .manualFire, scope: scope, source: source)
        onConfirm(request)
    }

    private static func performCustomRequest(source: FireRequest.Source, onConfirm: (FireRequest) -> Void) {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: source)
        onConfirm(request)
    }

    private static func burnTab(tabViewModel: TabViewModel?,
                                options: FireRequest.Options = .all,
                                source: FireRequest.Source,
                                onConfirm: (FireRequest) -> Void) {
        guard let tabViewModel else {
            return
        }
        let request = FireRequest(options: options, trigger: .manualFire, scope: .tab(viewModel: tabViewModel), source: source)
        onConfirm(request)
    }

    // MARK: - Header Title

    private static func computeHeaderTitle(fireContext: FireContext,
                                           isSingleChatConfirmation: Bool,
                                           showDeleteAllOnlyForSingleTab: Bool,
                                           browsingMode: BrowsingMode,
                                           appSettings: AppSettings) -> String {
        switch fireContext {
        case .contextualChat, .duckAIOnboarding:
            return UserText.contextualChatDeleteConfirmationTitle
        case .singleTab:
            return isSingleChatConfirmation
                ? UserText.contextualChatDeleteConfirmationTitle
                : UserText.scopedFireConfirmationAlertSingleTabTitle
        case .custom(let title, _, _):
            return title
        case .deleteAllChats(let count, _):
            return UserText.aiChatHistoryDeleteAllConfirmationTitle(count: count)

        case .default:
            if isSingleChatConfirmation {
                return UserText.contextualChatDeleteConfirmationTitle
            }
            if browsingMode == .fire {
                return UserText.scopedFireConfirmationAlertFireModeTitle
            }
            if showDeleteAllOnlyForSingleTab {
                return UserText.scopedFireConfirmationAlertSingleTabTitle
            }
            return appSettings.autoClearAIChatHistory
                ? UserText.scopedFireConfirmationAlertTitleWithAIChat
                : UserText.scopedFireConfirmationAlertTitle
        }
    }

    // MARK: - Subtitle

    /// Computes the subtitle text for the confirmation dialog.
    ///
    /// The logic follows this priority:
    /// 1. If showing Dax fire dialog (onboarding) → return nil (skip all subtitles)
    /// 2. If there are ongoing downloads → show downloads warning
    /// 3. If no tab view model → return nil (tab switcher/settings)
    /// 4. If tab doesn't support tab history → show new tabs info
    /// 4a. If in fire mode → return nil (skip explanatory subtitles)
    /// 5. For AI tabs → show AI-specific description (up to 2 times)
    /// 6. For normal web tabs → show sign out warning (up to 2 times)
    /// 7. Otherwise → return nil
    private static func computeSubtitle(fireContext: FireContext,
                                        tabViewModel: TabViewModel?,
                                        browsingMode: BrowsingMode,
                                        isSingleChatConfirmation: Bool,
                                        downloadManager: DownloadManaging,
                                        keyValueStore: KeyValueStoring,
                                        appSettings: AppSettings) -> String? {
        switch fireContext {
        case .duckAIOnboarding, .contextualChat, .singleTab:
            return nil
        case .default(let daxDialogsManager) where daxDialogsManager.isShowingFireDialog:
            // Skip all subtitles if in onboarding
            return nil
        case .custom(_, let subtitle, _):
            return subtitle
        case .deleteAllChats:
            return nil
        case .default:
            break
        }

        // Check for ongoing downloads first
        if hasOngoingDownloads(downloadManager: downloadManager) {
            return UserText.scopedFireConfirmationDownloadsWarning
        }

        // No subtitle for tab switcher and settings
        guard let tabViewModel else {
            return nil
        }

        // If tab doesn't support burning, show new tabs info
        guard tabViewModel.tab.supportsTabHistory else {
            return UserText.scopedFireConfirmationNewTabsInfo
        }

        // Skip explanatory subtitles for fire mode
        guard browsingMode != .fire else {
            return nil
        }

        // Check tab type and show count
        if tabViewModel.tab.isAITab {
            return aiTabSubtitle(isSingleChatConfirmation: isSingleChatConfirmation, appSettings: appSettings)
        } else {
            return webTabSubtitle(keyValueStore: keyValueStore)
        }
    }

    private static func hasOngoingDownloads(downloadManager: DownloadManaging) -> Bool {
        let ongoingDownloads = downloadManager.downloadList.filter { $0.isRunning && !$0.temporary }
        return !ongoingDownloads.isEmpty
    }

    private static func webTabSubtitle(keyValueStore: KeyValueStoring) -> String? {
        let showCount = keyValueStore.object(forKey: Keys.signOutWarningShowCount) as? Int ?? 0

        guard showCount < Self.maxSubtitleShowCount else {
            return nil
        }

        keyValueStore.set(showCount + 1, forKey: Keys.signOutWarningShowCount)
        return UserText.scopedFireConfirmationSignOutWarning
    }

    private static func aiTabSubtitle(isSingleChatConfirmation: Bool, appSettings: AppSettings) -> String? {
        if isSingleChatConfirmation { return nil }
        return appSettings.autoClearAIChatHistory ? nil : UserText.scopedFireConfirmationDeleteThisChatDescription
    }
}
