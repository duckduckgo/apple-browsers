//
//  AIChatAttachedTabsTracker.swift
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
import Combine
import Foundation
import WebKit

/// Keeps each prompt's tab attachments in step with the tabs they point at: cards follow or drop on
/// navigation per `AIChatAttachedTabNavigationPolicy`, and closed tabs lose their attachment.
@MainActor
final class AIChatAttachedTabsTracker {

    /// Keyed by store too: an attachment belongs to the prompt's tab, not the selected one.
    private struct ObserverKey: Hashable {
        let promptStore: ObjectIdentifier
        let tabId: String
    }

    private struct Observer {
        weak var promptStore: (any DuckAIPromptDraftStoring)?
        /// Suspending a tab swaps the `Tab` behind the same uuid, stranding the old subscription.
        weak var tab: Tab?
        let cancellable: AnyCancellable
        /// While set, a URL change is that load settling (redirect, committed URL), not a page change.
        var isSettlingLoadFromAttachTime: Bool
        /// What the web view had committed when the tab was attached, replaced once by the load that
        /// was in flight. A further commit is a navigation the user (or the page) chose.
        weak var navigationAtAttachTime: WKBackForwardListItem?
        var hasCommittedSinceAttach = false
        /// The title of the page just navigated away from: it keeps being published for a beat after
        /// the URL changes, and adopting it would put the old page's name on the new one.
        var titleOfPreviousPage: String?
    }

    private weak var origin: (any DuckAIPromptOriginProviding)?
    private let automaticallySendsPageContext: () -> Bool

    private var observers: [ObserverKey: Observer] = [:]
    private weak var activeStore: (any DuckAIPromptDraftStoring)?
    /// Every prompt seen so far. Observers alone aren't enough: suspending an attached tab drops its
    /// observer, and that prompt still has to lose the card when the tab is closed.
    private let seenStores = NSHashTable<AnyObject>.weakObjects()
    private var tabListCancellable: AnyCancellable?

    init(origin: (any DuckAIPromptOriginProviding)?, automaticallySendsPageContext: @escaping () -> Bool) {
        self.origin = origin
        self.automaticallySendsPageContext = automaticallySendsPageContext
        watchTabListForClosedTabs()
    }

    /// Call whenever the prompt's own attachments change or the active draft switches.
    func trackAttachments(of store: (any DuckAIPromptDraftStoring)?) {
        activeStore = store
        if let store {
            seenStores.add(store as AnyObject)
        }
        dropObserversForDetachedTabs()
        observeAttachedTabs()
    }

    // MARK: - Closed tabs

    private func watchTabListForClosedTabs() {
        guard let collection = origin?.originTabCollectionViewModel else { return }
        let pinnedTabs = collection.pinnedTabsCollection?.$tabs.eraseToAnyPublisher()
            ?? Just([]).eraseToAnyPublisher()
        tabListCancellable = Publishers.CombineLatest(collection.tabCollection.$tabs, pinnedTabs)
            // Nothing has closed at subscription time; only later changes can strand an attachment.
            .dropFirst()
            // Moves between the two collections are two mutations; read the lists once both landed.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.dropAttachmentsForClosedTabs()
            }
    }

    private func dropAttachmentsForClosedTabs() {
        guard let collection = origin?.originTabCollectionViewModel else { return }
        let openTabIds = Set(allTabs(in: collection).map(\.uuid))
        for store in trackedStores {
            let remaining = store.aiChatTabAttachments.filter { openTabIds.contains($0.id) }
            guard remaining.count != store.aiChatTabAttachments.count else { continue }
            store.setAIChatTabAttachments(remaining)
        }
        dropObserversForDetachedTabs()
        observeAttachedTabs()
    }

    private var trackedStores: [any DuckAIPromptDraftStoring] {
        seenStores.allObjects.compactMap { $0 as? any DuckAIPromptDraftStoring }
    }

    // MARK: - Observing

    /// Observers for other prompts keep running, so their cards update while the user is elsewhere.
    private func dropObserversForDetachedTabs() {
        observers = observers.filter { key, observer in
            observer.tab != nil && observer.promptStore?.aiChatTabAttachments.contains { $0.id == key.tabId } ?? false
        }
    }

    private func observeAttachedTabs() {
        guard let collection = origin?.originTabCollectionViewModel else { return }
        for store in trackedStores {
            observeAttachedTabs(of: store, in: collection)
        }
    }

    private func observeAttachedTabs(of store: any DuckAIPromptDraftStoring, in collection: TabCollectionViewModel) {
        for attachment in store.aiChatTabAttachments {
            guard let tab = loadedTab(withId: attachment.id, in: collection) else { continue }
            let key = ObserverKey(promptStore: ObjectIdentifier(store), tabId: attachment.id)
            guard observers[key]?.tab !== tab else { continue }

            let isSettling = hasUncommittedLoad(tab)
            observers[key] = Observer(promptStore: store,
                                      tab: tab,
                                      cancellable: observe(tab, key: key, in: store),
                                      isSettlingLoadFromAttachTime: isSettling,
                                      navigationAtAttachTime: tab.webView.backForwardList.currentItem)
            // Reconcile against the page the tab is on now, which may predate this observer.
            applyPolicy(for: key, in: store, page: AIChatAttachedTabPage(tab: tab), isSettlingLoad: isSettling)
        }
    }

    /// `dropFirst`: the observer must be stored before any policy runs, or a re-sync subscribes twice.
    private func observe(_ tab: Tab, key: ObserverKey, in store: any DuckAIPromptDraftStoring) -> AnyCancellable {
        Publishers.CombineLatest4(tab.$content, tab.$title, tab.$favicon, tab.$isLoading)
            .dropFirst()
            .map { AIChatAttachedTabPage(content: $0, title: $1, favicon: $2, isLoading: $3) }
            .sink { [weak self, weak store] page in
                guard let self, let store else { return }
                self.applyPolicy(for: key,
                                 in: store,
                                 page: self.discardingTitleOfPreviousPage(from: page, for: key),
                                 isSettlingLoad: self.isSettlingLoad(for: key, page: page))
            }
    }

    /// Whether this change is still the load that was running when the tab was attached. Ends at the
    /// first navigation the web view commits on top of that one, and when the load finishes.
    private func isSettlingLoad(for key: ObserverKey, page: AIChatAttachedTabPage) -> Bool {
        guard let observer = observers[key], observer.isSettlingLoadFromAttachTime else { return false }

        // The load in flight commits once — over the attach-time item for a fresh tab, or as a new
        // item when a page was already committed. A second commit is the user going elsewhere.
        let committed = observer.tab?.webView.backForwardList.currentItem
        if committed !== observer.navigationAtAttachTime {
            guard !observer.hasCommittedSinceAttach else {
                observers[key]?.isSettlingLoadFromAttachTime = false
                return false
            }
            observers[key]?.hasCommittedSinceAttach = true
            observers[key]?.navigationAtAttachTime = committed
        }
        return finishSettlingIfLoaded(key: key, page: page)
    }

    private func finishSettlingIfLoaded(key: ObserverKey, page: AIChatAttachedTabPage) -> Bool {
        if !page.isLoading {
            observers[key]?.isSettlingLoadFromAttachTime = false
        }
        return true
    }

    /// Blanks the title while it still holds the previous page's, so the card shows the new page's
    /// host until its own title arrives.
    private func discardingTitleOfPreviousPage(from page: AIChatAttachedTabPage, for key: ObserverKey) -> AIChatAttachedTabPage {
        // A finished load publishes the new page's own title, so the old one can't come back after it.
        guard let stale = observers[key]?.titleOfPreviousPage, page.isLoading, page.title == stale else {
            observers[key]?.titleOfPreviousPage = nil
            return page
        }
        return AIChatAttachedTabPage(content: page.content, title: nil, favicon: page.favicon, isLoading: page.isLoading)
    }

    // MARK: - Applying the policy

    /// `store` is the prompt's own store, which is not necessarily the active one.
    private func applyPolicy(for key: ObserverKey,
                             in store: any DuckAIPromptDraftStoring,
                             page: AIChatAttachedTabPage,
                             isSettlingLoad: Bool) {
        var attachments = store.aiChatTabAttachments
        guard let index = attachments.firstIndex(where: { $0.id == key.tabId }) else { return }

        switch AIChatAttachedTabNavigationPolicy.action(for: attachments[index],
                                                       page: page,
                                                       isSettlingLoadFromAttachTime: isSettlingLoad,
                                                       automaticallySendsPageContext: automaticallySendsPageContext()) {
        case .keep:
            return
        case .drop:
            attachments.remove(at: index)
        case .refresh(let refreshed):
            if refreshed.url != attachments[index].url {
                // The tab's own title, not the one on `page`: that has been through the discard
                // filter already and may be blanked, which would let the old title back in.
                observers[key]?.titleOfPreviousPage = observers[key]?.tab?.title
            }
            attachments[index] = refreshed
        }
        store.setAIChatTabAttachments(attachments)
        dropObserversForDetachedTabs()
        observeAttachedTabs()
    }

    // MARK: - Tab lookup

    /// A load that hasn't committed: the tab's content is ahead of what the web view is showing. A
    /// page that has committed and is only finishing subresources isn't one, so a navigation made
    /// after it can't pass as the attach-time load settling.
    private func hasUncommittedLoad(_ tab: Tab) -> Bool {
        tab.isLoading && tab.content.urlForWebView != tab.webView.url
    }

    /// Suspended tabs are skipped: they can't navigate, and the tab-list watch re-observes on resume.
    private func loadedTab(withId id: String, in collection: TabCollectionViewModel) -> Tab? {
        allTabs(in: collection).lazy.compactMap { anyTab -> Tab? in
            guard case .loaded(let tab) = anyTab, tab.uuid == id else { return nil }
            return tab
        }.first
    }

    private func allTabs(in collection: TabCollectionViewModel) -> [AnyTab] {
        (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
    }
}
