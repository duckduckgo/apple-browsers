//
//  TabViewModel.swift
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

import Core
import History
import os.log

@MainActor
struct TabViewModel {
    
    // MARK: - Variables
    
    private(set) var tab: Tab
    private let historyCapture: HistoryCapture
    private let historyManager: HistoryManaging
    
    // MARK: - Init
    
    init(tab: Tab, historyManager: HistoryManaging) {
        self.tab = tab
        self.historyManager = historyManager
        let tabID = tab.supportsTabHistory ? tab.uid : nil // Only record tab history if the tab supports it
        self.historyCapture = .init(historyManager: historyManager, tabID: tabID)
    }

    // MARK: - History Capturing Methods
    
    func captureWebviewDidCommit(_ url: URL) {
        historyCapture.webViewDidCommit(url: url)

    }
    
    func captureTitleDidChange(_ title: String?, for url: URL) {
        historyCapture.titleDidChange(title, forURL: url)
    }
    
    // MARK: - Tab History
    
    func tabHistory() async -> [URL] {
        do {
            return try await historyManager.tabHistory(tabID: tab.uid)
        } catch {
            Logger.history.error("Failed to fetch tab history: \(error.localizedDescription)")
            return []
        }
    }

    /// Returns unique domains visited in this tab's session
    func visitedDomains() async -> Set<String> {
        Set(await tabHistory().compactMap { $0.host })
    }

    // MARK: - AI Chat

    /// Returns the current AI Chat ID if the tab is displaying an AI Chat with a chatID, nil otherwise.
    ///
    /// The chatID is extracted from the `chatID` query parameter in the URL.
    /// Example URL: `https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4&chatID=eb5e9bce-9d58-4ff1-8c81-c88f52120933`
    var currentAIChatId: String? {
        guard tab.isAITab else { return nil }
        return tab.link?.url.duckAIChatID
    }
    
    /// Returns the current Chat ID for the contextual AI chat session for this tab
    ///
    /// The chatID is extracted from the `chatID` query parameter in the URL.
    /// Example URL: `https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4&chatID=eb5e9bce-9d58-4ff1-8c81-c88f52120933`
    var currentContextualChatId: String? {
        guard let urlString = tab.contextualChatURL,
              let url = URL(string: urlString) else { return nil }
        return url.duckAIChatID
    }
}
