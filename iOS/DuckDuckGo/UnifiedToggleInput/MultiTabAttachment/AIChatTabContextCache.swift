//
//  AIChatTabContextCache.swift
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
import Foundation

/// In-memory page context per browser tab, keyed on the tab `uid`.
///
/// Retains page updates during the hack phase. Attachments prepare their own context from the
/// live tab, waking its web view when needed, so this cache need not survive an app restart.
// @MainActor
final class AIChatTabContextCache {

    struct Entry {
        /// The page context collected from the page.
        let context: AIChatPageContextData
        /// The URL the context came from. Compared against the tab's current URL to find a stale entry.
        let url: URL
    }

    private var entries: [TabUID: Entry] = [:]

    func store(context: AIChatPageContextData, url: URL, forTabId tabId: TabUID) {
        entries[tabId] = Entry(context: context, url: url)
    }

    func context(forTabId tabId: TabUID) -> Entry? {
        entries[tabId]
    }

    func removeContext(forTabId tabId: TabUID) {
        entries[tabId] = nil
    }
}
