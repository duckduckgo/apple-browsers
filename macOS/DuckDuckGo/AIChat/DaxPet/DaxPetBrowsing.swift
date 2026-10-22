//
//  DaxPetBrowsing.swift
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

import AppKit
import History

/// An open tab Dax can bring forward.
struct DaxPetTab: Equatable, Identifiable {
    let id: String
    let title: String
    let url: URL
    var favicon: NSImage?
}

/// A page from the browsing history, at its latest visit.
struct DaxPetVisit: Equatable {
    let title: String
    let url: URL
    let date: Date
}

/// The user's tabs and history, read on the Mac for Dax's quick lookups. Fire Windows are left out.
@MainActor
protocol DaxPetBrowsing {
    var openTabs: [DaxPetTab] { get }
    func switchTo(_ tab: DaxPetTab)
    /// Pages whose title or address has any of `terms`, the most matching and most recent first.
    func history(matching terms: [String], limit: Int) -> [DaxPetVisit]
    func open(_ url: URL)
}

@MainActor
final class DaxPetBrowser: DaxPetBrowsing {

    private let windowControllersManager: WindowControllersManagerProtocol
    private let historyCoordinator: HistoryCoordinating

    init(windowControllersManager: WindowControllersManagerProtocol, historyCoordinator: HistoryCoordinating) {
        self.windowControllersManager = windowControllersManager
        self.historyCoordinator = historyCoordinator
    }

    var openTabs: [DaxPetTab] {
        var seen = Set<String>()
        return windowControllersManager.allTabCollectionViewModels
            .filter { !$0.isBurner }
            .flatMap { ($0.pinnedTabsCollection?.tabs ?? []) + $0.tabCollection.tabs }
            .compactMap { tab -> DaxPetTab? in
                guard case .url(let url, _, _) = tab.content, !url.isDuckAIURL, seen.insert(tab.uuid).inserted else { return nil }
                return DaxPetTab(id: tab.uuid, title: tab.title ?? url.host ?? url.absoluteString, url: url, favicon: tab.favicon)
            }
    }

    func switchTo(_ tab: DaxPetTab) {
        windowControllersManager.show(url: tab.url, tabId: tab.id, source: .switchToOpenTab, newTab: true, selected: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    func history(matching terms: [String], limit: Int) -> [DaxPetVisit] {
        Self.rank(historyCoordinator.allHistoryVisits ?? [], matching: terms, limit: limit)
    }

    func open(_ url: URL) {
        windowControllersManager.show(url: url, tabId: nil, source: .historyEntry, newTab: true, selected: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// One row per page, at its latest visit; pages matching more of the terms come first, then the newest.
    static func rank(_ visits: [Visit], matching terms: [String], limit: Int) -> [DaxPetVisit] {
        let terms = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        var best: [URL: (visit: DaxPetVisit, score: Int)] = [:]
        for visit in visits {
            guard let entry = visit.historyEntry else { continue }
            let haystack = (entry.title ?? "") + " " + entry.url.absoluteString
            let score = terms.filter { mentions(haystack, $0) }.count
            guard score > 0 else { continue }
            if let existing = best[entry.url], existing.visit.date >= visit.date { continue }
            let title = SearchHistoryBrowserTool.displayTitle(title: entry.title, url: entry.url)
            best[entry.url] = (DaxPetVisit(title: title, url: entry.url, date: visit.date), score)
        }
        return best.values
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.visit.date > $1.visit.date }
            .prefix(limit)
            .map(\.visit)
    }

    /// Whether `text` has every word of `term`, in any order, ignoring case and accents.
    static func mentions(_ text: String, _ term: String) -> Bool {
        let words = term.split(whereSeparator: { $0.isWhitespace })
        return !words.isEmpty && words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
