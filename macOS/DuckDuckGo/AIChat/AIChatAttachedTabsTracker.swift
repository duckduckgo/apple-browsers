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
        /// While set, a URL change is that load settling (redirect, committed URL), not a page change.
        var isSettlingLoadFromAttachTime: Bool
    }

    private weak var origin: (any DuckAIPromptOriginProviding)?
    private let automaticallySendsPageContext: () -> Bool

    private var observers: [ObserverKey: Observer] = [:]
    private weak var activeStore: (any DuckAIPromptDraftStoring)?
    private var tabListCancellable: AnyCancellable?

    init(origin: (any DuckAIPromptOriginProviding)?, automaticallySendsPageContext: @escaping () -> Bool) {
        self.origin = origin
        self.automaticallySendsPageContext = automaticallySendsPageContext
        watchTabListForClosedTabs()
    }

    /// Call whenever the prompt's own attachments change or the active draft switches.
    func trackAttachments(of store: (any DuckAIPromptDraftStoring)?) {
        activeStore = store
        dropObserversForDetachedTabs()
        observeAttachedTabs()
    }

    // MARK: - Closed tabs

    private func watchTabListForClosedTabs() {
        guard let collection = origin?.originTabCollectionViewModel else { return }
        let pinnedTabs = collection.pinnedTabsCollection?.$tabs.eraseToAnyPublisher()
            ?? Just([]).eraseToAnyPublisher()
        tabListCancellable = Publishers.CombineLatest(collection.tabCollection.$tabs, pinnedTabs)
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

    /// Every prompt this tracker knows of, not only the one on screen.
    private var trackedStores: [any DuckAIPromptDraftStoring] {
        var stores: [any DuckAIPromptDraftStoring] = observers.values.compactMap(\.promptStore)
        if let activeStore {
            stores.append(activeStore)
        }
        return stores
    }

    // MARK: - Observing

    /// Observers for other prompts keep running, so their cards update while the user is elsewhere.
    private func dropObserversForDetachedTabs() {
        observers = observers.filter { key, observer in
            observer.tab != nil && observer.promptStore?.aiChatTabAttachments.contains { $0.id == key.tabId } ?? false
        }
    }

    private func observeAttachedTabs() {
        guard let store = activeStore, let collection = origin?.originTabCollectionViewModel else { return }
        for attachment in store.aiChatTabAttachments {
            guard let tab = loadedTab(withId: attachment.id, in: collection) else { continue }
            let key = ObserverKey(promptStore: ObjectIdentifier(store), tabId: attachment.id)
            guard observers[key]?.tab !== tab else { continue }

            observers[key] = Observer(promptStore: store,
                                      tab: tab,
                                      cancellable: observe(tab, key: key, in: store),
                                      isSettlingLoadFromAttachTime: tab.isLoading)
            // Reconcile against the page the tab is on now, which may predate this observer.
            applyPolicy(for: key, in: store, page: AIChatAttachedTabPage(tab: tab), isSettlingLoad: tab.isLoading)
        }
    }

    /// `dropFirst`: the observer must be stored before any policy runs, or a re-sync subscribes twice.
    private func observe(_ tab: Tab, key: ObserverKey, in store: any DuckAIPromptDraftStoring) -> AnyCancellable {
        Publishers.CombineLatest4(tab.$content, tab.$title, tab.$favicon, tab.$isLoading)
            .dropFirst()
            .map(AIChatAttachedTabPage.init)
            .sink { [weak self, weak store] page in
                guard let self, let store else { return }
                self.applyPolicy(for: key, in: store, page: page, isSettlingLoad: self.isSettlingLoad(for: key, page: page))
            }
    }

    /// Whether this change is still the load that was running when the tab was attached. Clears once
    /// that load finishes, so later navigation is judged as a page change.
    private func isSettlingLoad(for key: ObserverKey, page: AIChatAttachedTabPage) -> Bool {
        let isSettling = observers[key]?.isSettlingLoadFromAttachTime ?? false
        if isSettling, !page.isLoading {
            observers[key]?.isSettlingLoadFromAttachTime = false
        }
        return isSettling
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
            attachments[index] = refreshed
        }
        store.setAIChatTabAttachments(attachments)
        dropObserversForDetachedTabs()
        observeAttachedTabs()
    }

    // MARK: - Tab lookup

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
