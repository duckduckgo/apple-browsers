//
//  SuggestionViewModel.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Cocoa
import Common
import Suggestions

struct SuggestionViewModel {
    let isHomePage: Bool
    let suggestion: Suggestion
    let userStringValue: String
    let suggestionIcons: SuggestionsIconsProviding

    init(isHomePage: Bool,
         suggestion: Suggestion,
         userStringValue: String,
         visualStyle: VisualStyleProviding) {
        self.isHomePage = isHomePage
        self.suggestion = suggestion
        self.userStringValue = userStringValue

        let fontSize = isHomePage ? visualStyle.addressBarStyleProvider.newTabOrHomePageAddressBarFontSize : visualStyle.addressBarStyleProvider.defaultAddressBarFontSize
        self.tableRowViewStandardAttributes = Self.rowViewStandardAttributes(size: fontSize, isBold: false)
        self.tableRowViewBoldAttributes = Self.rowViewStandardAttributes(size: fontSize, isBold: true)
        self.suggestionIcons = visualStyle.iconsProvider.suggestionsIconsProvider
    }

    // MARK: - Attributed Strings

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private static func rowViewStandardAttributes(size: CGFloat, isBold: Bool) -> [NSAttributedString.Key: Any] {
        if isBold {
            return [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: size, weight: .bold),
                .paragraphStyle: Self.paragraphStyle
            ]
        } else {
            return [
                .font: NSFont.systemFont(ofSize: size, weight: .regular),
                .paragraphStyle: Self.paragraphStyle
            ]
        }
    }

    var tableRowViewStandardAttributes: [NSAttributedString.Key: Any]
    var tableRowViewBoldAttributes: [NSAttributedString.Key: Any]

    var tableCellViewAttributedString: NSAttributedString {
        var firstPart = ""
        var boldPart = string
        if string.hasPrefix(userStringValue) {
            firstPart = String(string.prefix(userStringValue.count))
            boldPart = String(string.dropFirst(userStringValue.count))
        }

        let attributedString = NSMutableAttributedString(string: firstPart, attributes: tableRowViewStandardAttributes)
        let boldAttributedString = NSAttributedString(string: boldPart, attributes: tableRowViewBoldAttributes)
        attributedString.append(boldAttributedString)

        return attributedString
    }

    var string: String {
        switch suggestion {
        case .phrase(phrase: let phrase):
            return phrase
        case .website(url: let url):
            return url.toString(forUserInput: userStringValue)
        case .historyEntry(title: let title, url: let url, _):
            if url.isDuckDuckGoSearch {
                return url.searchQuery ?? url.toString(forUserInput: userStringValue)
            } else {
                return title ?? url.toString(forUserInput: userStringValue)
            }
        case .bookmark(title: let title, url: _, isFavorite: _, _),
             .internalPage(title: let title, url: _, _),
             .openTab(title: let title, url: _, _, _):
            return title
        case .unknown(value: let value), .askAIChat(let value):
            return value
        }
    }

    var title: String? {
        switch suggestion {
        case .phrase,
             .website,
             .unknown,
             .askAIChat:
            return nil
        case .historyEntry(title: let title, url: let url, _):
            if url.isDuckDuckGoSearch {
                return url.searchQuery
            } else {
                return title
            }
        case .bookmark(title: let title, url: _, isFavorite: _, _),
             .internalPage(title: let title, url: _, _),
             .openTab(title: let title, url: _, _, _):
            return title
        }
    }

    var autocompletionString: String {
        switch suggestion {
        case .historyEntry(title: _, url: let url, _),
             .bookmark(title: _, url: let url, isFavorite: _, _):

            let userStringValue = self.userStringValue.lowercased()
            let urlString = url.toString(forUserInput: userStringValue)
            if !urlString.hasPrefix(userStringValue),
               let title = self.title,
               title.lowercased().hasPrefix(userStringValue) {
                return title
            }

            return urlString

        default:
            return self.string
        }
    }

    var suffix: String? {
        switch suggestion {
        // for punycoded urls display real url as a suffix
        case .website(url: let url) where url.toString(forUserInput: userStringValue, decodePunycode: false) != self.string:
            return url.toString(decodePunycode: false, dropScheme: true, dropTrailingSlash: true)

        case .phrase, .unknown, .website, .askAIChat:
            return nil
        case .openTab(title: _, url: let url, _, _) where url.isDuckURLScheme:
            return UserText.duckDuckGo
        case .openTab(title: _, url: let url, _, _) where url.isDuckDuckGoSearch:
            return UserText.duckDuckGoSearchSuffix
        case .historyEntry(title: _, url: let url, _),
             .bookmark(title: _, url: let url, isFavorite: _, _),
             .openTab(title: _, url: let url, _, _):
            if url.isDuckDuckGoSearch {
                return UserText.searchDuckDuckGoSuffix
            } else {
                return url.toString(decodePunycode: true, dropScheme: true, needsWWW: false, dropTrailingSlash: true)
            }
        case .internalPage:
            return UserText.duckDuckGo
        }
    }

    // MARK: - Icon

    var icon: NSImage? {
        switch suggestion {
        case .phrase:
            return suggestionIcons.phraseEntryIcon
        case .website:
            return suggestionIcons.websiteEntryIcon
        case .historyEntry:
            return suggestionIcons.historyEntryIcon
        case .bookmark(title: _, url: _, isFavorite: false, _):
            return suggestionIcons.bookmarkEntryIcon
        case .bookmark(title: _, url: _, isFavorite: true, _):
            return suggestionIcons.favoriteEntryIcon
        case .unknown, .askAIChat:
            return suggestionIcons.unknownEntryIcon
        case .internalPage(title: _, url: let url, _) where url == .bookmarks,
             .openTab(title: _, url: let url, _, _) where url == .bookmarks:
            return suggestionIcons.folderEntryIcon
        case .internalPage(title: _, url: let url, _) where url.isSettingsURL,
             .openTab(title: _, url: let url, _, _) where url.isSettingsURL:
            return suggestionIcons.settingsEntryIcon
        case .internalPage(title: _, url: let url, _) where url.isHistory,
             .openTab(title: _, url: let url, _, _) where url.isHistory:
            return suggestionIcons.historyEntryIcon
        case .internalPage(title: _, url: let url, _):
            guard url == URL(string: NSApp.delegateTyped.startupPreferences.formattedCustomHomePageURL) else { return nil }
            return suggestionIcons.homeEntryIcon
        case .openTab:
            return suggestionIcons.openTabEntryIcon
        }
    }

}

extension SuggestionViewModel: Equatable {
    static func == (lhs: SuggestionViewModel, rhs: SuggestionViewModel) -> Bool {
        return lhs.isHomePage == rhs.isHomePage && lhs.suggestion == rhs.suggestion && lhs.userStringValue == rhs.userStringValue
    }
}
