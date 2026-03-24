//
//  TabSwitcherViewController+MultiSelect.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import BrowserServicesKit
import Core
import Bookmarks
import DesignResourcesKit

// MARK: Source agnostic action implementations
extension TabSwitcherViewController {

    func bookmarkTabs(withIndexPaths indexPaths: [IndexPath], title: String, message: String,
                      pixel: Pixel.Event, dailyPixel: Pixel.Event) {

        Pixel.fire(pixel: pixel)
        DailyPixel.fire(pixel: dailyPixel)

        func tabsToBookmarks(_ controller: TabSwitcherViewController) {
            let model = MenuBookmarksViewModel(bookmarksDatabase: controller.bookmarksDatabase, syncService: controller.syncService)
            model.favoritesDisplayMode = AppDependencyProvider.shared.appSettings.favoritesDisplayMode
            let result = controller.bookmarkTabs(withIndexPaths: indexPaths, viewModel: model)
            self.displayBookmarkAllStatusMessage(with: result, openTabsCount: controller.tabsModel.tabs.count)
        }

        if indexPaths.count == 1 {
            tabsToBookmarks(self)
        } else {
            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: UserText.actionCancel, style: .cancel))
            alert.addAction(title: UserText.actionBookmark, style: .default) { [weak self] in
                guard let self else { return }
                tabsToBookmarks(self)
            }
            present(alert, animated: true, completion: nil)
        }
    }

    func bookmarkTabAt(_ indexPath: IndexPath) {
        guard let tab = tabsModel.get(tabAt: indexPath.row), let link = tab.link else { return }
        let viewModel = MenuBookmarksViewModel(bookmarksDatabase: self.bookmarksDatabase, syncService: self.syncService)
        viewModel.createBookmark(title: link.displayTitle, url: link.url)
        ActionMessageView.present(message: UserText.tabsBookmarked(withCount: 1),
                                  actionTitle: UserText.actionGenericEdit,
                                  onAction: {
            self.editBookmark(tab.link?.url)
        })
    }

    func onTabStyleChange() {
        guard isProcessingUpdates == false else { return }

        isProcessingUpdates = true
        // Idea is here to wait for any pending processing of reconfigureItems on a cells,
        // so when transition to/from grid happens we can request cells without any issues
        // related to mismatched identifiers.
        // Alternative is to use reloadItems instead of reconfigureItems but it looks very bad
        // when tabs are reloading in the background.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }

            tabSwitcherSettings.isGridViewEnabled = !tabSwitcherSettings.isGridViewEnabled

            if tabSwitcherSettings.isGridViewEnabled {
                Pixel.fire(pixel: .tabSwitcherGridEnabled)
            } else {
                Pixel.fire(pixel: .tabSwitcherListEnabled)
            }

            self.refreshDisplayModeButton()

            UIView.transition(with: view,
                              duration: 0.3,
                              options: .transitionCrossDissolve, animations: {
                self.refreshTitleViews()
                self.collectionView.reloadData()
            }, completion: { _ in
                self.isProcessingUpdates = false
            })

            self.updateUIForSelectionMode()
        }
    }

    func burn(sender: AnyObject) {
        func presentFireConfirmation() {
            let presenter = FireConfirmationPresenter(tabsModel: tabsModel,
                                                      featureFlagger: featureFlagger,
                                                      historyManager: historyManager,
                                                      fireproofing: fireproofing,
                                                      aiChatSettings: aiChatSettings,
                                                      keyValueFilesStore: keyValueStore)
            presenter.presentFireConfirmation(
                on: self,
                attachPopoverTo: sender,
                tabViewModel: nil,
                pixelSource: .tabSwitcher,
                daxDialogsManager: daxDialogsManager,
                browsingMode: selectedBrowsingMode,
                onConfirm: { [weak self] fireRequest in
                    self?.forgetAll(fireRequest)
                },
                onCancel: { }
            )
        }

        Pixel.fire(pixel: .forgetAllPressedTabSwitching)
        DailyPixel.fire(pixel: .forgetAllPressedTabSwitcherDaily)
        ViewHighlighter.hideAll()
        presentFireConfirmation()
    }

    func transitionToMultiSelect() {
        self.isEditing = true
        collectionView.reloadData()
        updateUIForSelectionMode()
        refreshTitleViews()
    }

    func transitionFromMultiSelect(reloadCollectionView: Bool = true) {
        self.isEditing = false
        if reloadCollectionView {
            collectionView.reloadData()
        }
        updateUIForSelectionMode()
        refreshTitleViews()
    }

    func closeAllTabs() {
        Pixel.fire(pixel: .tabSwitcherCloseAll)
        DailyPixel.fire(pixel: .tabSwitcherCloseAllDaily)

        let alert = UIAlertController(
            title: UserText.alertTitleCloseAllTabs(withCount: tabsModel.count),
            message: UserText.alertMessageCloseAllTabs(withCount: tabsModel.count),
            preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: UserText.closeTabs(withCount: tabsModel.count),
                                      style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.fireConfirmCloseTabsPixel()
            self.delegate?.tabSwitcherDidRequestCloseAll(tabSwitcher: self)
        })

        alert.addAction(UIAlertAction(title: UserText.actionCancel,
                                      style: .cancel) { _ in })

        present(alert, animated: true)
    }

    func closeSelectedTabs() {
        self.closeTabs(withIndexPaths: collectionView.indexPathsForSelectedItems ?? [],
                       confirmTitle: UserText.alertTitleCloseSelectedTabs(withCount: selectedTabs.count),
                       confirmMessage: UserText.alertMessageCloseTabs(withCount: selectedTabs.count))
    }

    func closeTabs(withIndexPaths indexPaths: [IndexPath], confirmTitle: String, confirmMessage: String) {

        let alert = UIAlertController(
            title: confirmTitle,
            message: confirmMessage,
            preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: UserText.actionCancel,
                                      style: .cancel) { _ in })

        alert.addAction(UIAlertAction(title: UserText.closeTabs(withCount: indexPaths.count),
                                      style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.fireConfirmCloseTabsPixel()
            self.deleteTabsAtIndexPaths(indexPaths)
        })

        present(alert, animated: true)
    }

    func fireConfirmCloseTabsPixel() {
        Pixel.fire(pixel: .tabSwitcherConfirmCloseTabs)
        DailyPixel.fire(pixel: .tabSwitcherConfirmCloseTabsDaily)
    }

    func deselectAllTabs() {
        Pixel.fire(pixel: .tabSwitcherDeselectAll)
        DailyPixel.fire(pixel: .tabSwitcherDeselectAllDaily)
        collectionView.reloadData()
        updateUIForSelectionMode()
        refreshTitleViews()
    }

    func selectAllTabs() {
        Pixel.fire(pixel: .tabSwitcherSelectAll)
        DailyPixel.fire(pixel: .tabSwitcherSelectAllDaily)
        collectionView.reloadData()
        tabsModel.tabs.indices.forEach {
            collectionView.selectItem(at: IndexPath(row: $0, section: 0), animated: true, scrollPosition: [])
        }
        updateUIForSelectionMode()
        refreshTitleViews()
    }

    func shareTabs(_ tabs: [Tab]) {
        Pixel.fire(pixel: .tabSwitcherSelectModeMenuShareLinks)
        DailyPixel.fire(pixel: .tabSwitcherSelectModeMenuShareLinksDaily)

        let sharingItems = tabs.compactMap { $0.link?.url }
        let controller = UIActivityViewController(activityItems: sharingItems, applicationActivities: nil)

        // Generically show the share sheet in the middle of the screen when on iPad
        if let popoverController = controller.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 0,
                height: 0
            )
            popoverController.permittedArrowDirections = []
        }
        present(controller, animated: true)
    }

    func closeOtherTabs(retainingIndexPaths indexPaths: [IndexPath], pixel: Pixel.Event, dailyPixel: Pixel.Event) {
        Pixel.fire(pixel: pixel)
        DailyPixel.fire(pixel: dailyPixel)

        let otherIndexPaths = Set<IndexPath>(tabsModel.tabs.indices.map {
            IndexPath(row: $0, section: 0)
        }).subtracting(indexPaths)
        
        self.closeTabs(withIndexPaths: [IndexPath](otherIndexPaths),
                       confirmTitle: UserText.alertTitleCloseOtherTabs(withCount: otherIndexPaths.count),
                       confirmMessage: UserText.alertMessageCloseOtherTabs(withCount: otherIndexPaths.count))
    }

}

// MARK: UI updating
extension TabSwitcherViewController {
    
    func updateUIForSelectionMode() {
        if AppWidthObserver.shared.isLargeWidth {
            interfaceMode = isEditing ? .editingLargeSize : .largeSize
        } else {
            interfaceMode = isEditing ? .editingRegularSize : .regularSize
        }

        let showAIChatButton = aiChatSettings.isAIChatTabSwitcherUserSettingsEnabled
        let containsWebPages = tabsModel.tabs.contains(where: { $0.link != nil })

        let state: TabSwitcherToolbarState
        if isEditing {
            state = AppWidthObserver.shared.isLargeWidth
                ? .editingLargeSize(selectedCount: selectedTabs.count, totalCount: tabsModel.count)
                : .editingRegularSize(selectedCount: selectedTabs.count, totalCount: tabsModel.count)
        } else {
            state = AppWidthObserver.shared.isLargeWidth
                ? .largeSize(selectedCount: selectedTabs.count, totalCount: tabsModel.count,
                             containsWebPages: containsWebPages, showAIChat: showAIChatButton,
                             canDismissOnEmpty: canDismissOnEmpty)
                : .regularSize(selectedCount: selectedTabs.count, totalCount: tabsModel.count,
                               containsWebPages: containsWebPages, showAIChat: showAIChatButton,
                               canDismissOnEmpty: canDismissOnEmpty)
        }

        barsHandler.update(state)
        barsHandler.configureButtonActions(tabsStyle: tabsStyle, canShowSelectionMenu: canShowSelectionMenu)

        titleBarView.topItem?.titleView = isEditing ? nil : segmentedPickerHostingController?.view
        titleBarView.topItem?.leftBarButtonItems = barsHandler.topBarLeftButtonItems
        titleBarView.topItem?.rightBarButtonItems = barsHandler.topBarRightButtonItems
        toolbar.items = barsHandler.bottomBarItems
        toolbar.isHidden = barsHandler.isBottomBarHidden
        collectionView.contentInset.bottom = barsHandler.isBottomBarHidden ? 0 : toolbar.frame.height
    }
    
    func createMultiSelectionMenu() -> UIMenu {
        let selectedIndexPaths = selectedTabs
        let selectedTabObjects = selectedIndexPaths.map { tabsModel.get(tabAt: $0.row) }.compactMap { $0 }
        let state = TabSwitcherMultiSelectMenuState(
            selectedCount: selectedTabObjects.count,
            totalCount: tabsModel.count,
            selectedContainsWebPages: selectedTabObjects.contains(where: { $0.link != nil }),
            allContainsWebPages: tabsModel.tabs.contains(where: { $0.link != nil })
        )
        canShowSelectionMenu = state.canShowSelectionMenu
        return menuBuilder.multiSelectionMenu(state: state, actions: TabSwitcherMultiSelectMenuActions(
            onDeselectAll: { [weak self] in self?.deselectAllTabs() },
            onSelectAll: { [weak self] in self?.selectAllTabs() },
            onShare: { [weak self] in self?.selectModeShareLinks() },
            onBookmarkSelected: { [weak self] in self?.selectModeBookmarkSelected() },
            onCloseOther: { [weak self] in self?.selectModeCloseOtherTabs() },
            onCloseSelected: { [weak self] in self?.selectModeCloseSelectedTabs() },
            onBookmarkAll: { [weak self] in self?.selectModeBookmarkAll() }
        ))
    }

    func createEditMenu() -> UIMenu {
        return menuBuilder.editMenu(actions: TabSwitcherEditMenuActions(
            onEnterSelectMode: { [weak self] in self?.editMenuEnterSelectMode() },
            onCloseAll: { [weak self] in self?.editMenuCloseAllTabs() }
        ))
    }

    /// Takes indexes of tabs to create long menu for.  Internally creates tab array for those
    /// indexes, then passes either tabs or indexes to the handlers to reduce [Int] -> [Tab] conversions.
    func createLongPressMenuForTabs(atIndexPaths indexPaths: [IndexPath]) -> UIMenu {
        let tabs = indexPaths.map { tabsModel.get(tabAt: $0.row) }.compactMap { $0 }
        let containsWebPages = tabs.contains(where: { $0.link != nil })

        let title = tabs.count > 1 ? UserText.numberOfSelectedTabsForMenuTitle(withCount: tabs.count)
            // If there's a single web page tab use the hostname, failing that don't provide a title
            : tabs.first?.link?.url.host?.droppingWwwPrefix() ?? ""

        let state = TabSwitcherLongPressMenuState(
            pressedCount: tabs.count,
            totalCount: tabsModel.count,
            pressedContainsWebPages: containsWebPages,
            isEditing: isEditing,
            title: title
        )
        return menuBuilder.longPressMenu(state: state, actions: TabSwitcherLongPressMenuActions(
            onShare: { [weak self] in self?.longPressMenuShareLinks(tabs: tabs) },
            onBookmark: { [weak self] in self?.longPressMenuBookmarkTabs(indexPaths: indexPaths) },
            onSelect: { [weak self] in self?.longPressMenuSelectTabs(indexPaths: indexPaths) },
            onClose: { [weak self] in self?.longPressMenuCloseTabs(indexPaths: indexPaths) },
            onCloseOther: { [weak self] in self?.longPressMenuCloseOtherTabs(retainingIndexPaths: indexPaths) }
        ))
    }

    private func shouldShowBookmarkThisPageLongPressMenuItem(_ tab: Tab, _ bookmarksModel: MenuBookmarksViewModel) -> Bool {
        return tab.link?.url != nil &&
        bookmarksModel.bookmark(for: tab.link!.url) == nil &&
        tabsModel.count > selectedTabs.count
    }

}

// MARK: Button configuration
extension TabSwitcherViewController {
    // Button configuration is now handled in TabSwitcherBarsStateHandler
    // via the setupBarButtonActions() method called in viewDidLoad()
}

// MARK: Edit menu actions
extension TabSwitcherViewController {

    func editMenuEnterSelectMode() {
        Pixel.fire(pixel: .tabSwitcherEditMenuSelectTabs)
        DailyPixel.fire(pixel: .tabSwitcherEditMenuSelectTabsDaily)
        transitionToMultiSelect()
    }

    func editMenuCloseAllTabs() {
        Pixel.fire(pixel: .tabSwitcherEditMenuCloseAllTabs)
        DailyPixel.fire(pixel: .tabSwitcherEditMenuCloseAllTabsDaily)
        closeAllTabs()
    }

}

// MARK: Select mode menu actions
extension TabSwitcherViewController {

    func selectModeCloseSelectedTabs() {
        self.closeTabs(withIndexPaths: selectedTabs,
                       confirmTitle: UserText.alertTitleCloseSelectedTabs(withCount: self.selectedTabs.count),
                       confirmMessage: UserText.alertMessageCloseTabs(withCount: self.selectedTabs.count))
    }

    func selectModeCloseOtherTabs() {
        closeOtherTabs(retainingIndexPaths: selectedTabs,
                       pixel: .tabSwitcherSelectModeMenuCloseOtherTabs,
                       dailyPixel: .tabSwitcherSelectModeMenuCloseOtherTabsDaily)
    }

    func selectModeBookmarkAll() {
        bookmarkTabs(withIndexPaths: tabsModel.tabs.indices.map { IndexPath(row: $0, section: 0) },
                     title: UserText.alertTitleBookmarkAll(withCount: tabsModel.count),
                     message: UserText.alertBookmarkAllMessage,
                     pixel: .tabSwitcherSelectModeMenuBookmarkAllTabs,
                     dailyPixel: .tabSwitcherSelectModeMenuBookmarkAllTabsDaily)
    }

    func selectModeBookmarkSelected() {
        bookmarkTabs(withIndexPaths: selectedTabs,
                     title: UserText.alertTitleBookmarkSelectedTabs(withCount: selectedTabs.count),
                     message: UserText.alertBookmarkAllMessage,
                     pixel: .tabSwitcherSelectModeMenuBookmarkTabs,
                     dailyPixel: .tabSwitcherSelectModeMenuBookmarkTabsDaily)
    }

    func selectModeShareLinks() {
        shareTabs(selectedTabs.compactMap { tabsModel.get(tabAt: $0.row) })
    }

}

// MARK: Long press menu actions
extension TabSwitcherViewController {

    func longPressMenuCloseSelectedTabs() {
        closeSelectedTabs()
    }

    func longPressMenuShareSelectedLinks() {
        shareTabs(selectedTabs.map { tabsModel.get(tabAt: $0.row) }.compactMap { $0 })
    }

    func longPressMenuBookmarkTabs(indexPaths: [IndexPath]) {
        bookmarkTabs(withIndexPaths: indexPaths,
                     title: UserText.bookmarkSelectedTabs(withCount: selectedTabs.count),
                     message: UserText.alertBookmarkAllMessage,
                     pixel: .tabSwitcherLongPressBookmarkTabs,
                     dailyPixel: .tabSwitcherLongPressBookmarkTabsDaily)
    }

    func longPressMenuShareLinks(tabs: [Tab]) {
        Pixel.fire(pixel: .tabSwitcherLongPressShare)
        shareTabs(tabs)
    }

    func longPressMenuSelectTabs(indexPaths: [IndexPath]) {
        Pixel.fire(pixel: .tabSwitcherLongPressSelectTabs)

        if !isEditing {
            transitionToMultiSelect()
        }
        
        indexPaths.forEach { path in
            collectionView.selectItem(at: path, animated: true, scrollPosition: .centeredVertically)
            (collectionView.cellForItem(at: path) as? TabViewCell)?.refreshSelectionAppearance()
        }
        updateUIForSelectionMode()
        refreshTitleViews()
    }

    func longPressMenuCloseTabs(indexPaths: [IndexPath]) {
        Pixel.fire(pixel: .tabSwitcherLongPressCloseTab)

        if indexPaths.count == 1 {
            // No confirmation for a single tab
            self.deleteTabsAtIndexPaths(indexPaths)
            return
        }
        
        let alert = UIAlertController(title: UserText.alertTitleCloseTabs(withCount: indexPaths.count),
                                      message: UserText.alertMessageCloseTabs(withCount: indexPaths.count),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: UserText.actionCancel, style: .cancel))
        alert.addAction(title: UserText.closeTabs(withCount: indexPaths.count), style: .destructive) { [weak self] in
            guard let self else { return }
            self.deleteTabsAtIndexPaths(indexPaths)
        }
        present(alert, animated: true, completion: nil)
    }

    func longPressMenuCloseOtherTabs(retainingIndexPaths indexPaths: [IndexPath]) {
        closeOtherTabs(retainingIndexPaths: indexPaths,
                       pixel: .tabSwitcherLongPressCloseOtherTabs,
                       dailyPixel: .tabSwitcherLongPressCloseOtherTabsDaily)
    }

}
