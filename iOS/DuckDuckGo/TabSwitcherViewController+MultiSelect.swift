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
import DesignResourcesKitIcons

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
        guard let tab = tabsModel.safeGetTabAt(indexPath.row), let link = tab.link else { return }
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
                self.refreshTitle()
                self.collectionView.reloadData()
            }, completion: { _ in
                self.isProcessingUpdates = false
            })

            self.updateUIForSelectionMode()
        }
    }

    func burn(sender: AnyObject) {
        func presentForgetDataAlert() {
            let alert = ForgetDataAlert.buildAlert(forgetTabsAndDataHandler: { [weak self] in
                self?.forgetAll()
            })

            if let view = sender as? UIView {
                self.present(controller: alert, fromView: view)
            } else if let button = sender as? UIBarButtonItem {
                self.present(controller: alert, fromButtonItem: button)
            } else {
                assertionFailure("Unexpected sender")
            }
        }

        Pixel.fire(pixel: .forgetAllPressedTabSwitching)
        ViewHighlighter.hideAll()
        presentForgetDataAlert()
    }

    func addNewTab() {
        guard !isProcessingUpdates else { return }

        Pixel.fire(pixel: .tabSwitcherNewTab)
        delegate.tabSwitcherDidRequestNewTab(tabSwitcher: self)
        dismiss()
    }

    func transitionToMultiSelect() {
        self.isEditing = true
        collectionView.reloadData()
        updateUIForSelectionMode()
    }

    func transitionFromMultiSelect() {
        self.isEditing = false
        collectionView.reloadData()
        updateUIForSelectionMode()
        refreshTitle()
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
    }

    func selectAllTabs() {
        Pixel.fire(pixel: .tabSwitcherSelectAll)
        DailyPixel.fire(pixel: .tabSwitcherSelectAllDaily)
        collectionView.reloadData()
        tabsModel.tabs.indices.forEach {
            collectionView.selectItem(at: IndexPath(row: $0, section: 0), animated: true, scrollPosition: [])
        }
        updateUIForSelectionMode()
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

        barsHandler.update(interfaceMode,
                           selectedTabsCount: selectedTabs.count,
                           totalTabsCount: tabsModel.count,
                           containsWebPages: tabsModel.tabs.contains(where: { $0.link != nil }),
                           showAIChatButton: aiChatSettings.isAIChatTabSwitcherUserSettingsEnabled)

        topBarView.topItem?.leftBarButtonItems = barsHandler.topBarLeftButtonItems
        topBarView.topItem?.rightBarButtonItems = barsHandler.topBarRightButtonItems
        toolbar.items = barsHandler.bottomBarItems
        toolbar.isHidden = barsHandler.isBottomBarHidden
        collectionView.contentInset.bottom = barsHandler.isBottomBarHidden ? 0 : toolbar.frame.height

        refreshBarButtons()
    }
    
    func createMultiSelectionMenu() -> UIMenu {

        let otherTabCount = max(0, tabsModel.count - selectedTabs.count)
        let selectedTabs = selectedTabs.map { self.tabsModel.safeGetTabAt($0.row) }.compactMap { $0 }
        let selectedTabsContainsWebPages = selectedTabs.contains(where: { $0.link != nil })
        let canShare = selectedTabsContainsWebPages
        let canAddBookmarks = selectedTabsContainsWebPages
        let canCloseOther = !selectedTabs.isEmpty && otherTabCount > 0
        let canBookmarkAll = selectedTabs.isEmpty && self.tabsModel.tabs.contains(where: { $0.link != nil })
        let canShowDeselectAll = interfaceMode.isLarge && selectedTabs.count == tabsModel.count
        let canShowSelectAll = interfaceMode.isLarge && selectedTabs.count < tabsModel.count
        let canClose = interfaceMode.isLarge && selectedTabs.count > 0

        let items = [

            UIMenu(title: "", options: .displayInline, children: [
                canShowDeselectAll ? action(UserText.deselectAllTabs, DesignSystemImages.Glyphs.Size16.checkCircle, { [weak self] in
                    self?.deselectAllTabs()
                }) : nil,
                canShowSelectAll ? action(UserText.selectAllTabs, DesignSystemImages.Glyphs.Size16.checkCircle, { [weak self] in
                    self?.selectAllTabs()
                }) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                canShare ? action(UserText.shareLinks(withCount: selectedTabs.count), DesignSystemImages.Glyphs.Size16.shareApple, { [weak self] in
                    self?.selectModeShareLinks()
                }) : nil,
                canAddBookmarks ? action(UserText.bookmarkSelectedTabs(withCount: selectedTabs.count), DesignSystemImages.Glyphs.Size16.bookmarkAdd, { [weak self] in
                    self?.selectModeBookmarkSelected()
                }) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                // Always use plural here
                canCloseOther ? destructive(UserText.tabSwitcherCloseOtherTabs(withCount: 2), DesignSystemImages.Glyphs.Size16.tabCloseAlt, { [weak self] in
                    self?.selectModeCloseOtherTabs()
                }) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                canClose ? destructive(UserText.closeTabs(withCount: selectedTabs.count), imageForCloseTabs(selectedTabs.count), { [weak self] in
                    self?.selectModeCloseSelectedTabs()
                }) : nil,
            ].compactMap { $0 }),

            UIMenu(title: "", options: .displayInline, children: [
                canBookmarkAll ? action(UserText.tabSwitcherBookmarkAllTabs, DesignSystemImages.Glyphs.Size16.bookmarkAll, { [weak self] in
                    self?.selectModeBookmarkAll()
                }) : nil,
            ].compactMap { $0 })
        ]

        canShowSelectionMenu = !items.allSatisfy(\.children.isEmpty)

        let deferredElement = UIDeferredMenuElement.uncached { completion in
            Pixel.fire(pixel: .tabSwitcherSelectModeMenuClicked)
            completion(items)
        }

        return UIMenu(title: "", children: [
            deferredElement
        ])
    }
    
    func createEditMenu() -> UIMenu {
        let items = [
            // Force plural version for the menu - this really means "switch to select tabs mode"
            action(UserText.tabSwitcherSelectTabs(withCount: 2), DesignSystemImages.Glyphs.Size16.checkCircle, { [weak self] in
                self?.editMenuEnterSelectMode()
            }),

            UIMenu(title: "", options: [.displayInline], children: [
                destructive(UserText.closeAllTabs, DesignSystemImages.Glyphs.Size16.tabCloseAlt, { [weak self] in
                    self?.editMenuCloseAllTabs()
                })
            ]),
        ]

        let deferredElement = UIDeferredMenuElement.uncached { completion in
            Pixel.fire(pixel: .tabSwitcherEditMenuClicked)
            completion(items)
        }

        return UIMenu(children: [
            deferredElement
        ])
    }

    /// Takes indexes of tabs to create long menu for.  Interally creates tab array for those indexes, then passes either tabs or indexes to the handles in order to try and reduce the amount of
    ///  converting from [Int] -> [Tab] operations.
    func createLongPressMenuForTabs(atIndexPaths indexPaths: [IndexPath]) -> UIMenu {
        let tabs = indexPaths.map { tabsModel.safeGetTabAt($0.row) }.compactMap { $0 }
        let containsWebPages = tabs.contains(where: { $0.link != nil })
    
        let title = tabs.count > 1 ? UserText.numberOfSelectedTabsForMenuTitle(withCount: tabs.count)
            // If there's a single web page tab use the hostname, failing that don't provide a title
            : tabs.first?.link?.url.host?.droppingWwwPrefix() ?? ""
        
        let canCloseOthers = tabs.count < tabsModel.count
        
        // Show selection if it's a single tab, but NOT if it's the home page in selection mode ¯\_(ツ)_/¯
        // See point 3: https://app.asana.com/0/1209499866654340/1209424833903137
        // See point 4: https://app.asana.com/0/1209499866654340/1209424833902043
        // Also: https://app.asana.com/0/1209499866654340/1209503836757555
        let canSelect = !isEditing && tabs.count == 1 && (containsWebPages || !isEditing)
        
        return UIMenu(title: title, children: [
            UIMenu(title: "", options: .displayInline, children: [
                containsWebPages ? action(UserText.shareLinks(withCount: tabs.count), DesignSystemImages.Glyphs.Size16.shareApple, { [weak self] in
                    self?.longPressMenuShareLinks(tabs: tabs)
                }) : nil,
                containsWebPages ? action(UserText.bookmarkSelectedTabs(withCount: tabs.count), DesignSystemImages.Glyphs.Size16.bookmarkAdd, { [weak self] in
                    self?.longPressMenuBookmarkTabs(indexPaths: indexPaths)
                }) : nil,
                canSelect ? action(UserText.tabSwitcherSelectTabs(withCount: 1), DesignSystemImages.Glyphs.Size16.checkCircle, { [weak self] in
                    self?.longPressMenuSelectTabs(indexPaths: indexPaths)
                }) : nil,
            ].compactMap { $0 }),
            
            UIMenu(title: "", options: .displayInline, children: [
                destructive(UserText.closeTabs(withCount: tabs.count), imageForCloseTabs(tabs.count), { [weak self] in
                    self?.longPressMenuCloseTabs(indexPaths: indexPaths)
                })
            ]),

            UIMenu(title: "", options: .displayInline, children: [
                // Always use plural here
                canCloseOthers ? destructive(UserText.tabSwitcherCloseOtherTabs(withCount: 2), imageForCloseTabs(2), { [weak self] in
                    self?.longPressMenuCloseOtherTabs(retainingIndexPaths: indexPaths)
                }) : nil
            ].compactMap { $0 }),
        ].compactMap { $0 })
    }

    private func imageForCloseTabs(_ count: Int) -> UIImage {
        return count < 2 ?
            DesignSystemImages.Glyphs.Size16.closeOutline :
            DesignSystemImages.Glyphs.Size16.tabCloseAlt
    }

    private func shouldShowBookmarkThisPageLongPressMenuItem(_ tab: Tab, _ bookmarksModel: MenuBookmarksViewModel) -> Bool {
        return tab.link?.url != nil &&
        bookmarksModel.bookmark(for: tab.link!.url) == nil &&
        tabsModel.count > selectedTabs.count
    }

}

// MARK: Button configuration
extension TabSwitcherViewController {

    func refreshBarButtons() {
        barsHandler.tabSwitcherStyleButton.accessibilityLabel = tabsStyle.accessibilityLabel
        barsHandler.tabSwitcherStyleButton.primaryAction = action(image: tabsStyle.image, { [weak self] in
            guard let self else { return }
            self.onTabStyleChange()
        })
        barsHandler.tabSwitcherStyleButton.tintColor = UIColor(designSystemColor: .icons)

        barsHandler.addAllBookmarksButton.accessibilityLabel = UserText.bookmarkAllTabs
        barsHandler.addAllBookmarksButton.primaryAction = action(image: DesignSystemImages.Glyphs.Size24.bookmarkNew) { [weak self] in
            self?.bookmarkTabs(withIndexPaths: self!.tabsModel.tabs.indices.map { IndexPath(row: $0, section: 0) },
                               title: UserText.alertTitleBookmarkAll(withCount: self!.tabsModel.count),
                               message: UserText.alertBookmarkAllMessage,
                               pixel: .tabSwitcherSelectModeMenuBookmarkAllTabs,
                               dailyPixel: .tabSwitcherSelectModeMenuBookmarkAllTabsDaily)
        }

        barsHandler.plusButton.accessibilityLabel = UserText.keyCommandNewTab
        barsHandler.plusButton.primaryAction = action(image: DesignSystemImages.Glyphs.Size24.add, { [weak self] in
            self?.addNewTab()
        })

        barsHandler.fireButton.accessibilityLabel = "Close all tabs and clear data"
        barsHandler.fireButton.primaryAction = action(image: DesignSystemImages.Glyphs.Size24.fireSolid) { [weak self] in
            self?.burn(sender: self!.barsHandler.fireButton)
        }

        barsHandler.doneButton.primaryAction = action(UserText.navigationTitleDone) { [weak self] in
            self?.onDonePressed(self!.barsHandler.doneButton)
        }

        barsHandler.editButton.title = UserText.actionGenericEdit
        barsHandler.editButton.menu = createEditMenu()

        barsHandler.selectAllButton.primaryAction = action(UserText.selectAllTabs) { [weak self] in
            self?.selectAllTabs()
        }

        barsHandler.deselectAllButton.primaryAction = action(UserText.deselectAllTabs) { [weak self] in
            self?.deselectAllTabs()
        }

        barsHandler.menuButton.accessibilityLabel = "More Menu"
        barsHandler.menuButton.image = DesignSystemImages.Glyphs.Size24.moreApple
        barsHandler.menuButton.tintColor = UIColor(designSystemColor: .icons)
        barsHandler.menuButton.menu = createMultiSelectionMenu()
        barsHandler.menuButton.isEnabled = canShowSelectionMenu

        barsHandler.closeTabsButton.isEnabled = selectedTabs.count > 0
        barsHandler.closeTabsButton.primaryAction = action(UserText.closeTabs(withCount: selectedTabs.count)) { [weak self] in
            self?.closeSelectedTabs()
        }

        barsHandler.duckChatButton.tintColor = UIColor(designSystemColor: .icons)
        barsHandler.duckChatButton.primaryAction = action(image: DesignSystemImages.Glyphs.Size24.aiChat, { [weak self] in
            self?.delegate.tabSwitcherDidRequestAIChat(tabSwitcher: self!)
        })
    }

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
        shareTabs(selectedTabs.compactMap { tabsModel.safeGetTabAt($0.row) })
    }

}

// MARK: Long press menu actions
extension TabSwitcherViewController {

    func longPressMenuCloseSelectedTabs() {
        closeSelectedTabs()
    }

    func longPressMenuShareSelectedLinks() {
        shareTabs(selectedTabs.map { tabsModel.safeGetTabAt($0.row) }.compactMap { $0 })
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

// MARK: UIAction factories
extension TabSwitcherViewController {
    
    func action(_ title: String, _ image: UIImage? = nil, _ handler: @escaping () -> Void) -> UIAction {
        return UIAction(title: title, image: image) { _ in
            handler()
        }
    }

    func action(image: UIImage, _ handler: @escaping () -> Void) -> UIAction {
        return UIAction(title: "", image: image) { _ in
            handler()
        }
    }
    
    func destructive(_ title: String, _ image: UIImage, _ handler: @escaping () -> Void) -> UIAction {
        return UIAction(title: title, image: image, attributes: .destructive) { _ in
            handler()
        }
    }

}
