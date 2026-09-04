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

/// Owned by the draft, then by its submission. Removing the last owner cancels collection.
@MainActor
final class MultiTabAttachmentPreparation {
    let tab: Tab
    let url: URL
    private(set) var isComplete = false
    private var task: Task<AIChatPageContextData?, Never>?

    init(tab: Tab, url: URL, collect: @escaping @MainActor () async -> AIChatPageContextData?) {
        self.tab = tab
        self.url = url
        task = Task { @MainActor [weak self] in
            let context = await collect()
            guard !Task.isCancelled else {
                print("🇱🇻🟢 PREFETCH CANCELLED tab=\(tab.uid)")
                return nil
            }
            self?.isComplete = true
            if let context {
                print("🇱🇻🟢 PREFETCH READY tab=\(tab.uid) contentLength=\(context.content.count)")
            } else {
                print("🇱🇻🟢 PREFETCH FAILED tab=\(tab.uid) - will retry on send")
            }
            return context
        }
    }

    deinit {
        task?.cancel()
    }

    func value() async -> AIChatPageContextData? {
        await task?.value
    }
}

/// Resolves browser tabs and prepares context when attached, with a submit-time fallback.
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

    func prepareContext(for attachment: UnifiedToggleInputTabAttachment,
                        currentTabId: TabUID?) -> MultiTabAttachmentPreparation? {
        guard let tab = resolveTab(for: attachment, currentTabId: currentTabId) else { return nil }
        print("🇱🇻🟢 PREFETCH START tab=\(tab.uid) title=\(attachment.title) - chip attached, loading and collecting context")
        return MultiTabAttachmentPreparation(tab: tab, url: attachment.url) { [weak self] in
            await self?.collectContext(for: tab)
        }
    }

    /// Reuses the attachment snapshot or waits for its in-flight collect. Missing/failed
    /// preparations fall back to sequential live collection; unavailable contexts are omitted.
    func pageContexts(for attachments: [UnifiedToggleInputTabAttachment],
                      currentTabId: TabUID?,
                      preparations: [UUID: MultiTabAttachmentPreparation] = [:]) async -> [AIChatPageContextData] {
        guard isEnabled else { return [] }
        print("🇱🇻🟢 building contexts for \(attachments.count) attached tab(s), currentTabId=\(currentTabId ?? "nil")")
        var contexts: [AIChatPageContextData] = []
        for attachment in attachments {
            guard !Task.isCancelled, isEnabled else { return [] }
            guard let tab = resolveTab(for: attachment, currentTabId: currentTabId) else { continue }

            var context: AIChatPageContextData?
            if let preparation = preparations[attachment.id], preparation.tab === tab, preparation.url == attachment.url {
                print("🇱🇻🟢 PREFETCH \(preparation.isComplete ? "USE" : "WAIT") tab=\(tab.uid) - send uses existing collection")
                context = await preparation.value()
            }
            guard !Task.isCancelled, isEnabled else { return [] }
            if context == nil {
                print("🇱🇻🟢 PREFETCH MISS tab=\(tab.uid) - collecting at send")
                context = await collectContext(for: tab)
            }
            guard let context, !Task.isCancelled, isEnabled,
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

    private func resolveTab(for attachment: UnifiedToggleInputTabAttachment, currentTabId: TabUID?) -> Tab? {
        guard isEnabled else { return nil }
        let tabs = openTabsProvider()
        let originMode = tabs.first { $0.uid == currentTabId }?.mode
        guard currentTabId == nil || originMode != nil,
              let tab = tabs.first(where: { $0.uid == attachment.tabId }),
              tab.link?.url == attachment.url,
              originMode == nil || tab.mode == originMode,
              !AIChatTabMetadata.shouldExcludeFromTabPicker(attachment.url) else { return nil }
        return tab
    }

    private func collectContext(for tab: Tab) async -> AIChatPageContextData? {
        guard !Task.isCancelled, isEnabled,
              openTabsProvider().contains(where: { $0 === tab }),
              let context = await contentProvider(tab),
              !Task.isCancelled, isEnabled,
              openTabsProvider().contains(where: { $0 === tab }),
              context.hasAttachedPage,
              tab.link?.url.absoluteString == context.url else { return nil }
        return context
    }
}
