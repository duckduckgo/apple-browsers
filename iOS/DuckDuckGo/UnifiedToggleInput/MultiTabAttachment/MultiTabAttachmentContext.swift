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

/// One open browser tab the user can attach to a Duck.ai prompt.
struct MultiTabAttachmentCandidate: Equatable {
    let tabId: TabUID
    let title: String
    let url: URL
}

/// A frozen attachment selection, collected before its prompt is dispatched.
struct MultiTabAttachmentRequest {
    let collect: @MainActor () async -> [AIChatPageContextData]
    let didConsume: @MainActor () -> Void
}

/// Resolves browser tabs and collects fresh context for the Duck.ai input.
@MainActor
final class MultiTabAttachmentContext {

    let cache: AIChatTabContextCache
    private let feature: MultiTabAttachmentHackFeature
    private let openTabsProvider: () -> [Tab]
    private let contentProvider: (Tab) async -> AIChatPageContextData?

    init(cache: AIChatTabContextCache? = nil,
         feature: MultiTabAttachmentHackFeature = MultiTabAttachmentHackFeature(),
         openTabsProvider: @escaping () -> [Tab],
         contentProvider: @escaping (Tab) async -> AIChatPageContextData?) {
        self.cache = cache ?? AIChatTabContextCache()
        self.feature = feature
        self.openTabsProvider = openTabsProvider
        self.contentProvider = contentProvider
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

    /// Like macOS, unavailable contexts are omitted rather than sent as empty attachments.
    /// Collect sequentially to bound the number of web views awakened on iOS.
    func pageContexts(for attachments: [UnifiedToggleInputTabAttachment],
                      currentTabId: TabUID?) async -> [AIChatPageContextData] {
        guard isEnabled else { return [] }
        print("🇱🇻🟢 building contexts for \(attachments.count) attached tab(s), currentTabId=\(currentTabId ?? "nil")")
        var contexts: [AIChatPageContextData] = []
        let originMode = openTabsProvider().first { $0.uid == currentTabId }?.mode
        guard currentTabId == nil || originMode != nil else { return [] }
        for attachment in attachments {
            guard !Task.isCancelled, isEnabled else { return [] }
            guard let tab = openTabsProvider().first(where: { $0.uid == attachment.tabId }),
                  tab.link?.url == attachment.url,
                  originMode == nil || tab.mode == originMode,
                  !AIChatTabMetadata.shouldExcludeFromTabPicker(attachment.url) else { continue }

            guard let context = await contentProvider(tab),
                  !Task.isCancelled, isEnabled,
                  openTabsProvider().contains(where: { $0 === tab }),
                  context.hasAttachedPage,
                  let collectedURL = URL(string: context.url),
                  tab.link?.url == collectedURL else {
                print("🇱🇻🟢 context unavailable after loading and collection tab=\(tab.uid) title=\(attachment.title) - skipping attachment")
                continue
            }
            cache.store(context: context, url: collectedURL, forTabId: tab.uid)
            print("🇱🇻🟢 COLLECTED tab=\(tab.uid) title=\(context.title) contentLength=\(context.content.count)")
            contexts.append(context.withTabId(attachment.tabId == currentTabId ? nil : attachment.tabId))
        }
        return contexts
    }
}
