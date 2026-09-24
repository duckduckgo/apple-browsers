//
//  BrowserToolPageAccess.swift
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
import Foundation
import WebKit

/// Resolves the tab a page tool acts on: the optional `tabId` argument, defaulting to the owner
/// tab, and always scoped to the owner window.
@MainActor
enum BrowserToolTargetTab {

    enum Resolution: Equatable {
        case resolved(tabID: TabIdentifier, collection: TabCollectionViewModel)
        case failure(BrowserToolFailure)

        static func == (lhs: Resolution, rhs: Resolution) -> Bool {
            switch (lhs, rhs) {
            case (.resolved(let a, let ca), .resolved(let b, let cb)): a == b && ca === cb
            case (.failure(let a), .failure(let b)): a == b
            default: false
            }
        }
    }

    static func resolve(tabIDArgument: JSONValue?,
                        context: BrowserToolCallContext,
                        in windowControllersManager: WindowControllersManagerProtocol) -> Resolution {
        let tabID: TabIdentifier
        switch tabIDArgument {
        case .none, .some(.null):
            tabID = context.ownerTabID
        case .some(.string(let value)):
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            tabID = trimmed.isEmpty ? context.ownerTabID : trimmed
        default:
            return .failure(.invalidArguments)
        }

        guard let token = context.ownerWindowToken,
              let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token,
                                                                           in: windowControllersManager) else {
            return .failure(.unavailable)
        }
        guard collection.indexInAllTabs(where: { $0.uuid == tabID }) != nil else {
            return .failure(.notFound)
        }
        return .resolved(tabID: tabID, collection: collection)
    }

    /// The loaded tab, or nil when it is not a page the tab picker would offer.
    static func attachableTab(withID tabID: TabIdentifier, in collection: TabCollectionViewModel) -> Tab? {
        guard let index = collection.indexInAllTabs(where: { $0.uuid == tabID }),
              let tab = collection.materialize(at: index),
              case .url(let url, _, _) = tab.content,
              !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else {
            return nil
        }
        return tab
    }
}

/// Page text for the read and find tools, behind a seam so the tools are testable without a web view.
@MainActor
protocol BrowserToolPageContentReading: AnyObject {
    func pageContext(forTabID tabID: TabIdentifier, in collection: TabCollectionViewModel) async -> AIChatPageContextData?
}

@MainActor
final class BrowserToolPageContentReader: BrowserToolPageContentReading {

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func pageContext(forTabID tabID: TabIdentifier, in collection: TabCollectionViewModel) async -> AIChatPageContextData? {
        await AIChatUserScriptHandler.extractPageContext(forTabId: tabID, origin: collection, in: windowControllersManager)
    }
}

enum BrowserToolHighlightOutcome: Equatable {
    /// `count` is nil when only the public find API was available, which reports no total.
    case painted(count: UInt?)
    case notFound
    case cancelled
}

/// WebKit's own find, the same one behind Cmd+F: it lights every occurrence of one string.
@MainActor
protocol BrowserToolPageHighlighting: AnyObject {
    func isFindBarVisible(in tab: Tab) -> Bool
    func highlight(_ quote: String, in tab: Tab) async -> BrowserToolHighlightOutcome
}

@MainActor
final class WebViewPageHighlighter: BrowserToolPageHighlighting {

    private static let maxMatches: UInt = 1000

    func isFindBarVisible(in tab: Tab) -> Bool {
        tab.findInPage?.model.isVisible ?? false
    }

    func highlight(_ quote: String, in tab: Tab) async -> BrowserToolHighlightOutcome {
        // Case-sensitive on purpose: the contract defines `quotes` as exact page substrings.
        let result = await tab.webView.find(quote, with: [.showOverlay, .showFindIndicator, .wrapAround], maxCount: Self.maxMatches)
        switch result {
        case .found(let matches): return .painted(count: matches)
        case .notFound: return .notFound
        case .cancelled: return .cancelled
        }
    }
}
