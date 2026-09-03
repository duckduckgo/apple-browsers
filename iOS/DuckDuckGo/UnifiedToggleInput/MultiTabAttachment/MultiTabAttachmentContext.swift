//
//  MultiTabAttachmentContext.swift
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
import os.log

/// One open browser tab the user can attach to a Duck.ai prompt.
struct MultiTabAttachmentCandidate: Equatable {
    let tabId: TabUID
    let title: String
    let url: URL
}

/// The seam between the browser's tabs and the Duck.ai input.
///
/// `TabManager` owns one instance and hands it to every `TabViewController`, which writes each
/// tab's page context into the cache. The contextual chat input reads the tab list and the cached
/// contexts back through the same instance.
@MainActor
final class MultiTabAttachmentContext {

    let cache: AIChatTabContextCache
    private let feature: MultiTabAttachmentHackFeature
    private let openTabsProvider: () -> [Tab]

    /// `cache` defaults to nil rather than to a new instance, because a default argument is
    /// evaluated outside the main actor and `AIChatTabContextCache` is main-actor isolated. The
    /// initializer body is isolated, so the instance is built there instead.
    init(cache: AIChatTabContextCache? = nil,
         feature: MultiTabAttachmentHackFeature = MultiTabAttachmentHackFeature(),
         openTabsProvider: @escaping () -> [Tab]) {
        self.cache = cache ?? AIChatTabContextCache()
        self.feature = feature
        self.openTabsProvider = openTabsProvider
    }

    var isEnabled: Bool {
        feature.isMultiTabAttachmentHackPhaseEnabled
    }

    /// The tabs the user may attach, in the order of the tabs array.
    ///
    /// `Tab.lastViewedDate` orders this list in the final design, but that property is reserved for
    /// one daily pixel and must not be read here.
    func attachableTabs(excluding excludedTabId: TabUID?) -> [MultiTabAttachmentCandidate] {
        openTabsProvider().compactMap { tab in
            guard tab.uid != excludedTabId else { return nil }
            guard let link = tab.link else { return nil }
            guard !AIChatTabMetadata.shouldExcludeFromTabPicker(link.url) else { return nil }
            return MultiTabAttachmentCandidate(tabId: tab.uid, title: link.displayTitle, url: link.url)
        }
    }

    /// Builds one page context per attached tab, in the order the user attached them.
    ///
    /// A tab whose cache holds nothing, or holds a context from a URL the tab has since left, falls
    /// back to URL and title. The submit is never blocked.
    ///
    /// `tabId` marks "another tab": it is stamped on every entry except the one that matches the
    /// current tab, which the duck.ai web app reads as the current page.
    func pageContexts(for attachments: [UnifiedToggleInputTabAttachment],
                      currentTabId: TabUID?) -> [AIChatPageContextData] {
        print("🇱🇻 building contexts for \(attachments.count) attached tab(s), currentTabId=\(currentTabId ?? "nil")")
        return attachments.map { attachment in
            let tabId: String? = attachment.tabId == currentTabId ? nil : attachment.tabId
            guard let entry = cache.context(forTabId: attachment.tabId) else {
                Logger.aiChat.debug("[MultiTabAttachment] cache miss for tab \(attachment.tabId) - sending URL and title only")
                print("🇱🇻 CACHE MISS tab=\(attachment.tabId) title=\(attachment.title) - sending URL and title only")
                return Self.metadataOnlyContext(for: attachment).withTabId(tabId)
            }
            guard entry.url == attachment.url else {
                Logger.aiChat.debug("[MultiTabAttachment] stale cache for tab \(attachment.tabId) - sending URL and title only")
                print("🇱🇻 CACHE STALE tab=\(attachment.tabId) cachedURL=\(entry.url.absoluteString) attachedURL=\(attachment.url.absoluteString)")
                return Self.metadataOnlyContext(for: attachment).withTabId(tabId)
            }
            print("🇱🇻 CACHE HIT tab=\(attachment.tabId) contentLength=\(entry.context.content.count) stampedTabId=\(tabId ?? "nil")")
            return entry.context.withTabId(tabId)
        }
    }

    private static func metadataOnlyContext(for attachment: UnifiedToggleInputTabAttachment) -> AIChatPageContextData {
        AIChatPageContextData(
            title: attachment.title,
            favicon: [],
            url: attachment.url.absoluteString,
            content: "",
            truncated: false,
            fullContentLength: 0,
            attached: false
        )
    }
}
