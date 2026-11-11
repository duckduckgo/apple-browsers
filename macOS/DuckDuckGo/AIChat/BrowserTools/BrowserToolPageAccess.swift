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

    static func isListed(_ tab: AnyTab) -> Bool {
        // Web pages only: a file URL names a local path that can include the user's name.
        guard case .url(let url, _, _) = tab.content, url.isHttpOrHttps else { return false }
        return !url.isDuckAIURL
    }

    static func actionableTab(withID tabID: TabIdentifier, ownerTabID: TabIdentifier, in collection: TabCollectionViewModel) -> AnyTab? {
        let tab: AnyTab? = switch collection.indexInAllTabs(where: { $0.uuid == tabID }) {
        case .pinned(let index): collection.pinnedTabsCollection?.tabs[safe: index]
        case .unpinned(let index): collection.tabCollection.tabs[safe: index]
        case .none: nil
        }
        guard let tab, tab.uuid == ownerTabID || isListed(tab) else { return nil }
        return tab
    }

    static func actionableTabs(withIDs tabIDs: [TabIdentifier]?, ownerTabID: TabIdentifier, in collection: TabCollectionViewModel) -> [AnyTab]? {
        var unique: [TabIdentifier] = []
        for tabID in tabIDs ?? [ownerTabID] where !unique.contains(tabID) { unique.append(tabID) }
        let tabs = unique.compactMap { actionableTab(withID: $0, ownerTabID: ownerTabID, in: collection) }
        return tabs.count == unique.count ? tabs : nil
    }

    static func tabIDs(from arguments: JSONValue?, maxCount: Int = 50) -> TabIDsArgument {
        guard let value = arguments?["tabIds"] else { return .absent }
        guard let values = value.arrayValue, (1...maxCount).contains(values.count) else { return .invalid }
        let tabIDs = values.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return tabIDs.count == values.count ? .ids(tabIDs) : .invalid
    }

    enum TabIDsArgument: Equatable {
        case absent
        case ids([TabIdentifier])
        case invalid
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

/// Field limits from the client-tools contract, applied at the browser-tools boundary only.
enum BrowserToolOutputLimits {
    static let title = 256
    static let url = 1280
    static let content = 3000
    static let snippet = 100
    static let query = 1000

    /// JSON Schema `maxLength` counts code points, so this cuts by Unicode scalar.
    static func clip(_ value: String, to limit: Int) -> String {
        guard value.unicodeScalars.count > limit else { return value }
        return String(String.UnicodeScalarView(value.unicodeScalars.prefix(limit)))
    }

    /// Clips a string value and leaves anything else untouched.
    static func clip(_ value: JSONValue?, to limit: Int) -> JSONValue? {
        guard case .string(let text)? = value else { return value }
        return .string(clip(text, to: limit))
    }

    static func fits(_ value: String, within limit: Int) -> Bool {
        value.unicodeScalars.count <= limit
    }

    // Userinfo, query and fragment can hold credentials or tokens.
    static func redactedURL(_ url: String) -> String {
        var redacted = String(url[..<(url.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? url.endIndex)])
        if let scheme = redacted.range(of: "://") {
            let authorityEnd = redacted[scheme.upperBound...].firstIndex(of: "/") ?? redacted.endIndex
            if let at = redacted[scheme.upperBound..<authorityEnd].lastIndex(of: "@") {
                redacted.removeSubrange(scheme.upperBound...at)
            }
        }
        return clip(redacted, to: self.url)
    }

    static func redactedURL(_ value: JSONValue?) -> JSONValue? {
        guard case .string(let text)? = value else { return value }
        return .string(redactedURL(text))
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
        // Same two-step sequence as the find bar: a cold search with the overlay does not reliably
        // paint. The first pass only reports the next match; the overlay pass reports the total.
        // Each await yields the main actor, so the user can open Cmd+F mid-sequence; from then on the
        // overlay is theirs and we stop touching it.
        let webView = tab.webView
        guard !Task.isCancelled, !isFindBarVisible(in: tab) else { return .cancelled }
        let result = await webView.find(quote, with: [.showFindIndicator, .wrapAround], maxCount: Self.maxMatches)
        guard !Task.isCancelled else {
            if !isFindBarVisible(in: tab) {
                webView.clearFindInPageState()
            }
            return .cancelled
        }
        guard !isFindBarVisible(in: tab) else { return .cancelled }
        let firstMatches: UInt?
        switch result {
        case .found(let matches):
            firstMatches = matches
        case .notFound:
            webView.clearFindInPageState()
            return .notFound
        case .cancelled:
            return .cancelled
        }

        webView.clearFindInPageState()
        let overlay = await webView.find(quote, with: [.noIndexChange, .showOverlay, .showFindIndicator, .wrapAround], maxCount: Self.maxMatches)
        guard !Task.isCancelled else {
            if !isFindBarVisible(in: tab) {
                webView.clearFindInPageState()
            }
            return .cancelled
        }
        guard !isFindBarVisible(in: tab) else { return .cancelled }
        switch overlay {
        case .found(let total):
            return .painted(count: total ?? firstMatches)
        case .notFound:
            webView.clearFindInPageState()
            return .notFound
        case .cancelled:
            return .cancelled
        }
    }
}
