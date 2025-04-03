//
//  TabIndex.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Foundation

/**
 * Represents a tab position in one of the 2 sections
 * of the tab bar view (pinned or unpinned tabs).
 *
 * The associated value represents the position in a respective tab bar section.
 */
enum TabIndex: Equatable, Comparable {
    case pinned(Int), unpinned(Int)

    /**
     * Returns tab position within its respective section.
     *
     * - Note: the name follows `IndexPath.item` pattern.
     */
    var item: Int {
        switch self {
        case .pinned(let index), .unpinned(let index):
            return index
        }
    }

    var isPinnedTab: Bool {
        if case .pinned = self {
            return true
        }
        return false
    }

    var isUnpinnedTab: Bool {
        !isPinnedTab
    }

    /**
     * Creates a new tab index by incrementing position by 1.
     *
     * No bounds checking is performed.
     */
    func makeNext() -> TabIndex {
        switch self {
        case let .pinned(index):
            return .pinned(index + 1)
        case let .unpinned(index):
            return .unpinned(index + 1)
        }
    }

    func makeNextUnpinned() -> TabIndex {
        switch self {
        case .pinned:
            return .unpinned(0)
        case let .unpinned(index):
            return .unpinned(index + 1)
        }
    }

    func isInSameSection(as other: TabIndex) -> Bool {
        switch (self, other) {
        case (.pinned, .unpinned), (.unpinned, .pinned):
            return false
        default:
            return true
        }
    }

    static func < (_ lhs: TabIndex, _ rhs: TabIndex) -> Bool {
        switch (lhs, rhs) {
        case (.pinned, .unpinned):
            return true
        case (.unpinned, .pinned):
            return false
        default:
            return lhs.item < rhs.item
        }
    }
}

// MARK: - Tab Collection View Model index manipulation

extension TabIndex {

    @MainActor
    static func first(in viewModel: TabCollectionViewModel) -> TabIndex {
        if viewModel.pinnedTabsCount > 0 {
            return .pinned(0)
        }
        assert(viewModel.tabsCount > 0, "There must be at least 1 tab, pinned or unpinned")
        return .unpinned(0)
    }

    @MainActor
    static func last(in viewModel: TabCollectionViewModel) -> TabIndex {
        if viewModel.tabsCount > 0 {
            return .unpinned(viewModel.tabsCount - 1)
        }
        assert(viewModel.pinnedTabsCount > 0, "There must be at least 1 tab, pinned or unpinned")
        return .pinned(viewModel.pinnedTabsCount - 1)
    }

    @MainActor
    static func at(_ position: Int, in viewModel: TabCollectionViewModel) -> TabIndex {
        .pinned(position).sanitized(for: viewModel)
    }

    @MainActor
    func next(in viewModel: TabCollectionViewModel) -> TabIndex {
        switch self {
        case .pinned(let index):
            if index >= viewModel.pinnedTabsCount - 1 {
                return viewModel.tabsCount > 0 ? .unpinned(0) : .first(in: viewModel)
            }
            return .pinned(index + 1)
        case .unpinned(let index):
            if index >= viewModel.tabCollection.tabs.count - 1 {
                return .first(in: viewModel)
            }
            return .unpinned(index + 1)
        }
    }

    @MainActor
    func previous(in viewModel: TabCollectionViewModel) -> TabIndex {
        switch self {
        case .pinned(let index):
            if index == 0 {
                return viewModel.tabsCount > 0 ? .unpinned(viewModel.tabsCount - 1) : .pinned(viewModel.pinnedTabsCount - 1)
            }
            return .pinned(index - 1)
        case .unpinned(let index):
            if index == 0 {
                return viewModel.pinnedTabsCount > 0 ? .pinned(viewModel.pinnedTabsCount - 1) : .unpinned(viewModel.tabsCount - 1)
            }
            return .unpinned(index - 1)
        }
    }

    @MainActor
    func sanitized(for viewModel: TabCollectionViewModel) -> TabIndex {
        switch self {
        case .pinned(let index):
            if index >= viewModel.pinnedTabsCount && viewModel.tabsCount > 0 {
                return .unpinned(min(index - viewModel.pinnedTabsCount, viewModel.tabsCount - 1))
            }
            if index < 0 {
                return viewModel.pinnedTabsCount > 0 ? .pinned(0) : .unpinned(0)
            }
            return .pinned(max(0, min(index, viewModel.pinnedTabsCount - 1)))
        case .unpinned(let index):
            if index >= 0 && viewModel.tabsCount == 0 {
                return .pinned(viewModel.pinnedTabsCount - 1)
            }
            return .unpinned(max(0, min(index, viewModel.tabsCount - 1)))
        }
    }

    // MARK: - Logic when closing a tab

    /// When closing an active tab, the following rules will be used to find the appropriate tab to activate. Rules will be evaluated top to bottom and evaluation stops once a tab has been found:
    /// 1. If this tab has a parent (i.e. has been opened via "Open In New Tab"):
    ///     a. Try to find the next tab with the same parent tab
    ///     b. Try to find the previous tab with the same parent tab
    ///     c. Try to find the parent tab
    /// 2. Try to find the next tab that has the closing tab as it's parent
    /// 3. Try to find the previous tab that has the closing tab as it's parent
    /// 4. Try to find the previously active tab.
    ///     a. The previously active tab is only remembered until the user moves to an existing tab or creates new tabs.
    /// 5. Try to find the next tab
    /// 6. Try to find the previous tab
    @MainActor
    func calculateSelectedTabIndexAfterClosing(for viewModel: TabCollectionViewModel, removedTab: Tab) -> TabIndex? {
        if let parentTabId = removedTab.parentTabID {
            if let nextTabWithSameParent = findNextTabWithSameParent(for: viewModel, parentTabId: parentTabId) {
                return nextTabWithSameParent
            }

            if let previousTabWithSameParent = findPreviousTabWithSameParent(for: viewModel, parentTabId: parentTabId) {
                return previousTabWithSameParent
            }

            if let parentTab = removedTab.parentTab, let parentTabIndex = viewModel.indexInAllTabs(of: parentTab) {
                return parentTabIndex
            }
        }

        return findNewSelectionIndexWithoutParent(for: viewModel, removedTab: removedTab)
    }

    private enum SearchDirection {
        case next, previous
    }

    /// - Parameters:
    ///   - viewModel: The `TabCollectionViewModel` to search within
    ///   - parentTabId: The ID of the parent tab to find the next tab for
    /// - Returns: The `TabIndex` of the next tab with the same parent, if found
    @MainActor
    private func findNextTabWithSameParent(for viewModel: TabCollectionViewModel, parentTabId: String) -> TabIndex? {
        return findTabWithParent(for: viewModel, parentTabId: parentTabId, direction: .next)
    }

    /// - Parameters:
    ///   - viewModel: The `TabCollectionViewModel` to search within
    ///   - parentTabId: The ID of the parent tab to find the next tab for
    /// - Returns: The `TabIndex` of the previous tab with the same parent, if found
    @MainActor
    private func findPreviousTabWithSameParent(for viewModel: TabCollectionViewModel, parentTabId: String) -> TabIndex? {
        return findTabWithParent(for: viewModel, parentTabId: parentTabId, direction: .previous)
    }

    /// Finds the next or previous tab that has the given parent tab
    ///
    /// - Parameters:
    ///   - viewModel: The `TabCollectionViewModel` to search within
    ///   - parentTabId: The ID of the parent tab to find the next tab for
    ///   - direction: The direction to search in (.next or .previous)
    /// - Returns: The `TabIndex` of the first tab found with the given parent, if any
    @MainActor
    private func findTabWithParent(for viewModel: TabCollectionViewModel, parentTabId: String, direction: SearchDirection) -> TabIndex? {
        var currentIndex = self
        if let viewModelTab = viewModel.tabViewModel(at: currentIndex), viewModelTab.tab.parentTabID == parentTabId {
            return currentIndex
        }

        while let nextIndex = direction == .next ? currentIndex.getRighteousTab(for: viewModel) : currentIndex.getLeftTab(for: viewModel) {
            if let viewModelTab = viewModel.tabViewModel(at: nextIndex), viewModelTab.tab.parentTabID == parentTabId {
                return nextIndex
            }
            currentIndex = nextIndex
        }
        return nil
    }

    /// Finds the new tab index to select after closing a tab that doesn't have a parent
    ///
    /// The rules are:
    /// 1. Try to find the next tab that has the closed tab as its parent
    /// 2. Try to find the previous tab that has the closed tab as its parent
    /// 3. Try to find the recently active tab
    ///     a. The previously active tab is only remembered until the user moves to an existing tab or creates new tabs.
    /// 4. Try to find the current tab index (if it still exists)
    /// 5. Try to find the next tab
    /// 6. Try to find the previous tab
    @MainActor
    private func findNewSelectionIndexWithoutParent(for viewModel: TabCollectionViewModel, removedTab: Tab) -> TabIndex? {
        if let nextTabWithRemovedTabAsParent = findNextTabWithRemovedTabAsParent(for: viewModel, removedTab: removedTab) {
            return nextTabWithRemovedTabAsParent
        }

        if let previousTabWithRemovedTabAsParent = findPreviousTabWithRemovedTabAsParent(for: viewModel, removedTab: removedTab) {
            return previousTabWithRemovedTabAsParent
        }

        if let recentlyClosedTabIndex = viewModel.getPreviouslyActiveTab() {
            return recentlyClosedTabIndex
        }

        /// Given of the nature of when this method is called, the tab index being manipulated (self) could be the tab to the right.
        /// So we need to check for self to see if it exists, if it exists, we return it.
        if viewModel.tabViewModel(at: self) != nil {
            return self
        }

        if let nextIndex = getRighteousTab(for: viewModel) {
            return nextIndex
        }

        if let previousIndex = getLeftTab(for: viewModel) {
            return previousIndex
        }

        return nil
    }

    /// Finds the next tab that has the given removed tab as its parent
    ///
    /// - Parameters:
    ///   - viewModel: The `TabCollectionViewModel` to search within
    ///   - removedTab: The tab that was removed
    /// - Returns: The `TabIndex` of the next tab with the given removed tab as its parent, if found
    @MainActor
    private func findNextTabWithRemovedTabAsParent(for viewModel: TabCollectionViewModel, removedTab: Tab) -> TabIndex? {
        var currentIndex = self

        if let viewModelTab = viewModel.tabViewModel(at: currentIndex), viewModelTab.tab.parentTab == removedTab {
            return currentIndex
        }

        while let nextIndex = currentIndex.getRighteousTab(for: viewModel) {
            if let viewModelTab = viewModel.tabViewModel(at: nextIndex), viewModelTab.tab.parentTab == removedTab {
                return nextIndex
            }
            currentIndex = nextIndex
        }
        return nil
    }

    /// Finds the previous tab that has the given removed tab as its parent
    ///
    /// - Parameters:
    ///   - viewModel: The `TabCollectionViewModel` to search within
    ///   - removedTab: The tab that was removed
    /// - Returns: The `TabIndex` of the previous tab with the given removed tab as its parent, if found
    @MainActor
    private func findPreviousTabWithRemovedTabAsParent(for viewModel: TabCollectionViewModel, removedTab: Tab) -> TabIndex? {
        var currentIndex = self
        while let previousIndex = currentIndex.getLeftTab(for: viewModel) {
            if let viewModelTab = viewModel.tabViewModel(at: previousIndex), viewModelTab.tab.parentTab == removedTab {
                return previousIndex
            }
            currentIndex = previousIndex
        }
        return nil
    }

    /// Gets the tab to the right of the current tab index
    ///
    /// If the current tab index is the last one, returns `nil`
    @MainActor
    private func getRighteousTab(for viewModel: TabCollectionViewModel) -> TabIndex? {
        switch self {
        case .pinned(let index):
            if index >= viewModel.pinnedTabsCount - 1 {
                return viewModel.tabsCount > 0 ? .unpinned(0) : nil
            }
            return .pinned(index + 1)
        case .unpinned(let index):
            if index >= viewModel.tabCollection.tabs.count - 1 {
                return nil
            }
            return .unpinned(index + 1)
        }
    }

    /// Gets the tab to the left of the current tab index
    ///
    /// If the current tab index is the first one, returns `nil`
    @MainActor
    private func getLeftTab(for viewModel: TabCollectionViewModel) -> TabIndex? {
        switch self {
        case .pinned(let index):
            if index == 0 {
                return nil
            }
            return .pinned(index - 1)
        case .unpinned(let index):
            if index == 0 {
                return viewModel.pinnedTabsCount > 0 ? .pinned(viewModel.pinnedTabsCount - 1) : nil
            }
            return .unpinned(index - 1)
        }
    }
}

private extension TabCollectionViewModel {
    var tabsCount: Int {
        tabCollection.tabs.count
    }

    var pinnedTabsCount: Int {
        pinnedTabsCollection?.tabs.count ?? 0
    }
}
