//
//  NewTabPageOmnibarActionHandler.swift
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

final class NewTabPageOmnibarActionHandler: NewTabPageOmnibarActionHandling {

    func openSearch(term: String, target: NewTabPage.NewTabPageDataModel.OpenTarget) {
        guard let mainWindowController = NSApp.delegateTyped.windowControllersManager.lastKeyMainWindowController,
              let searchURL = URL.makeSearchUrl(from: term) else {
            assertionFailure("Failed to open search")
            return
        }

        NewTabPageLinkOpener.open(
            searchURL,
            source: .ui,
            sender: .userScript,
            target: target.linkOpenTarget,
            sourceWindow: mainWindowController.window
        )
    }

    func openSuggestion(_ suggestion: NewTabPageDataModel.Suggestion, target: NewTabPageDataModel.OpenTarget) {
        let windowControllersManager = NSApp.delegateTyped.windowControllersManager
        guard let mainWindowController = windowControllersManager.lastKeyMainWindowController,
                let addressBarTextField = mainWindowController.mainViewController.navigationBarViewController.addressBarViewController?.addressBarTextField else {
            assertionFailure("Failed to open suggestion")
            return
        }

        let appSuggestion = suggestion.toAppSuggestion()

        if case .internalPage(title: _, url: let url, _) = appSuggestion,
           url == .bookmarks || url.isSettingsURL {
            windowControllersManager.show(url: url, tabId: nil, source: .switchToOpenTab, newTab: true)
        } else if case .openTab(_, url: let url, tabId: let tabId, _) = appSuggestion {
            windowControllersManager.show(url: url, tabId: tabId, source: .switchToOpenTab, newTab: true)
        } else {
            addressBarTextField.makeUrl(suggestion: appSuggestion, stringValueWithoutSuffix: "") { suggestionUrl, _, _ in
                guard let suggestionUrl else {
                    assertionFailure("Failed to open suggestion")
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

}

extension NewTabPageDataModel.OpenTarget {

    var linkOpenTarget: LinkOpenTarget {
        switch self {
        case .sameTab:
            return .current
        case .newTab:
            return .newTab
        case .newWindow:
            return .newWindow
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
