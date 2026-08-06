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

    private struct ObserverKey: Hashable {
        let store: ObjectIdentifier
        let tabId: String
    }

    private struct Observer {
        weak var store: (any DuckAIPromptDraftStoring)?
        /// Suspending a tab swaps the `Tab` behind the same uuid, stranding the old subscription.
        weak var tab: Tab?
        let cancellable: AnyCancellable
        /// While set, a URL change is that load settling (redirect, committed URL), not a page change.
        var isSettlingLoadFromAttachTime: Bool
    }

    private weak var origin: (any DuckAIPromptOriginProviding)?
    private let automaticallySendsPageContext: () -> Bool

    /// Keyed by store too: an attachment belongs to the prompt's tab, not the selected one.
    private var observers: [ObserverKey: Observer] = [:]
    private weak var activeStore: (any DuckAIPromptDraftStoring)?
    private var tabListCancellable: AnyCancellable?

    init(origin: (any DuckAIPromptOriginProviding)?, automaticallySendsPageContext: @escaping () -> Bool) {
        self.origin = origin
        self.automaticallySendsPageContext = automaticallySendsPageContext
        subscribeToTabList()
    }

    /// Call whenever the prompt's own attachments change or the active draft switches.
    func trackAttachments(of store: (any DuckAIPromptDraftStoring)?) {
        activeStore = store
        syncObservers()
    }

    private func subscribeToTabList() {
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
        let openTabIds = Set(((collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs).map(\.uuid))
        for store in storesWithAttachments {
            let remaining = store.aiChatTabAttachments.filter { openTabIds.contains($0.id) }
            guard remaining.count != store.aiChatTabAttachments.count else { continue }
            store.setAIChatTabAttachments(remaining)
        }
        syncObservers()
    }

    private var storesWithAttachments: [any DuckAIPromptDraftStoring] {
        var stores: [any DuckAIPromptDraftStoring] = observers.values.compactMap(\.store)
        if let activeStore {
            stores.append(activeStore)
        }
        return stores
    }

    /// Observers for other drafts keep running; a newly observed tab is reconciled right after.
    private func syncObservers() {
        observers = observers.filter { key, observer in
            observer.tab != nil && observer.store?.aiChatTabAttachments.contains { $0.id == key.tabId } ?? false
        }

        guard let store = activeStore, let collection = origin?.originTabCollectionViewModel else { return }
        for attachment in store.aiChatTabAttachments {
            guard let tab = loadedTab(withId: attachment.id, in: collection) else { continue }
            let key = ObserverKey(store: ObjectIdentifier(store), tabId: attachment.id)
            guard observers[key]?.tab !== tab else { continue }

            observers[key] = Observer(store: store,
                                      tab: tab,
                                      cancellable: observe(tab, for: attachment.id, in: store, key: key),
                                      isSettlingLoadFromAttachTime: tab.isLoading)
            apply(to: attachment.id, in: store, content: tab.content, title: tab.title, favicon: tab.favicon,
                  isSettlingLoadFromAttachTime: tab.isLoading)
        }
    }

    /// `dropFirst`: the observer must be stored before any policy runs, or a re-sync subscribes twice.
    private func observe(_ tab: Tab,
                         for tabId: String,
                         in store: any DuckAIPromptDraftStoring,
                         key: ObserverKey) -> AnyCancellable {
        Publishers.CombineLatest4(tab.$content, tab.$title, tab.$favicon, tab.$isLoading)
            .dropFirst()
            .sink { [weak self, weak store] content, title, favicon, isLoading in
                guard let self, let store else { return }
                let isSettling = self.observers[key]?.isSettlingLoadFromAttachTime ?? false
                if isSettling, !isLoading {
                    self.observers[key]?.isSettlingLoadFromAttachTime = false
                }
                self.apply(to: tabId, in: store, content: content, title: title, favicon: favicon,
                           isSettlingLoadFromAttachTime: isSettling)
            }
    }

    /// `store` is the prompt's own store, which is not necessarily the active one.
    private func apply(to tabId: String,
                       in store: any DuckAIPromptDraftStoring,
                       content: Tab.TabContent,
                       title: String?,
                       favicon: NSImage?,
                       isSettlingLoadFromAttachTime: Bool) {
        var current = store.aiChatTabAttachments
        guard let index = current.firstIndex(where: { $0.id == tabId }) else { return }

        switch AIChatAttachedTabNavigationPolicy.action(for: current[index],
                                                       content: content,
                                                       title: title,
                                                       favicon: favicon,
                                                       isSettlingLoadFromAttachTime: isSettlingLoadFromAttachTime,
                                                       automaticallySendsPageContext: automaticallySendsPageContext()) {
        case .keep:
            return
        case .drop:
            current.remove(at: index)
        case .refresh(let refreshed):
            current[index] = refreshed
        }
        store.setAIChatTabAttachments(current)
        syncObservers()
    }

    /// Suspended tabs are skipped: they can't navigate, and the tab-list watch re-observes on resume.
    private func loadedTab(withId id: String, in collection: TabCollectionViewModel) -> Tab? {
        let allTabs = (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
        return allTabs.lazy.compactMap { anyTab -> Tab? in
            guard case .loaded(let tab) = anyTab, tab.uuid == id else { return nil }
            return tab
        }.first
    }
}
