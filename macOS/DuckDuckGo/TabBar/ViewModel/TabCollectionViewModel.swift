//
//  TabCollectionViewModel.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Common
import FeatureFlags
import Foundation
import History
import os.log
import PixelKit
import PrivacyConfig
import WebKit

/**
 * The delegate callbacks taking `Int` indexes are triggered for events related to unpinned tabs only.
 * Callbacks taking `TabIndex` indexes are triggered for events related to both pinned and unpinned tabs.
 */
protocol TabCollectionViewModelDelegate: AnyObject {

    func tabCollectionViewModelDidAppend(_ tabCollectionViewModel: TabCollectionViewModel, selected: Bool)
    func tabCollectionViewModelDidInsert(_ tabCollectionViewModel: TabCollectionViewModel, at index: TabIndex, selected: Bool)
    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel,
                                didRemoveTabAt removalIndex: Int,
                                andSelectTabAt selectionIndex: Int?)
    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didReplaceTabAt index: TabIndex)
    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didMoveTabAt index: TabIndex, to newIndex: TabIndex)
    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didSelectAt selectionIndex: Int?)
    func tabCollectionViewModelDidMultipleChanges(_ tabCollectionViewModel: TabCollectionViewModel)
}

@MainActor
final class TabCollectionViewModel: NSObject {

    weak var delegate: TabCollectionViewModelDelegate?
    weak var windowControllersManager: WindowControllersManagerProtocol?

    /// Local tabs collection
    let tabCollection: TabCollection

    var tabs: [AnyTab] { tabCollection.tabs }
    var pinnedTabs: [Tab] { pinnedTabsCollection?.loadedTabs ?? [] }

    var isPopup: Bool {
        tabCollection.isPopup
    }

    /// Pinned tabs collection (provided via `PinnedTabsManager` instance).
    var pinnedTabsCollection: TabCollection? {
        if isBurner {
            return nil
        } else {
            return pinnedTabsManager?.tabCollection
        }
    }

    var allTabsCount: Int {
        if isBurner {
            return tabCollection.tabs.count
        } else {
            return (pinnedTabsCollection?.tabs.count ?? 0) + tabCollection.tabs.count
        }
    }

    let burnerMode: BurnerMode

    var changesEnabled = true

    private(set) var pinnedTabsManager: PinnedTabsManager? {
        didSet {
            subscribeToPinnedTabsManager()
        }
    }
    private(set) var pinnedTabsManagerProvider: PinnedTabsManagerProviding?

    /**
     * Contains view models for local tabs
     *
     * Pinned tabs' view models are shared between windows
     * and are available through `pinnedTabsManager`.
     */
    private(set) var tabViewModels = [TabIdentifier: any TabBarViewModel]()

    @Published private(set) var selectionIndex: TabIndex? {
        didSet {
            updateSelectedTabViewModel()
        }
    }

    /// Can point to a local or pinned tab view model.
    @Published private(set) var selectedTabViewModel: TabViewModel? {
        didSet {
            previouslySelectedTabViewModel = oldValue
            oldValue?.tab.renderTabSnapshot()

            if #available(macOS 15.4, *), let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
                if let oldValue {
                    webExtensionManager.eventsListener.didDeselectTabs([oldValue.tab])
                }
                if let selectedTabViewModel {
                    webExtensionManager.eventsListener.didSelectTabs([selectedTabViewModel.tab])
                    webExtensionManager.eventsListener.didActivateTab(selectedTabViewModel.tab,
                                                              previousActiveTab: oldValue?.tab)
                }
            }
        }
    }
    private weak var previouslySelectedTabViewModel: TabViewModel?

    private var tabLazyLoader: TabLazyLoader<TabCollectionViewModel>?
    private var isTabLazyLoadingRequested: Bool = false

    private var shouldBlockPinnedTabsManagerUpdates: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var pinnedTabsManagerCancellable: Cancellable?

    private var tabsPreferences: TabsPreferences
    private var startupPreferences: StartupPreferences
    private var accessibilityPreferences: AccessibilityPreferences
    private var homePage: Tab.TabContent {
        var homePage: Tab.TabContent = .newtab
        if startupPreferences.launchToCustomHomePage,
           let customURL = URL(string: startupPreferences.formattedCustomHomePageURL) {
            homePage = Tab.TabContent.contentFromURL(customURL, source: .bookmark(isFavorite: false))
        }
        return homePage
    }

    /// This property logic will be true when the user appends a new tab
    /// it will be set to false when the user selects an existing tab
    private var shouldReturnToPreviousActiveTab: Bool = false

    // MARK: - Popup window handling
    /// Redirects tab opening out of a popup window to the main window
    private func redirectOpenOutsidePopup(_ tab: Tab, parentTab: Tab? = nil, selected: Bool = true) {
        guard let manager = windowControllersManager else { return }
        if let parentTab = parentTab ?? tab.parentTab ?? tabCollection.tabs.first?.parentTab,
           parentTab.burnerMode == tab.burnerMode {
            manager.openTab(tab, afterParentTab: parentTab, selected: selected)
        } else {
            let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab], isPopup: false), burnerMode: tab.burnerMode)
            manager.openNewWindow(with: tabCollectionViewModel, burnerMode: tab.burnerMode, showWindow: true)
        }
    }

    private enum TabCollectionViewModelError: Error {
        case tabCollectionAtIndexNotFound(String)
        case noTabSelected
    }

    private let featureFlagger: FeatureFlagger
    private let dataClearingPixelsReporter: DataClearingPixelsReporter

    init(
        tabCollection: TabCollection,
        selectionIndex: TabIndex = .unpinned(0),
        pinnedTabsManagerProvider: PinnedTabsManagerProviding?,
        burnerMode: BurnerMode = .regular,
        startupPreferences: StartupPreferences = NSApp.delegateTyped.startupPreferences,
        tabsPreferences: TabsPreferences = NSApp.delegateTyped.tabsPreferences,
        accessibilityPreferences: AccessibilityPreferences = NSApp.delegateTyped.accessibilityPreferences,
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
        windowControllersManager: WindowControllersManagerProtocol? = nil,
        dataClearingPixelsReporter: DataClearingPixelsReporter = .init()
    ) {
        assert(!tabCollection.isPopup || windowControllersManager != nil, "Cannot create TabCollectionViewModel with a popup tab collection without a window controllers manager")
        self.tabCollection = tabCollection
        self.pinnedTabsManagerProvider = pinnedTabsManagerProvider
        self.burnerMode = burnerMode
        self.startupPreferences = startupPreferences
        self.tabsPreferences = tabsPreferences
        self.accessibilityPreferences = accessibilityPreferences
        self.featureFlagger = featureFlagger
        self.windowControllersManager = windowControllersManager
        self.dataClearingPixelsReporter = DataClearingPixelsReporter()
        super.init()

        self.pinnedTabsManager = pinnedTabsManagerProvider?.getNewPinnedTabsManager(shouldMigrate: false, tabCollectionViewModel: self, forceActive: nil)
        subscribeToTabs()
        subscribeToPinnedTabsManager()
        subscribeToPinnedTabsSettingChanged()

        if tabCollection.tabs.isEmpty {
            appendNewTab(with: homePage)
        }
        // Materialize the selected tab if unloaded — selectUnpinnedTab does this
        // on user-initiated selection, but init sets selectionIndex directly.
        if case .unloaded = tab(at: selectionIndex) {
            materialize(at: selectionIndex)
        }
        self.selectionIndex = selectionIndex
    }

    convenience init(tabCollection: TabCollection,
                     selectionIndex: TabIndex = .unpinned(0),
                     burnerMode: BurnerMode = .regular,
                     windowControllersManager: WindowControllersManagerProtocol? = nil) {
        assert(!tabCollection.isPopup || windowControllersManager != nil, "Cannot create TabCollectionViewModel with a popup tab collection without a window controllers manager")
        self.init(tabCollection: tabCollection,
                  selectionIndex: selectionIndex,
                  pinnedTabsManagerProvider: Application.appDelegate.pinnedTabsManagerProvider,
                  burnerMode: burnerMode,
                  windowControllersManager: windowControllersManager)
    }

    convenience init(isPopup: Bool, burnerMode: BurnerMode = .regular, windowControllersManager: WindowControllersManagerProtocol? = nil) {
        assert(!isPopup || windowControllersManager != nil, "Cannot create TabCollectionViewModel with a popup tab collection without a window controllers manager")
        let tabCollection = TabCollection(isPopup: isPopup)
        self.init(tabCollection: tabCollection,
                  pinnedTabsManagerProvider: Application.appDelegate.pinnedTabsManagerProvider,
                  burnerMode: burnerMode,
                  windowControllersManager: windowControllersManager)
    }

    deinit {
#if DEBUG
        // Check that the tab collection deallocates
        tabCollection.ensureObjectDeallocated(after: 1.0, do: .interrupt)

        // Only check loaded tabs and their view models — they hold expensive resources.
        // Unloaded tabs/view models are lightweight data objects and don't inherit from
        // NSObject (which ensureObjectDeallocated requires).
        for tab in tabCollection.tabs {
            if case .loaded(let tab) = tab {
                tab.ensureObjectDeallocated(after: 1.0, do: .interrupt)
            }
        }
        for viewModel in tabViewModels.values {
            if let tabViewModel = viewModel as? TabViewModel {
                tabViewModel.ensureObjectDeallocated(after: 1.0, do: .interrupt)
            }
        }
#endif
    }

    func setUpLazyLoadingIfNeeded(force: Bool = false) {
        guard force || !isTabLazyLoadingRequested else {
            Logger.tabLazyLoading.debug("Lazy loading already requested in this session, skipping.")
            return
        }

        tabLazyLoader = TabLazyLoader(dataSource: self)
        isTabLazyLoadingRequested = true

        tabLazyLoader?.lazyLoadingDidFinishPublisher
            .sink { [weak self] _ in
                self?.tabLazyLoader = nil
                Logger.tabLazyLoading.debug("Disposed of Tab Lazy Loader")
            }
            .store(in: &cancellables)

        tabLazyLoader?.scheduleLazyLoading()
    }

    func tabViewModel(at unpinnedIndex: Int) -> TabViewModel? {
        return tabViewModel(at: .unpinned(unpinnedIndex))
    }

    func tabViewModel(at index: TabIndex) -> TabViewModel? {
        switch index {
        case .unpinned(let index):
            return tabCollection.tabs[safe: index].flatMap { tabViewModels[$0.uuid] as? TabViewModel }
        case .pinned(let index):
            return pinnedTabsManager?.tabViewModel(at: index)
        }
    }

    func tabBarViewModel(at index: TabIndex) -> (any TabBarViewModel)? {
        switch index {
        case .unpinned(let index):
            return tabCollection.tabs[safe: index].flatMap { tabViewModels[$0.uuid] }
        case .pinned(let index):
            return pinnedTabsManager?.tabBarViewModel(at: index)
        }
    }

    /// This method ensures that `tabViewModels` dictionary value for `tab`
    /// has the correct type, matching the type of tab it represents.
    func updateTabBarViewModelIfNeeded(for tab: AnyTab) {
        guard let tabViewModel = tabViewModels[tab.uuid] else {
            return
        }

        if case .loaded(let loadedTab) = tab, tabViewModel is UnloadedTabViewModel {
            tabViewModels[tab.uuid] = TabViewModel(tab: loadedTab)
        } else if case .unloaded(let unloadedTab) = tab, tabViewModel is TabViewModel {
            tabViewModels[tab.uuid] = UnloadedTabViewModel(unloadedTab: unloadedTab)
        }
    }

    // MARK: - Selection

    @discardableResult func selectTab(at index: TabIndex, forceChange: Bool = false) -> Tab? {
        shouldReturnToPreviousActiveTab = false
        let result = selectWithoutResettingState(at: index, forceChange: forceChange)
        guard result else { return nil }

        let tab = materialize(at: index)
        return tab
    }

    @discardableResult func select(at index: TabIndex, forceChange: Bool = false) -> Bool {
        selectTab(at: index, forceChange: forceChange) != nil
    }

    @discardableResult func select(tab: Tab, forceChange: Bool = false) -> Bool {
        guard let index = tabCollection.firstIndex(of: tab) else {
            return false
        }
        return selectUnpinnedTab(at: index, forceChange: forceChange)
    }

    @discardableResult func selectDisplayableTabIfPresent(_ content: Tab.TabContent) -> Bool {
        guard changesEnabled else { return false }
        guard content.isDisplayable else { return false }

        let isTabCurrentlySelected = selectedTabViewModel?.tab.content.matchesDisplayableTab(content) ?? false
        if isTabCurrentlySelected {
            selectedTabViewModel?.tab.setContent(content)
            return true
        }

        guard let index = indexInAllTabs(where: { $0.content.matchesDisplayableTab(content) }),
              let tab = selectTab(at: index)
        else {
            return false
        }

        tab.setContent(content)

        return true
    }

    func selectNext() {
        guard changesEnabled else { return }
        guard allTabsCount > 0 else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: No tabs for selection")
            return
        }

        let newSelectionIndex = selectionIndex?.next(in: self) ?? .first(in: self)
        select(at: newSelectionIndex)
        if newSelectionIndex.isUnpinnedTab {
            delegate?.tabCollectionViewModel(self, didSelectAt: newSelectionIndex.item)
        }
    }

    func selectPrevious() {
        guard changesEnabled else { return }
        guard allTabsCount > 0 else {
            Logger.tabLazyLoading.debug("TabCollectionViewModel: No tabs for selection")
            return
        }

        let newSelectionIndex = selectionIndex?.previous(in: self) ?? .last(in: self)
        select(at: newSelectionIndex)
        if newSelectionIndex.isUnpinnedTab {
            delegate?.tabCollectionViewModel(self, didSelectAt: newSelectionIndex.item)
        }
    }

    @discardableResult private func selectWithoutResettingState(at index: TabIndex, forceChange: Bool = false) -> Bool {
        switch index {
        case .unpinned(let i):
            return selectUnpinnedTab(at: i, forceChange: forceChange)
        case .pinned(let i):
            return selectPinnedTab(at: i, forceChange: forceChange)
        }
    }

    @discardableResult private func selectUnpinnedTab(at index: Int, forceChange: Bool = false) -> Bool {
        guard changesEnabled || forceChange else { return false }
        guard index >= 0, index < tabCollection.tabs.count else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: Index out of bounds")
            selectionIndex = nil
            return false
        }

        // Materialize unloaded tab on selection
        if case .unloaded = tabCollection.tabs[index] {
            materialize(at: .unpinned(index))
        }

        selectionIndex = .unpinned(index)
        return true
    }

    @discardableResult private func selectPinnedTab(at index: Int, forceChange: Bool = false) -> Bool {
        guard changesEnabled || forceChange else { return false }
        guard let pinnedTabsCollection = pinnedTabsCollection else { return false }

        guard index >= 0, index < pinnedTabsCollection.tabs.count else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: Index out of bounds")
            selectionIndex = nil
            return false
        }

        pinnedTabsManager?.materializeIfNeeded(at: index)

        selectionIndex = .pinned(index)
        return true
    }

    // MARK: - Addition

    func appendNewTab(with content: Tab.TabContent = .newtab, selected: Bool = true, forceChange: Bool = false) {
        if selectDisplayableTabIfPresent(content) {
            return
        }
        let tab = makeTab(for: content)
        // Prevent multiple tabs in popup windows: redirect to parent/main window
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            redirectOpenOutsidePopup(tab, selected: selected)
            return
        }
        append(tab: tab, selected: selected, forceChange: forceChange)
    }

    @discardableResult
    func append(tab: Tab, selected: Bool = true, forceChange: Bool = false) -> Int? {
        guard changesEnabled || forceChange else { return nil }
        // Prevent multiple tabs in popup windows: redirect to parent/main window
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            redirectOpenOutsidePopup(tab, selected: selected)
            return nil
        }

        shouldReturnToPreviousActiveTab = true
        tabCollection.append(tab: tab)
        if tab.content == .newtab {
            NotificationCenter.default.post(name: HomePage.Models.newHomePageTabOpen, object: nil)
            if isBurner, featureFlagger.isFeatureOn(.subscriptionPromoFireWindow) {
                var persistor = SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
                if persistor.fireTabVisitCount < SubscriptionPromoConstants.requiredVisitCount {
                    persistor.fireTabVisitCount += 1
                }
            }
        }
        let insertionIndex = tabCollection.tabs.indices.index(before: tabCollection.tabs.endIndex)
        // Notify the delegate before updating selection — see `insert(_:at:selected:)`.
        delegate?.tabCollectionViewModelDidAppend(self, selected: selected)
        if selected {
            selectUnpinnedTab(at: insertionIndex, forceChange: forceChange)
        }
        return insertionIndex
    }

    func append(tabs: [AnyTab], andSelect shouldSelectLastTab: Bool) {
        guard changesEnabled else { return }

        // Prevent multiple tabs in popup windows: redirect each tab to parent/main window
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            for (idx, tab) in tabs.enumerated() {
                let loadedTab: Tab
                switch tab {
                case .loaded(let t): loadedTab = t
                case .unloaded(let s): loadedTab = s.materialize()
                }
                let select = shouldSelectLastTab && idx == tabs.indices.last
                redirectOpenOutsidePopup(loadedTab, selected: select)
            }
            return
        }

        tabCollection.append(tabs: tabs)
        // Notify the delegate before updating selection — see `insert(_:at:selected:)`.
        delegate?.tabCollectionViewModelDidMultipleChanges(self)
        if shouldSelectLastTab {
            let newSelectionIndex = tabCollection.tabs.count - 1
            selectUnpinnedTab(at: newSelectionIndex)
        }
    }

    func append(tabs: [Tab], andSelect shouldSelectLastTab: Bool) {
        append(tabs: tabs.map { .loaded($0) }, andSelect: shouldSelectLastTab)
    }

    func insertNewTab(after parentTab: Tab, with content: Tab.TabContent = .newtab, selected: Bool = true) {
        let tab = makeTab(for: content)
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            redirectOpenOutsidePopup(tab, parentTab: parentTab, selected: selected)
            return
        }
        insert(tab, after: parentTab, selected: selected)
    }

    func insert(_ tab: AnyTab, at index: TabIndex, selected: Bool = true) {
        guard changesEnabled else { return }
        guard let tabCollection = tabCollection(for: index) else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: Tab collection for index \(String(describing: index)) not found")
            return
        }

        // Prevent multiple tabs in popup windows: redirect to parent/main window
        if tabCollection.isPopup, !self.tabCollection.tabs.isEmpty {
            guard case .loaded(let loadedTab) = tab else { return }
            redirectOpenOutsidePopup(loadedTab, selected: selected)
            return
        }

        tabCollection.insert(tab, at: index.item)
        // Notify the delegate before updating selection: setting `selectionIndex`
        // publishes `selectedTabViewModel`, which can synchronously re-enter via
        // `TabLazyLoader` → `materialize` → `replaceTab` → `didReplaceTabAt` and
        // call `reloadItems` on the collection view while it still has the
        // pre-insert item count, raising NSInternalInconsistencyException.
        delegate?.tabCollectionViewModelDidInsert(self, at: index, selected: selected)
        if selected {
            select(at: index)
        }
    }

    func insert(_ tab: Tab, at index: TabIndex, selected: Bool = true) {
        insert(AnyTab.loaded(tab), at: index, selected: selected)
    }

    func insert(_ tab: Tab, after parentTab: Tab?, selected: Bool) {
        guard changesEnabled else { return }
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            redirectOpenOutsidePopup(tab, parentTab: parentTab, selected: selected)
            return
        }

        guard let parentTab = parentTab ?? tab.parentTab,
              let parentTabIndex = indexInAllTabs(of: parentTab) else {
            Logger.tabLazyLoading.error("TabCollection: No parent tab")
            return
        }

        // Insert at the end of the child tabs
        var newIndex = parentTabIndex.isPinnedTab ? 0 : parentTabIndex.item + 1
        while tabCollection.tabs[safe: newIndex]?.parentTab === parentTab { newIndex += 1 }
        insert(tab, at: .unpinned(newIndex), selected: selected)
    }

    func insert(_ tab: Tab, selected: Bool = true) {
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            redirectOpenOutsidePopup(tab, selected: selected)
            return
        }
        if let parentTab = tab.parentTab {
            self.insert(tab, after: parentTab, selected: selected)
        } else {
            self.insert(tab, at: .unpinned(0))
        }
    }

    func insertOrAppendNewTab(_ content: Tab.TabContent = .newtab, selected: Bool = true) {
        if selectDisplayableTabIfPresent(content) {
            return
        }

        let tab = makeTab(for: content)
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            redirectOpenOutsidePopup(tab, selected: selected)
            return
        }

        insertOrAppend(tab: tab, selected: selected)
    }

    func insertOrAppend(tab: Tab, selected: Bool) {
        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            redirectOpenOutsidePopup(tab, selected: selected)
            return
        }
        if tabsPreferences.newTabPosition == .nextToCurrent, let selectionIndex {
            self.insert(tab, at: selectionIndex.makeNextUnpinned(), selected: selected)
        } else {
            append(tab: tab, selected: selected)
        }
    }

    private func makeTab(for content: Tab.TabContent) -> Tab {
        return Tab(content: content, shouldLoadInBackground: true, burnerMode: burnerMode)
    }

    // MARK: - Removal

    func removeAll(with content: Tab.TabContent) {
        let matchingTabs = tabCollection.tabs.filter { $0.content == content }
        for tab in matchingTabs {
            if let index = indexInAllTabs(of: tab) {
                remove(at: index)
            }
        }
    }

    func removeAll(matching condition: (Tab.TabContent) -> Bool) {
        let matchingTabs = tabCollection.tabs.filter { condition($0.content) }
        for tab in matchingTabs {
            if let index = indexInAllTabs(of: tab) {
                remove(at: index)
            }
        }
    }

    func remove(at index: TabIndex, published: Bool = true, forceChange: Bool = false) {
        switch index {
        case .unpinned(let i):
            return removeUnpinnedTab(at: i, published: published, forceChange: forceChange)
        case .pinned(let i):
            return removePinnedTab(at: i, published: published)
        }
    }

    private func removeUnpinnedTab(at index: Int, published: Bool = true, forceChange: Bool = false) {
        guard changesEnabled || forceChange else { return }

        let removedTab = tabCollection.tabs[safe: index]
        let parentTab = removedTab?.parentTab
        guard tabCollection.removeTab(at: index, published: published, forced: forceChange) else { return }

        didRemoveTab(removedTab!,
                     at: .unpinned(index),
                     withParent: parentTab,
                     forced: forceChange)
    }

    private func removePinnedTab(at index: Int, published: Bool = true) {
        guard changesEnabled else { return }
        shouldBlockPinnedTabsManagerUpdates = true
        defer {
            shouldBlockPinnedTabsManagerUpdates = false
        }
        guard let removedTab = pinnedTabsManager?.unpinTab(at: index, published: published) else { return }

        didRemoveTab(removedTab, at: .pinned(index), withParent: nil)
    }

    private func didRemoveTab(_ tab: AnyTab, at index: TabIndex, withParent parentTab: Tab?, forced: Bool = false) {

        func notifyDelegate() {
            if index.isUnpinnedTab {
                let newSelectionIndex = self.selectionIndex?.isUnpinnedTab == true ? self.selectionIndex?.item : nil
                delegate?.tabCollectionViewModel(self, didRemoveTabAt: index.item, andSelectTabAt: newSelectionIndex)
            }
        }

        guard allTabsCount > 0 else {
            selectionIndex = nil
            notifyDelegate()
            return
        }

        guard let selectionIndex else {
            Logger.tabLazyLoading.error("TabCollection: No tab selected")
            notifyDelegate()
            return
        }

        let newSelectionIndex: TabIndex

        if index == selectionIndex, let calculatedIndex = selectionIndex.calculateSelectedTabIndexAfterClosing(for: self, removedTab: tab) {
            newSelectionIndex = calculatedIndex
        } else if selectionIndex > index, selectionIndex.isInSameSection(as: index) {
            newSelectionIndex = selectionIndex.previous(in: self)
        } else {
            newSelectionIndex = selectionIndex.sanitized(for: self)
        }

        notifyDelegate()
        select(at: newSelectionIndex, forceChange: forced)
    }

    func getPreviouslyActiveTab() -> TabIndex? {
        guard shouldReturnToPreviousActiveTab else {
            return nil
        }

        let recentlyOpenedPinnedTab = (pinnedTabsCollection?.tabs ?? []).max(by: { $0.lastSelectedAt ?? Date.distantPast < $1.lastSelectedAt ?? Date.distantPast })
        let recentlyOpenedNormalTab = tabCollection.tabs.max(by: { $0.lastSelectedAt ?? Date.distantPast < $1.lastSelectedAt ?? Date.distantPast })

        if let pinnedTab = recentlyOpenedPinnedTab, let normalTab = recentlyOpenedNormalTab {
            if pinnedTab.lastSelectedAt ?? Date.distantPast > normalTab.lastSelectedAt ?? Date.distantPast {
                return indexInAllTabs(of: pinnedTab)
            } else {
                return indexInAllTabs(of: normalTab)
            }
        } else if let pinnedTab = recentlyOpenedPinnedTab {
            return indexInAllTabs(of: pinnedTab)
        } else if let normalTab = recentlyOpenedNormalTab {
            return indexInAllTabs(of: normalTab)
        } else {
            return nil
        }
    }

    func moveTab(at fromIndex: Int, to otherViewModel: TabCollectionViewModel, at toIndex: Int) {
        moveTab(at: .unpinned(fromIndex), to: otherViewModel, at: .unpinned(toIndex))
    }

    func moveTab(at fromIndex: TabIndex, to otherViewModel: TabCollectionViewModel, at toIndex: TabIndex) {
        assert(self !== otherViewModel)
        guard changesEnabled else { return }

        guard let sourceCollection = tabCollection(for: fromIndex), let targetCollection = otherViewModel.tabCollection(for: toIndex) else {
            return
        }

        guard let movedTab = sourceCollection.tabs[safe: fromIndex.item] else {
            return
        }

        let parentTab = movedTab.parentTab
        guard sourceCollection.moveTab(at: fromIndex.item, to: targetCollection, at: toIndex.item) else {
            return
        }

        didRemoveTab(movedTab, at: fromIndex, withParent: parentTab)

        otherViewModel.selectWithoutResettingState(at: toIndex)
        otherViewModel.delegate?.tabCollectionViewModelDidInsert(otherViewModel, at: toIndex, selected: true)
    }

    func removeAllTabs(except exceptionIndex: Int? = nil, forceChange: Bool = false) {
        guard changesEnabled || forceChange else { return }

        if let exceptionTab = exceptionIndex.flatMap({ tabCollection.tabs[$0] }) {
            tabCollection.removeAll(andAppend: exceptionTab)
        } else {
            tabCollection.removeAll()
        }

        if exceptionIndex != nil {
            selectUnpinnedTab(at: 0, forceChange: forceChange)
        } else {
            selectionIndex = nil
        }
        delegate?.tabCollectionViewModelDidMultipleChanges(self)
    }

    func removeTabs(before index: Int) {
        guard changesEnabled else { return }

        tabCollection.removeTabs(before: index)

        if let currentSelection = selectionIndex, currentSelection.isUnpinnedTab {
            if currentSelection.item < index {
                selectionIndex = .unpinned(0)
            } else {
                selectionIndex = .unpinned(currentSelection.item - index)
            }
        }

        delegate?.tabCollectionViewModelDidMultipleChanges(self)
    }

    func removeTabs(after index: Int) {
        guard changesEnabled else { return }

        tabCollection.removeTabs(after: index)

        if let currentSelection = selectionIndex, currentSelection.isUnpinnedTab, !tabCollection.tabs.indices.contains(currentSelection.item) {
            selectionIndex = .unpinned(tabCollection.tabs.count - 1)
        }

        delegate?.tabCollectionViewModelDidMultipleChanges(self)
    }

    func removeSelected(forceChange: Bool = false) -> Result<Void, Error> {
        guard changesEnabled || forceChange else { return .success(()) }

        guard let selectionIndex else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: No tab selected")
            return .failure(TabCollectionViewModelError.noTabSelected)
        }

        remove(at: selectionIndex, forceChange: forceChange)
        return .success(())
    }

    // MARK: - Others

    func duplicateTab(at tabIndex: TabIndex) {
        guard changesEnabled else { return }

        guard let tab = tab(at: tabIndex) else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: Index out of bounds")
            return
        }

        if tabCollection.isPopup, !tabCollection.tabs.isEmpty {
            guard let loadedTab = materialize(at: tabIndex) else { return }
            redirectOpenOutsidePopup(loadedTab)
            return
        }

        let tabCopy = Tab(
            content: tab.content.loadedFromCache(),
            title: tab.title,
            favicon: tab.favicon,
            interactionStateData: tab.interactionStateData,
            shouldLoadInBackground: true,
            burnerMode: tab.burnerMode
        )
        let newIndex = tabIndex.makeNext()

        tabCollection(for: tabIndex)?.insert(tabCopy, at: newIndex.item)
        select(at: newIndex)

        delegate?.tabCollectionViewModelDidInsert(self, at: newIndex, selected: true)
    }

    func pinTab(at index: Int) {
        guard changesEnabled else { return }
        guard let pinnedTabsCollection = pinnedTabsCollection else { return }

        guard index >= 0, index < tabCollection.tabs.count else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: Index out of bounds")
            return
        }

        // Materialize if unloaded — pinned tabs must always be loaded
        guard let tab = materialize(at: .unpinned(index)) else { return }

        pinnedTabsManager?.pin(tab)
        removeUnpinnedTab(at: index, published: false)
        selectPinnedTab(at: pinnedTabsCollection.tabs.count - 1)
    }

    func unpinTab(at index: Int) {
        guard changesEnabled else { return }
        shouldBlockPinnedTabsManagerUpdates = true
        defer {
            shouldBlockPinnedTabsManagerUpdates = false
        }

        guard let tab = pinnedTabsManager?.unpinTab(at: index, published: false) else {
            Logger.tabLazyLoading.error("Unable to unpin a tab")
            return
        }

        insert(tab, at: .unpinned(0))
    }

    @discardableResult
    func suspendTab(at tabIndex: TabIndex) -> Bool {
        guard changesEnabled else { return false }
        guard !isBurner else {
            assertionFailure("Cannot suspend a burner tab")
            return false
        }
        guard let oldTab = tab(at: tabIndex) else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: Index out of bounds")
            return false
        }
        guard tabIndex != selectionIndex else { return false }
        guard case .loaded(let loadedTab) = oldTab, loadedTab.tabSuspension?.canBeSuspended == true else { return false }
        let suspendedTab = loadedTab.makeSuspendedTab()

        _ = replaceTab(at: tabIndex, with: .unloaded(suspendedTab))
        return true
    }

    /// This method is only called from the "Resume Tab" debug option in tab context menu
    func resumeTab(at tabIndex: TabIndex) {
        guard changesEnabled else { return }
        if let tab = materialize(at: tabIndex) {
            // Reload is called here only to trigger loading a page (simulate selection).
            // In real world, tabs are resumed on selection which triggers reloading (via private reloadIfNeeded).
            tab.reload()
        }
    }

    func title(forTabWithURL url: URL) -> String? {
        let matchingTab = tabCollection.tabs.first { tab in
            tab.url == url
        }
        return matchingTab?.title
    }

    private func handleTabUnpinnedInAnotherTabCollectionViewModel(at index: Int) {
        if selectionIndex == .pinned(index), let tab = tab(at: .pinned(index)) {
            didRemoveTab(tab, at: .pinned(index), withParent: nil)
        }
    }

    func moveTab(at index: TabIndex, to newIndex: TabIndex) {
        guard changesEnabled, index.isInSameSection(as: newIndex), let tabCollection = tabCollection(for: index) else { return }

        tabCollection.moveTab(at: index.item, to: newIndex.item)
        selectWithoutResettingState(at: newIndex)

        delegate?.tabCollectionViewModel(self, didMoveTabAt: index, to: newIndex)
    }

    func replaceTab(at index: TabIndex, with tab: Tab, forceChange: Bool = false, keepHistory: Bool = true) -> Result<Void, Error> {
        return replaceTab(at: index, with: .loaded(tab), forceChange: forceChange, keepHistory: keepHistory)
    }

    func replaceTab(at index: TabIndex, with tab: AnyTab, forceChange: Bool = false, keepHistory: Bool = true) -> Result<Void, Error> {
        guard changesEnabled || forceChange else { return .success(()) }
        guard let tabCollection = tabCollection(for: index) else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: Tab collection for index \(String(describing: index)) not found")
            return .failure(TabCollectionViewModelError.tabCollectionAtIndexNotFound(String(describing: index)))
        }

        tabCollection.replaceTab(at: index.item, with: tab, keepHistory: keepHistory)
        updateTabBarViewModelIfNeeded(for: tab)

        guard let selectionIndex else {
            Logger.tabLazyLoading.error("TabCollectionViewModel: No tab selected")
            return .failure(TabCollectionViewModelError.noTabSelected)
        }
        if index == selectionIndex {
            // only reselect if we've replaced a selected tab
            select(at: selectionIndex, forceChange: forceChange)
        }

        delegate?.tabCollectionViewModel(self, didReplaceTabAt: index)
        return .success(())
    }

    private func subscribeToPinnedTabsSettingChanged() {
        pinnedTabsManagerProvider?.settingChangedPublisher
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.pinnedTabsManager = self.pinnedTabsManagerProvider?.getNewPinnedTabsManager(shouldMigrate: true, tabCollectionViewModel: self, forceActive: nil)
            }.store(in: &cancellables)
    }

    private func subscribeToPinnedTabsManager() {
        pinnedTabsManagerCancellable = pinnedTabsManager?.didUnpinTabPublisher
            .filter { [weak self] _ in self?.shouldBlockPinnedTabsManagerUpdates == false }
            .sink { [weak self] index in
                self?.handleTabUnpinnedInAnotherTabCollectionViewModel(at: index)
            }
    }

    private func subscribeToTabs() {
        tabCollection.$tabs.sink { [weak self] newTabs in
            guard let self = self else { return }

            let newUUIDs = Set(newTabs.map(\.uuid))
            let oldUUIDs = Set(self.tabViewModels.keys)

            let removedUUIDs = oldUUIDs.subtracting(newUUIDs)
            for uuid in removedUUIDs {
                self.tabViewModels[uuid] = nil
            }

            let addedUUIDs = newUUIDs.subtracting(oldUUIDs)
            for tab in newTabs where addedUUIDs.contains(tab.uuid) {
                switch tab {
                case .loaded(let tab):
                    self.tabViewModels[tab.uuid] = TabViewModel(tab: tab)
                case .unloaded(let unloaded):
                    self.tabViewModels[unloaded.uuid] = UnloadedTabViewModel(unloadedTab: unloaded)
                }
            }

            // Make sure the tab is burner if it is supposed to be
            if newTabs.first(where: { $0.burnerMode != self.burnerMode }) != nil {
                PixelKit.fire(DebugEvent(GeneralPixel.burnerTabMisplaced))
                fatalError("Error in burner tab management")
            }
        } .store(in: &cancellables)
    }

    private func updateSelectedTabViewModel() {
        guard let selectionIndex else {
            selectedTabViewModel = nil
            return
        }

        let tabCollection = self.tabCollection(for: selectionIndex)
        var selectedTabViewModel: TabViewModel?

        switch tabCollection {
        case self.tabCollection:
            selectedTabViewModel = tabViewModel(at: .unpinned(selectionIndex.item))
        case pinnedTabsCollection:
            selectedTabViewModel = tabViewModel(at: .pinned(selectionIndex.item))
        default:
            break
        }

        if self.selectedTabViewModel !== selectedTabViewModel {
            selectedTabViewModel?.tab.lastSelectedAt = Date()
            self.selectedTabViewModel = selectedTabViewModel
        }
    }

    /// Clears tabViewModels and tabCollection after the tabs were moved to another collection
    func clearAfterMerge() {
        tabViewModels.removeAll()
        tabCollection.clearAfterMerge()
    }
}

extension TabCollectionViewModel {

    private func tabCollection(for selection: TabIndex) -> TabCollection? {
        switch selection {
        case .unpinned:
            return tabCollection
        case .pinned:
            return pinnedTabsCollection
        }
    }

    func indexInAllTabs(of tab: Tab) -> TabIndex? {
        if let index = pinnedTabsCollection?.firstIndex(of: tab) {
            return .pinned(index)
        }
        if let index = tabCollection.firstIndex(of: tab) {
            return .unpinned(index)
        }
        return nil
    }

    func indexInAllTabs(of tab: AnyTab) -> TabIndex? {
        if let index = pinnedTabsCollection?.tabs.firstIndex(where: { $0.uuid == tab.uuid }) {
            return .pinned(index)
        }
        if let index = tabCollection.tabs.firstIndex(where: { $0.uuid == tab.uuid }) {
            return .unpinned(index)
        }
        return nil
    }

    func indexInAllTabs(where condition: (AnyTab) -> Bool) -> TabIndex? {
        if let index = pinnedTabsCollection?.tabs.firstIndex(where: condition) {
            return .pinned(index)
        }
        if let index = tabCollection.tabs.firstIndex(where: condition) {
            return .unpinned(index)
        }
        return nil
    }

    private func tab(at tabIndex: TabIndex) -> AnyTab? {
        switch tabIndex {
        case .pinned(let index):
            return pinnedTabsCollection?.tabs[safe: index]
        case .unpinned(let index):
            return tabCollection.tabs[safe: index]
        }
    }

    /// Materializes an unloaded tab into a full Tab.
    /// If already loaded, returns the existing Tab.
    @discardableResult
    func materialize(at index: TabIndex) -> Tab? {
        guard let tab = tab(at: index) else {
            return nil
        }
        switch tab {
        case .loaded(let tab):
            return tab
        case .unloaded(let unloaded):
            Logger.tabLazyLoading.debug("Materializing unloaded tab \(unloaded.uuid) at \(String(reflecting: index))")
            let tab = unloaded.materialize()
            _ = replaceTab(at: index, with: tab, keepHistory: false)
            return tab
        }
    }
}

extension TabCollectionViewModel {

    var localHistory: [Visit] {
        var history = tabCollection.localHistory
        history += tabCollection.localHistoryOfRemovedTabs
        if pinnedTabsCollection != nil {
            history += pinnedTabsCollection?.localHistory ?? []
            history += pinnedTabsCollection?.localHistoryOfRemovedTabs ?? []
        }
        return history
    }

    var localHistoryDomains: Set<String> {
        var historyDomains = tabCollection.localHistoryDomains
        historyDomains.formUnion(tabCollection.localHistoryDomainsOfRemovedTabs)
        if let pinnedTabs = pinnedTabsCollection {
            historyDomains.formUnion(pinnedTabs.localHistoryDomains)
            historyDomains.formUnion(pinnedTabs.localHistoryDomainsOfRemovedTabs)
        }
        return historyDomains
    }

    func clearLocalHistory(keepingCurrent: Bool) {
        tabCollection.tabs.forEach { $0.clearNavigationHistory(keepingCurrent: keepingCurrent) }
        pinnedTabsManager?.tabCollection.tabs.forEach { $0.clearNavigationHistory(keepingCurrent: keepingCurrent) }
        tabCollection.localHistoryOfRemovedTabs.removeAll()
        tabCollection.removedTabDomains.removeAll()
        pinnedTabsManager?.tabCollection.localHistoryOfRemovedTabs.removeAll()
        pinnedTabsManager?.tabCollection.removedTabDomains.removeAll()
    }

}

extension TabCollectionViewModel {

    var isBurner: Bool {
        burnerMode.isBurner
    }

}

// MARK: - Bookmark All Open Tabs

extension TabCollectionViewModel {

    func canBookmarkAllOpenTabs() -> Bool {
        tabCollection.tabs.filter { $0.content.canBeBookmarked }.count >= 2
    }

}

// MARK: - New Windows Logic

extension TabCollectionViewModel {

    func canMoveSelectedTabToNewWindow() -> Bool {
        guard let selectionIndex else {
            return false
        }

        return canMoveTabToNewWindow(tabIndex: selectionIndex)
    }

    func canMoveTabToNewWindow(tabIndex: TabIndex) -> Bool {
        let pinnedTabsCount = pinnedTabsCollection?.tabs.count ?? 0
        let unpinnedTabsCount = tabCollection.tabs.count

        return tabIndex.isUnpinnedTab && (unpinnedTabsCount > 1 || pinnedTabsCount > 0)
    }
}
