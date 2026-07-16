//
//  AIChatMenu.swift
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
import AppKit
import Common
import FoundationExtensions
import DesignResourcesKitIcons
import OSLog
import PixelKit
import SwiftUI

@MainActor
final class AIChatMenu: NSMenu {

    enum Origin {
        case mainMenu
        case moreOptionsMenu
    }

    // MARK: - Actions

    struct Actions {
        var openNewChat: @MainActor () -> Void
        var openNewVoiceChat: @MainActor () -> Void
        var openNewImageChat: @MainActor () -> Void
        var openChat: @MainActor (AIChatSuggestion) -> Void
        var deleteAllChats: () async -> Void
    }

    // MARK: - Static items

    private lazy var openDuckAIItem: NSMenuItem = {
        let item = NSMenuItem(title: UserText.aiChatMenuOpenDuckAI, action: #selector(openDuckAITapped), keyEquivalent: origin == .mainMenu ? "n" : "")
        if origin == .mainMenu {
            item.keyEquivalentModifierMask = [.option, .command]
        }
        item.target = self
        item.image = DesignSystemImages.Glyphs.Size12.duckAi
        return item
    }()

    private lazy var newChatItem: NSMenuItem = {
        let item = NSMenuItem(title: UserText.aiChatMenuNewChat, action: #selector(newChatTapped), keyEquivalent: "")
        item.target = self
        item.image = DesignSystemImages.Glyphs.Size12.compose
        return item
    }()

    private lazy var newVoiceChatItem: NSMenuItem = {
        // Shortcut on the main menu only — More Options popups don't bind global keys.
        // ⌥⌘V groups with Open Duck.ai's ⌥⌘N under the same modifier family.
        let item = NSMenuItem(title: UserText.aiChatMenuNewVoiceChat, action: #selector(newVoiceChatTapped), keyEquivalent: origin == .mainMenu ? "v" : "")
        if origin == .mainMenu {
            item.keyEquivalentModifierMask = [.option, .command]
        }
        item.target = self
        item.image = DesignSystemImages.Glyphs.Size12.voice
        return item
    }()

    private lazy var newImageChatItem: NSMenuItem = {
        // ⌥⌘G — G for "Generate" image; ⌥⌘I and ⌥⌘C are taken by Web Inspector / JS Console.
        let item = NSMenuItem(title: UserText.aiChatMenuNewImageChat, action: #selector(newImageChatTapped), keyEquivalent: origin == .mainMenu ? "g" : "")
        if origin == .mainMenu {
            item.keyEquivalentModifierMask = [.option, .command]
        }
        item.target = self
        item.image = DesignSystemImages.Glyphs.Size12.images
        return item
    }()

    private lazy var recentChatsLabel: NSMenuItem = {
        let item = NSMenuItem(title: UserText.aiChatMenuRecentChats)
        item.isEnabled = false
        return item
    }()

    private lazy var deleteAllChatsItem: NSMenuItem = {
        let item = NSMenuItem(title: UserText.aiChatMenuDeleteAllChats, action: #selector(deleteAllChatsTapped), keyEquivalent: "")
        item.target = self
        item.image = DesignSystemImages.Glyphs.Size12.fire
        return item
    }()

    // MARK: - Dynamic chat items

    private var chatItems: [NSMenuItem] = []
    private var fetchTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let suggestionsReader: AIChatSuggestionsReading
    private let actions: Actions
    /// When set, limits the number of chat items shown in the menu.
    private let maxChatItems: Int?
    private let origin: Origin

    // MARK: - Init

    init(suggestionsReader: AIChatSuggestionsReading,
         actions: Actions,
         maxChatItems: Int? = nil,
         origin: Origin = .mainMenu) {
        self.suggestionsReader = suggestionsReader
        self.actions = actions
        self.maxChatItems = maxChatItems
        self.origin = origin
        super.init(title: "Duck.ai")
        buildMenu()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu construction

    private func buildMenu() {
        addItem(openDuckAIItem)
        addItem(.separator())
        addItem(newChatItem)
        addItem(newVoiceChatItem)
        addItem(newImageChatItem)
        addItem(.separator())
        addItem(recentChatsLabel)
        // Dynamic chat items are inserted after recentChatsLabel by insertChatItems(_:)
        addItem(.separator())
        addItem(deleteAllChatsItem)
    }

    // MARK: - NSMenu update

    override func update() {
        super.update()
        fetchTask?.cancel()
        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Fetch one extra item to detect whether there are more chats than we display,
            // which determines whether to show "View All Chats...".
            let fetchLimit = maxChatItems.map { $0 + 1 } ?? .max
            let (pinned, recent) = await suggestionsReader.fetchSuggestions(query: nil, maxChats: fetchLimit)
            guard !Task.isCancelled else { return }
            let sorted = (pinned + recent)
                .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            let hasMore = maxChatItems.map { sorted.count > $0 } ?? false
            let visible = maxChatItems.map { Array(sorted.prefix($0)) } ?? sorted
            clearChatItems()
            insertChatItems(visible, hasMore: hasMore)
        }
    }

    // MARK: - Dynamic item management

    private func clearChatItems() {
        chatItems.forEach { removeItem($0) }
        chatItems.removeAll()
    }

    private func insertChatItems(_ chats: [AIChatSuggestion], hasMore: Bool) {
        let labelIndex = index(of: recentChatsLabel)
        guard labelIndex != -1 else { return }
        for (offset, chat) in chats.enumerated() {
            let item = NSMenuItem(title: chat.title, action: #selector(chatItemTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = chat
            item.image = chat.isPinned
            ? (origin == .moreOptionsMenu ? DesignSystemImages.Color.Size16.chatPinned : DesignSystemImages.Color.Size12.chatPinned)
                : (origin == .moreOptionsMenu ? DesignSystemImages.Color.Size16.chat : DesignSystemImages.Color.Size12.chat)
            insertItem(item, at: labelIndex + 1 + offset)
            chatItems.append(item)
        }
        if hasMore {
            let separator = NSMenuItem.separator()
            let viewAllItem = NSMenuItem(title: UserText.aiChatMenuViewAllChats, action: #selector(viewAllChatsTapped), keyEquivalent: "")
            viewAllItem.target = self
            viewAllItem.image = origin == .moreOptionsMenu ? DesignSystemImages.Glyphs.Size16.aiChatHistory : DesignSystemImages.Glyphs.Size12.aiChatHistory
            let insertIndex = labelIndex + 1 + chats.count
            insertItem(separator, at: insertIndex)
            insertItem(viewAllItem, at: insertIndex + 1)
            chatItems.append(separator)
            chatItems.append(viewAllItem)
        }
    }

    // MARK: - Action handlers

    @objc private func openDuckAITapped() {
        actions.openNewChat()
        let pixel: AIChatPixel = origin == .moreOptionsMenu ? .aiChatOpenDuckAiMoreOptionsMenu : .aiChatOpenDuckAiMainMenu
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }

    @objc private func newChatTapped() {
        actions.openNewChat()
        let pixel: AIChatPixel = origin == .moreOptionsMenu ? .aiChatNewChatMoreOptionsMenu : .aiChatNewChatMainMenu
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }

    @objc private func newVoiceChatTapped() {
        actions.openNewVoiceChat()
        let pixel: AIChatPixel = origin == .moreOptionsMenu ? .aiChatNewVoiceChatMoreOptionsMenu : .aiChatNewVoiceChatMainMenu
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }

    @objc private func newImageChatTapped() {
        actions.openNewImageChat()
        let pixel: AIChatPixel = origin == .moreOptionsMenu ? .aiChatNewImageChatMoreOptionsMenu : .aiChatNewImageChatMainMenu
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }

    @objc private func chatItemTapped(_ sender: NSMenuItem) {
        guard let chat = sender.representedObject as? AIChatSuggestion else { return }
        actions.openChat(chat)
        let pixel: AIChatPixel = origin == .moreOptionsMenu ? .aiChatRecentChatSelectedMoreOptionsMenu : .aiChatRecentChatSelectedMainMenu
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }

    @objc private func viewAllChatsTapped() {
        actions.openNewChat()
        let pixel: AIChatPixel = origin == .moreOptionsMenu ? .aiChatViewAllChatsMoreOptionsMenu : .aiChatViewAllChatsMainMenu
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
    }

    @objc private func deleteAllChatsTapped() {
        var dialog = AIChatDeleteChatsDialog()
        let actions = self.actions
        let origin = self.origin
        dialog.confirmed = {
            let pixel: AIChatPixel = origin == .moreOptionsMenu ? .aiChatDeleteAllChatsMoreOptionsMenu : .aiChatDeleteAllChatsMainMenu
            PixelKit.fire(pixel, frequency: .dailyAndStandard)
            PixelKit.fire(FireButtonPixel.fireStarted, frequency: .dailyAndCount, doNotEnforcePrefix: true)
            PixelKit.fire(FireButtonPixel.fireStartedInSession, frequency: .dailyAndCount, doNotEnforcePrefix: true)
            PixelKit.fire(FireButtonPixel.burn(.aiChats), frequency: .dailyAndCount, doNotEnforcePrefix: true)
            Task { @MainActor in
                await actions.deleteAllChats()
            }
        }
        dialog.show()
    }
}

// MARK: - Default actions factory

extension AIChatMenu.Actions {

    @MainActor
    static func makeDefault(
        remoteSettings: AIChatRemoteSettings,
        tabOpener: AIChatTabOpening,
        historyCleaner: AIChatHistoryCleaning,
        windowControllersManager: WindowControllersManagerProtocol,
        aiChatSyncCleaner: @escaping () -> AIChatSyncCleaning?
    ) -> AIChatMenu.Actions {
        AIChatMenu.Actions(
            openNewChat: {
                tabOpener.openAIChatTab(with: .newChat, behavior: .newTab(selected: true))
            },
            openNewVoiceChat: {
                let sourceCollection = windowControllersManager.lastKeyMainWindowController?
                    .mainViewController.tabCollectionViewModel
                tabOpener.openVoiceSession(inSourceCollection: sourceCollection, behavior: .newTab(selected: true))
            },
            openNewImageChat: {
                let url = AIChatURLParameters.imageModeURL(from: remoteSettings.aiChatURL)
                tabOpener.openAIChatTab(with: .url(url), behavior: .newTab(selected: true))
            },
            openChat: { suggestion in
                tabOpener.openAIChatTab(with: .existingChat(chatId: suggestion.chatId), behavior: .currentTab)
            },
            deleteAllChats: {
                if case .failure(let error) = await historyCleaner.cleanAIChatHistory() {
                    Logger.aiChat.error("Failed to delete all Duck.ai chats: \(error.localizedDescription)")
                    return
                }
                await aiChatSyncCleaner()?.recordLocalClear(date: Date())
                for windowController in windowControllersManager.mainWindowControllers {
                    for tab in windowController.mainViewController.tabCollectionViewModel.tabs where tab.url?.isDuckAIURL == true {
                        tab.reload()
                    }
                }
            }
        )
    }
}
