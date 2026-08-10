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
        /// The title of the page just navigated away from: it keeps being published for a beat after
        /// the URL changes, and adopting it would put the old page's name on the new one.
        var titleOfPreviousPage: String?
    }

    private weak var origin: (any DuckAIPromptOriginProviding)?
    private weak var windowControllersManager: (any WindowControllersManagerProtocol)?

    private var observers: [ObserverKey: Observer] = [:]
    private weak var activeStore: (any DuckAIPromptDraftStoring)?
    /// Every prompt seen so far. Observers alone aren't enough: suspending an attached tab drops its
    /// observer, and that prompt still has to lose the card when the tab is closed.
    private let seenStores = NSHashTable<AnyObject>.weakObjects()
    private var tabListCancellable: AnyCancellable?

    init(origin: (any DuckAIPromptOriginProviding)?, windowControllersManager: (any WindowControllersManagerProtocol)?) {
        self.origin = origin
        self.windowControllersManager = windowControllersManager
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
        // The origin window's own lists, plus every other window's: an attached tab can be closed
        // from the window it lives in, which isn't necessarily this one.
        let ownTabs = Publishers.CombineLatest(collection.tabCollection.$tabs, pinnedTabs)
            // Nothing has closed at subscription time; only later changes can strand an attachment.
            .dropFirst()
            .map { _, _ in () }
        let otherWindows = windowControllersManager?.tabsChanged ?? Empty().eraseToAnyPublisher()
        tabListCancellable = ownTabs.merge(with: otherWindows)
            // Moves between collections are two mutations; read the lists once both landed.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.dropAttachmentsForClosedTabs()
            }
    }

    private func dropAttachmentsForClosedTabs() {
        let openTabIds = Set(attachableCollections.flatMap { allTabs(in: $0) }.map(\.uuid))
        guard !openTabIds.isEmpty else { return }
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
        for store in trackedStores {
            observeAttachedTabs(of: store)
        }
    }

    private func observeAttachedTabs(of store: any DuckAIPromptDraftStoring) {
        for attachment in store.aiChatTabAttachments {
            guard let tab = loadedTab(withId: attachment.id) else { continue }
            let key = ObserverKey(promptStore: ObjectIdentifier(store), tabId: attachment.id)
            guard observers[key]?.tab !== tab else { continue }

            observers[key] = Observer(promptStore: store,
                                      tab: tab,
                                      cancellable: observe(tab, key: key, in: store))
            // Reconcile against the page the tab is on now, which may predate this observer.
            applyPolicy(for: key, in: store, page: AIChatAttachedTabPage(tab: tab))
        }
    }

    /// `dropFirst`: the observer must be stored before any policy runs, or a re-sync subscribes twice.
    private func observe(_ tab: Tab, key: ObserverKey, in store: any DuckAIPromptDraftStoring) -> AnyCancellable {
        Publishers.CombineLatest4(tab.$content, tab.$title, tab.$favicon, tab.$isLoading)
            .dropFirst()
            .map { AIChatAttachedTabPage(content: $0, title: $1, favicon: $2, isLoading: $3) }
            .sink { [weak self, weak store] page in
                guard let self, let store else { return }
                self.applyPolicy(for: key, in: store, page: self.discardingTitleOfPreviousPage(from: page, for: key))
            }
    }

    /// Blanks the title while it still holds the previous page's, so the card shows the new page's
    /// host until its own title arrives.
    private func discardingTitleOfPreviousPage(from page: AIChatAttachedTabPage, for key: ObserverKey) -> AIChatAttachedTabPage {
        // No load event tells us the new page's title has arrived — `handleUrlDidChange` assigns
        // content directly, leaving the old title in place, and it can outlive the load. So the old
        // value is refused for as long as it is published; a page whose title matches the previous
        // one keeps the host, which is plain but never another page's name.
        guard let stale = observers[key]?.titleOfPreviousPage, page.title == stale else {
            observers[key]?.titleOfPreviousPage = nil
            return page
        }
        return AIChatAttachedTabPage(content: page.content, title: nil, favicon: page.favicon, isLoading: page.isLoading)
    }

    // MARK: - Applying the policy

    /// `store` is the prompt's own store, which is not necessarily the active one.
    private func applyPolicy(for key: ObserverKey,
                             in store: any DuckAIPromptDraftStoring,
                             page: AIChatAttachedTabPage) {
        var attachments = store.aiChatTabAttachments
        guard let index = attachments.firstIndex(where: { $0.id == key.tabId }) else { return }

        switch AIChatAttachedTabNavigationPolicy.action(for: attachments[index], page: page) {
        case .keep:
            return
        case .drop:
            attachments.remove(at: index)
        case .refresh(let refreshed):
            if refreshed.url != attachments[index].url {
                // The tab's own title, not the one on `page`: that has been through the discard
                // filter already and may be blanked, which would let the old title back in.
                let titleBeingLeft = observers[key]?.tab?.title
                observers[key]?.titleOfPreviousPage = titleBeingLeft
            }
            attachments[index] = refreshed
        }
        store.setAIChatTabAttachments(attachments)
        dropObserversForDetachedTabs()
        observeAttachedTabs()
    }

    // MARK: - Tab lookup

    /// The windows an attachment can live in — see `AIChatTabPickerSource`.
    private var attachableCollections: [TabCollectionViewModel] {
        guard let origin = origin?.originTabCollectionViewModel, let windowControllersManager else { return [] }
        return AIChatTabPickerSource.tabCollections(forOrigin: origin, in: windowControllersManager)
    }

    /// Suspended tabs are skipped: they can't navigate, and the tab-list watch re-observes on resume.
    private func loadedTab(withId id: String) -> Tab? {
        attachableCollections.lazy.flatMap { self.allTabs(in: $0) }.compactMap { anyTab -> Tab? in
            guard case .loaded(let tab) = anyTab, tab.uuid == id else { return nil }
            return tab
        }.first
    }

    private func allTabs(in collection: TabCollectionViewModel) -> [AnyTab] {
        (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
    }
}
