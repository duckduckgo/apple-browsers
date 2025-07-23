//
//  NewTabPageOmnibarActionsHandler.swift
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

import NewTabPage
import AppKit
import Suggestions
import Common
import AIChat
import os.log
import PixelKit

final class NewTabPageOmnibarActionsHandler: NewTabPageOmnibarActionsHandling {

    private let promptHandler: AIChatPromptHandler
    private let windowControllersManager: WindowControllersManagerProtocol
    private let tabsPreferences: TabsPreferences
    private let isShiftPressed: () -> Bool
    private let isCommandPressed: () -> Bool
    private let firePixel: (PixelKitEvent) -> Void

    init(promptHandler: AIChatPromptHandler = AIChatPromptHandler.shared,
         windowControllersManager: WindowControllersManagerProtocol,
         tabsPreferences: TabsPreferences,
         isShiftPressed: @escaping () -> Bool = { NSApp?.isShiftPressed ?? false },
         isCommandPressed: @escaping () -> Bool = { NSApp?.isCommandPressed ?? false },
         firePixel: @escaping (PixelKitEvent) -> Void = { PixelKit.fire($0, frequency: .dailyAndStandard) }) {
        self.promptHandler = promptHandler
        self.windowControllersManager = windowControllersManager
        self.tabsPreferences = tabsPreferences
        self.isShiftPressed = isShiftPressed
        self.isCommandPressed = isCommandPressed
        self.firePixel = firePixel
    }

    func submitSearch(_ term: String, target: NewTabPage.NewTabPageDataModel.OpenTarget) {
        // Check for the keyboard shortcut to open the chat
        if isShiftPressed() {
            submitChat(term, target: isCommandPressed() ? .newTab : .sameTab)
            return
        }

        firePixel(NewTabPagePixel.searchSubmitted)

        guard let mainWindowController = windowControllersManager.lastKeyMainWindowController else {
            Logger.newTabPageOmnibar.error("Failed to get mainWindowController in submitSearch")
            return
        }

        guard let url = URL.makeURL(from: term) else {
            Logger.newTabPageOmnibar.error("Failed to create URL from term: \(term)")
            return
        }

        NewTabPageLinkOpener.open(
            url,
            source: .ui,
            sender: .userScript,
            target: target.linkOpenTarget,
            sourceWindow: mainWindowController.window
        )
    }

    func openSuggestion(_ suggestion: NewTabPageDataModel.Suggestion, target: NewTabPageDataModel.OpenTarget) {
        guard let mainWindowController = windowControllersManager.lastKeyMainWindowController else {
            Logger.newTabPageOmnibar.error("Failed to get mainWindowController")
            return
        }

        let appSuggestion = suggestion.toAppSuggestion()

        if let autocompletePixel = appSuggestion.autocompletePixel(from: .ntpSearchBox) {
            firePixel(autocompletePixel)
        }

        if case .internalPage(title: _, url: let url, _) = appSuggestion,
           url == .bookmarks || url.isSettingsURL {
            windowControllersManager.show(url: url,
                                          tabId: nil,
                                          source: .switchToOpenTab,
                                          newTab: true,
                                          selected: nil)
        } else if case .openTab(_, url: let url, tabId: let tabId, _) = appSuggestion {
            windowControllersManager.show(url: url,
                                          tabId: tabId,
                                          source: .switchToOpenTab,
                                          newTab: true,
                                          selected: nil)
        } else {
            URL.makeUrl(suggestion: appSuggestion, stringValueWithoutSuffix: "") { suggestionUrl, _, _ in
                guard let suggestionUrl else {
                    Logger.newTabPageOmnibar.error("Failed to convert suggestion to URL")
                    return
                }
                NewTabPageLinkOpener.open(
                    suggestionUrl,
                    source: .ui,
                    sender: .userScript,
                    target: target.linkOpenTarget,
                    sourceWindow: mainWindowController.window
                )
            }
        }
    }

    func submitChat(_ chat: String, target: NewTabPage.NewTabPageDataModel.OpenTarget) {
        firePixel(NewTabPagePixel.promptSubmitted)

        let nativePrompt = AIChatNativePrompt.queryPrompt(chat, autoSubmit: true)

        promptHandler.setData(nativePrompt)

        let tabOpener = AIChatTabOpener(
            promptHandler: promptHandler,
            addressBarQueryExtractor: AIChatAddressBarPromptExtractor(),
            windowControllersManager: windowControllersManager
        )

        var behavior = linkOpenBehavior(for: target, using: tabsPreferences)
        // Check for keyboard modifiers opening on a new tab
        if isCommandPressed() {
            behavior = .newTab(selected: isShiftPressed())
        }

        tabOpener.openAIChatTab(chat, with: behavior)
    }

    private func linkOpenBehavior(for target: NewTabPageDataModel.OpenTarget, using tabsPreferences: TabsPreferences) -> LinkOpenBehavior {
        switch target {
        case .sameTab:
            return .currentTab
        case .newTab:
            return .newTab(selected: tabsPreferences.switchToNewTabWhenOpened)
        case .newWindow:
            return .newWindow(selected: tabsPreferences.switchToNewTabWhenOpened)
        }
    }

}

extension NewTabPageDataModel.Suggestion {

    func toAppSuggestion() -> Suggestion {
        switch self {
        case .phrase(let phrase):
            return .phrase(phrase: phrase)

        case .website(let urlString):
            guard let url = URL(string: urlString) else {
                return .unknown(value: urlString)
            }
            return .website(url: url)

        case .bookmark(let title, let urlString, let isFavorite, let score):
            guard let url = URL(string: urlString) else {
                return .unknown(value: urlString)
            }
            return .bookmark(title: title, url: url, isFavorite: isFavorite, score: score)

        case .historyEntry(let title, let urlString, let score):
            guard let url = URL(string: urlString) else {
                return .unknown(value: urlString)
            }
            return .historyEntry(title: title, url: url, score: score)

        case .internalPage(let title, let urlString, let score):
            guard let url = URL(string: urlString) else {
                return .unknown(value: urlString)
            }
            return .internalPage(title: title, url: url, score: score)

        case .openTab(let title, let tabId, let score):
            return .openTab(title: title, url: URL.empty, tabId: tabId, score: score)
        }
    }
}
