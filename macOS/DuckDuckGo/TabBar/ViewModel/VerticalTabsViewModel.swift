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
    let canBeDuplicated: Bool
    let activePermissions: [PermissionType]

    init(_ viewModel: any TabBarViewModel) {
        id = viewModel.uuid
        title = viewModel.title
        favicon = viewModel.favicon
        url = viewModel.url
        canBePinned = viewModel.tabContent.canBePinned
        canBeDuplicated = viewModel.tabContent.canBeDuplicated
        activePermissions = viewModel.usedPermissions.activeTabIndicators
    }
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
    private let onCloseTab: (TabIndex) -> Void
    private let onTearOffTab: (Int, NSPoint) -> Void
    private let refreshPreview: (TabIdentifier) async -> NSImage?
    let openNewTab: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var tabSubscriptions: [TabIdentifier: (source: any TabBarViewModel, cancellable: AnyCancellable)] = [:]

    init(tabCollectionViewModel: TabCollectionViewModel,
         onCloseTab: @escaping (TabIndex) -> Void,
         onTearOffTab: @escaping (Int, NSPoint) -> Void,
         refreshPreview: @escaping (TabIdentifier) async -> NSImage? = { _ in nil },
         openNewTab: @escaping () -> Void) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.onCloseTab = onCloseTab
        self.onTearOffTab = onTearOffTab
        self.refreshPreview = refreshPreview
        self.openNewTab = openNewTab

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
        onCloseTab(.unpinned(index))
    }

    func closeOtherTabs(except id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        tabCollectionViewModel.removeAllTabs(except: index)
    }

    func duplicate(_ id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id),
              tabCollectionViewModel.tabCollection.tabs[index].content.canBeDuplicated else { return }
        tabCollectionViewModel.duplicateTab(at: .unpinned(index))
    }

    func pin(_ id: TabIdentifier) {
        guard let index = unpinnedIndex(of: id) else { return }
        tabCollectionViewModel.pinTab(at: index)
    }

    /// Moves a tab to another place in the list, as when it is dragged there.
    func moveTab(_ id: TabIdentifier, to index: Int) {
        guard let currentIndex = unpinnedIndex(of: id), currentIndex != index,
              tabCollectionViewModel.tabCollection.tabs.indices.contains(index) else { return }
        tabCollectionViewModel.moveTab(at: .unpinned(currentIndex), to: .unpinned(index))
    }

    func canTearOffTab(_ id: TabIdentifier) -> Bool {
        tearOffIndex(of: id) != nil
    }

    func dragPreview(for id: TabIdentifier) -> NSImage? {
        guard canTearOffTab(id), let viewModel = tabCollectionViewModel.tabViewModels[id] else { return nil }
        return TabDragPreview.makeImage(for: viewModel)
    }

    func refreshDragPreview(for id: TabIdentifier) async -> NSImage? {
        guard canTearOffTab(id), tabCollectionViewModel.selectedTab?.uuid == id else { return nil }
        return await refreshPreview(id)
    }

    func tearOffTab(_ id: TabIdentifier, at screenPoint: NSPoint) {
        guard let index = tearOffIndex(of: id) else { return }
        onTearOffTab(index, screenPoint)
    }

    private func tearOffIndex(of id: TabIdentifier) -> Int? {
        guard !tabCollectionViewModel.isBurner, let index = unpinnedIndex(of: id),
              tabCollectionViewModel.canMoveTabToNewWindow(tabIndex: .unpinned(index)) else { return nil }
        return index
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
        let viewModels = tabCollectionViewModel.tabViewModels
        // Loading or suspending a tab can replace its view model without changing its UUID.
        tabSubscriptions = tabSubscriptions.filter { viewModels[$0.key] === $0.value.source }
        let orderedViewModels = tabCollectionViewModel.tabCollection.tabs.compactMap { viewModels[$0.uuid] }
        for viewModel in orderedViewModels where tabSubscriptions[viewModel.uuid] == nil {
            tabSubscriptions[viewModel.uuid] = (viewModel, subscribeToChanges(of: viewModel))
        }
        let tabs = orderedViewModels.map(VerticalTab.init)
        if self.tabs != tabs {
            self.tabs = tabs
        }
    }

    private func subscribeToChanges(of tabViewModel: any TabBarViewModel) -> AnyCancellable {
        return tabViewModel.titleAndLoadingStatusPublisher
            .combineLatest(tabViewModel.faviconPublisher, tabViewModel.tabContentPublisher, tabViewModel.usedPermissionsPublisher)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak tabViewModel] _ in
                guard let self, let tabViewModel,
                      tabCollectionViewModel.tabViewModels[tabViewModel.uuid] === tabViewModel else { return }
                update(VerticalTab(tabViewModel))
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
