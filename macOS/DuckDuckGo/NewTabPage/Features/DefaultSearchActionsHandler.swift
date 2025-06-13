//
//  DefaultSearchActionsHandler.swift
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

import AppKit
import Combine
import Common
import Foundation
import NewTabPage
import Suggestions
import AIChat

extension NewTabPageDataModel.Suggestion {
    var suggestion: Suggestion? {
        switch self {
        case .phrase(phrase: let phrase):
            return .phrase(phrase: phrase)
        case .website(url: let urlString):
            guard let url = urlString.url else {
                return nil
            }
            return .website(url: url)
        case .bookmark(title: let title, url: let urlString, isFavorite: let isFavorite, score: let score):
            guard let url = urlString.url else {
                return nil
            }
            return .bookmark(title: title, url: url, isFavorite: isFavorite, score: score)
        case .historyEntry(title: let title, url: let urlString, score: let score):
            guard let url = urlString.url else {
                return nil
            }
            return .historyEntry(title: title, url: url, score: score)
        case .internalPage(title: let title, url: let urlString, score: let score):
            guard let url = urlString.url else {
                return nil
            }
            return .internalPage(title: title, url: url, score: score)
        case .openTab(title: let title, url: let urlString, tabId: let tabId, score: let score):
            guard let url = urlString.url else {
                return nil
            }
            return .openTab(title: title, url: url, tabId: tabId, score: score)
        }
    }
}

final class DefaultSearchActionsHandler: NewTabPageSearchActionsHandling {

    func open(_ suggestion: NewTabPageDataModel.Suggestion) async throws {
        NSApp.delegateTyped.windowControllersManager
            .lastKeyMainWindowController?
            .mainViewController
            .navigationBarViewController
            .addressBarViewController?
            .addressBarTextField
            .navigate(suggestion: suggestion.suggestion)
    }
}

final class DefaultPromptctionsHandler: NewTabPagePromptActionsHandling {

    func open(_ prompt: String) async throws {
        let nativePrompt: AIChatNativePrompt = .queryPrompt(prompt, autoSubmit: true)
        let promptHandler = AIChatPromptHandler.shared
        promptHandler.setData(nativePrompt)

        let tabOpener = AIChatTabOpener(promptHandler: promptHandler, addressBarQueryExtractor: AIChatAddressBarPromptExtractor())
        tabOpener.openAIChatTab()
    }
}


