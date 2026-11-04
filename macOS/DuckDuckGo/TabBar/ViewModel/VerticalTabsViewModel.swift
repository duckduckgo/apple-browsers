//
//  VerticalTabsViewModel.swift
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
import FoundationExtensions

struct VerticalTab: Identifiable, Equatable {
    let id: TabIdentifier
    let title: String
    let favicon: NSImage?
    let url: URL?
    let canBePinned: Bool
}

/// Lists a window's unpinned tabs for the vertical tabs sidebar. Pinned tabs stay in the tab bar.
@MainActor
final class VerticalTabsViewModel: ObservableObject {
    @Published private(set) var tabs: [VerticalTab] = []
    @Published private(set) var selectedTabID: TabIdentifier?

    var canPinTabs: Bool {
        tabCollectionViewModel.pinnedTabsCollection != nil
    }

    private let tabCollectionViewModel: TabCollectionViewModel
    private let aiChatCoordinator: AIChatCoordinating?
    private let tabDragAndDropManager: TabDragAndDropManager
    private var cancellables = Set<AnyCancellable>()
    private var tabCancellables = Set<AnyCancellable>()

    init(
        tabCollectionViewModel: TabCollectionViewModel,
        aiChatCoordinator: AIChatCoordinating?,
        tabDragAndDropManager: TabDragAndDropManager
    ) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.aiChatCoordinator = aiChatCoordinator
        self.tabDragAndDropManager = tabDragAndDropManager

        reloadTabs()
        updateSelectedTabID()
        subscribeToTabCollection()
    }

    func select(_ id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        tabCollectionViewModel.select(at: .unpinned(index))
    }

    func close(_ id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        aiChatCoordinator?.closeFloatingWindow(for: id)
        tabCollectionViewModel.close(at: .unpinned(index))
    }

    func closeOtherTabs(except id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        tabCollectionViewModel.removeAllTabs(except: index)
    }

    func duplicate(_ id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        tabCollectionViewModel.duplicateTab(at: .unpinned(index))
    }

    func pin(_ id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        tabCollectionViewModel.pinTab(at: index)
    }

    func openNewTab() {
        tabCollectionViewModel.insertOrAppendNewTab()
    }

    /// Selects the dragged tab up front, like the tab bar: moving a tab selects it, and doing that mid-drag would switch the page.
    func startDragging(_ id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        tabCollectionViewModel.select(at: .unpinned(index))
        tabDragAndDropManager.setSource(tabCollectionViewModel: tabCollectionViewModel, index: .unpinned(index))
    }

    /// Moves a tab dragged within this window into the place of the tab it is dragged over.
    func moveDraggedTab(to targetID: TabIdentifier) {
        guard let source = tabDragAndDropManager.sourceUnit,
              source.tabCollectionViewModel === tabCollectionViewModel,
              source.index.isUnpinnedTab,
              let targetIndex = unpinnedIndex(of: targetID),
              targetIndex != source.index.item else { return }
        let newIndex = TabIndex.unpinned(targetIndex)
        tabCollectionViewModel.moveTab(at: source.index, to: newIndex)
        tabDragAndDropManager.setSource(tabCollectionViewModel: tabCollectionViewModel, index: newIndex)
    }

    /// Ends the drag on the tab it was dropped on. A tab dragged from another window moves to this one.
    func dropDraggedTab(on targetID: TabIdentifier) {
        defer { tabDragAndDropManager.clear() }
        guard let targetIndex = unpinnedIndex(of: targetID) else { return }
        tabDragAndDropManager.setDestination(tabCollectionViewModel: tabCollectionViewModel, index: .unpinned(targetIndex))
        tabDragAndDropManager.performDragAndDropIfNeeded()
    }

    private func unpinnedIndex(of id: TabIdentifier) -> Int? {
        tabCollectionViewModel.tabCollection.tabs.firstIndex { $0.uuid == id }
    }

    private func subscribeToTabCollection() {
        // TabCollectionViewModel updates its tab view models from the same publisher,
        // so read the collection once the change has settled.
        tabCollectionViewModel.tabCollection.$tabs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadTabs()
                self?.updateSelectedTabID()
            }
            .store(in: &cancellables)

        tabCollectionViewModel.$selectionIndex
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSelectedTabID()
            }
            .store(in: &cancellables)
    }

    private func reloadTabs() {
        let tabViewModels = tabCollectionViewModel.tabCollection.tabs.compactMap { tabCollectionViewModel.tabViewModels[$0.uuid] }
        let tabs = tabViewModels.map {
            VerticalTab(id: $0.uuid, title: $0.title, favicon: $0.favicon, url: $0.url, canBePinned: $0.tabContent.canBePinned)
        }
        if self.tabs != tabs {
            self.tabs = tabs
        }
        tabCancellables = Set(tabViewModels.map(subscribeToChanges(of:)))
    }

    private func subscribeToChanges(of tabViewModel: any TabBarViewModel) -> AnyCancellable {
        let id = tabViewModel.uuid
        return tabViewModel.titleAndLoadingStatusPublisher
            .combineLatest(tabViewModel.faviconPublisher, tabViewModel.tabContentPublisher)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] titleAndLoadingStatus, favicon, content in
                self?.update(VerticalTab(id: id,
                                         title: titleAndLoadingStatus.0,
                                         favicon: favicon,
                                         url: content.urlForWebView,
                                         canBePinned: content.canBePinned))
            }
    }

    private func update(_ tab: VerticalTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }), tabs[index] != tab else { return }
        tabs[index] = tab
    }

    private func updateSelectedTabID() {
        var selectedTabID: TabIdentifier?
        if case .unpinned(let index) = tabCollectionViewModel.selectionIndex {
            selectedTabID = tabCollectionViewModel.tabCollection.tabs[safe: index]?.uuid
        }
        if self.selectedTabID != selectedTabID {
            self.selectedTabID = selectedTabID
        }
    }
}
