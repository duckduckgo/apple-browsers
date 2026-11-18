//
//  MainViewController+DuckAIMenu.swift
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
import FeatureFlags_iOS
import UIKit

extension MainViewController {
    private static let mainMenuRecentChatsLimit = 8

    /// Recent Chats and Delete All Chats read the storage of the browsing mode the menu opened in.
    func isMenuChatCommandAvailable(_ command: UICommand?) -> Bool {
        switch command?.action {
        case MainMenuCommand.openRecentChat.action: return command?.propertyList is String
        case MainMenuCommand.deleteAllChats.action: return (command?.propertyList as? String).flatMap(Int.init) ?? 0 > 0
        default: return true
        }
    }

    func mainMenuRecentChats() async -> DuckAIRecentChatsMenuContent.Chats {
        guard aiChatSettings.isAIChatEnabled else { return .init(recentChats: [], totalChatCount: 0) }
        let chats = await mainMenuNativeChats(isFireMode: menuBrowsingMode == .fire) ?? []
        let aiChatURL = aiChatSettings.aiChatURL
        let recentChats = chats.sorted { $0.lastEdit > $1.lastEdit }
            .prefix(Self.mainMenuRecentChatsLimit)
            .map { DuckAIRecentChatsMenuContent.Chat(title: $0.title, url: aiChatURL.withChatID($0.chatId)) }
        return .init(recentChats: Array(recentChats), totalChatCount: chats.count)
    }

    /// The mode of the tab switcher's selected grid while it is open, which can differ from the current tab's.
    private var menuBrowsingMode: BrowsingMode {
        tabSwitcherController?.selectedBrowsingMode ?? tabManager.currentBrowsingMode
    }

    /// `nil` when native chat storage is unavailable for that browsing mode.
    private func mainMenuNativeChats(isFireMode: Bool) async -> [DuckAiChat]? {
        let storageHandler = isFireMode ? duckAiFireModeStorageHandler : duckAiNativeStorageHandler
        guard featureFlagger.isFeatureOn(.aiChatNativeStorage),
              let observer = storageHandler as? DuckAiNativeChatsObserving else { return nil }
        return await ChatHistoryReader(observer: observer).chatsPublisher().firstValue(within: .seconds(1))
    }

    /// The menu bar reports the browsing menu's entry sources for the page it opens from.
    private var menuBarDuckAIEntrySource: AIChatEntryPointSource {
        guard let tab = tabManager.currentTabsModel.currentTab else { return .browsingMenuNTP }
        if tab.isAITab { return .browsingMenuDuckAI }
        return tab.link == nil ? .browsingMenuNTP : .browsingMenuWebpage
    }

    @objc func menuOpenDuckAI() {
        guard menuCommandAvailability.isEnabled(.openDuckAI) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            openAIChat(source: menuBarDuckAIEntrySource, forcesNewTab: true)
        }
    }

    @objc func menuNewChat() {
        guard menuCommandAvailability.isEnabled(.newChat) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            if let tab = currentTab, tab.isAITab {
                openNewChatFromDuckAIPage(tab, source: .browsingMenuDuckAI)
            } else {
                let source = menuBarDuckAIEntrySource
                newTab(allowingKeyboard: false, startsNewTabPageSessionVisit: false)
                openAIChat(source: source, reportsNewTab: true)
            }
        }
    }

    @objc func menuNewVoiceChat() {
        guard menuCommandAvailability.isEnabled(.newVoiceChat) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            startDuckAIVoiceMode(from: .menuBar, entrySource: menuBarDuckAIEntrySource, opensNewTabOverContent: true)
        }
    }

    @objc func menuNewImageChat() {
        guard menuCommandAvailability.isEnabled(.newImageChat) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            let source = fireAIChatEntryPointPixel(source: menuBarDuckAIEntrySource, opensNewTab: true, hasPrompt: false)
            loadUrlInNewTab(AIChatURLParameters.imageModeURL(from: aiChatSettings.aiChatURL), inheritedAttribution: nil) {
                $0.duckAIEntrySource = source
            }
        }
    }

    @objc func menuOpenRecentChat(_ command: UICommand) {
        guard menuCommandAvailability.isEnabled(.openRecentChat),
              let urlString = command.propertyList as? String, let url = URL(string: urlString) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self, !selectOpenChatTab(for: url) else { return }
            guard currentTab?.tabModel.link != nil else {
                onChatHistorySelected(url: url)
                return
            }
            // Chat history loads in place over a chat or, without unified input, a website; the menu keeps the page like its other items.
            postIdleSessionInstrumentation.sessionEnded(reason: .chatSelected)
            let source = fireAIChatEntryPointPixel(source: .chatHistoryOpenChat, opensNewTab: true, hasPrompt: false)
            loadUrlInNewTab(url, inheritedAttribution: nil) { $0.duckAIEntrySource = source }
        }
    }

    /// Selects the tab already showing the chat, as a Duck.ai tab or in its sidebar, if there is one.
    private func selectOpenChatTab(for url: URL) -> Bool {
        guard let chatID = url.duckAIChatID else { return false }
        let tabs = tabManager.currentTabsModel.tabs
        if let chatTab = tabs.first(where: { $0.isAITab && $0.link?.url.duckAIChatID == chatID }) {
            selectChatTab(chatTab, source: .chatHistoryOpenChat)
            return true
        }
        guard let sidebarTab = tabs.first(where: { $0.contextualChatURL.flatMap(URL.init(string:))?.duckAIChatID == chatID })
        else { return false }
        selectChatTab(sidebarTab, source: .contextualChat)
        // An open sidebar comes back with its tab; a closed one reopens on the chat its tab kept.
        if let controller = tabManager.controller(for: sidebarTab),
           !controller.aiChatContextualSheetCoordinator.isSheetPresented,
           !controller.aiChatContextualSheetCoordinator.hasParkedSurface {
            controller.presentContextualAIChatSheet(from: self)
        }
        return true
    }

    private func selectChatTab(_ chatTab: Tab, source: AIChatEntryPointSource) {
        guard chatTab !== tabManager.currentTabsModel.currentTab else { return }
        performCancel()
        selectTab(chatTab)
        postIdleSessionInstrumentation.sessionEnded(reason: .tabSelected)
        fireAIChatEntryPointPixel(source: source, opensNewTab: false, hasPrompt: false)
        // This tab was shown before the entry started, so report it again for the entry.
        reportDuckAISessionCurrentTab()
    }

    @objc func menuDeleteAllChats(_ command: UICommand) {
        guard menuCommandAvailability.isEnabled(.deleteAllChats) else { return }
        let isFireMode = menuBrowsingMode == .fire
        dismissMenuPresentation { [weak self] in
            Task { @MainActor [weak self] in
                // Recounted because chats may have changed since the menu opened.
                guard let chatCount = await self?.mainMenuNativeChats(isFireMode: isFireMode)?.count, chatCount > 0 else { return }
                self?.presentDeleteAllChatsConfirmation(chatCount: chatCount, isFireMode: isFireMode)
            }
        }
    }

    private func presentDeleteAllChatsConfirmation(chatCount: Int, isFireMode: Bool) {
        FireConfirmationPresenter().presentFireConfirmation(
            on: self,
            attachPopoverTo: view,
            prefersSheet: true,
            tabViewModel: nil,
            pixelSource: .browsing,
            fireContext: .deleteChats(count: chatCount, onDelete: { [weak self] in
                self?.dismiss(animated: true) { self?.burnAllChats(isFireMode: isFireMode) }
            }),
            browsingMode: isFireMode ? .fire : .normal,
            onConfirm: { _ in },
            onCancel: {}
        )
    }

    private func burnAllChats(isFireMode: Bool) {
        let fireExecutor = self.fireExecutor
        fireButtonAnimator.animate { [weak self] in
            guard case .success = await fireExecutor.burnAllChats(isFireMode: isFireMode) else { return }
            self?.reloadOpenChats(isFireMode: isFireMode)
            guard !isFireMode else { return }
            // Flushes the deletion to sync so the chats aren't pulled back.
            fireExecutor.scheduleSync()
        } onTransitionCompleted: {
        } completion: {
        }
    }

    /// Reloads loaded Duck.ai tabs and Duck.ai sidebars so they stop showing deleted chats.
    private func reloadOpenChats(isFireMode: Bool) {
        for tab in tabManager.tabsModel(for: isFireMode ? .fire : .normal).tabs {
            guard let controller = tabManager.controller(for: tab) else { continue }
            controller.reloadFullModeAIChatIfNeeded()
            controller.reloadContextualAIChatIfNeeded()
        }
    }
}
