//
//  TabSwitcherViewController.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Common
import Core
import DDGSync
import WebKit
import Bookmarks
import Persistence
import os.log
import SwiftUI
import BrowserServicesKit
import AIChat
import Combine

class TabSwitcherViewController: UIViewController {

    struct Constants {
        static let preferredMinNumberOfRows: CGFloat = 2.7

        static let cellMinHeight: CGFloat = 140.0
        static let cellMaxHeight: CGFloat = 209.0
    }

    struct BookmarkAllResult {
        let newCount: Int
        let existingCount: Int
        let urls: [URL]
    }

    enum InterfaceMode {

        var isLarge: Bool {
            return [.largeSize, .editingLargeSize].contains(self)
        }

        var isNormal: Bool {
            return !isLarge
        }

        case regularSize
        case largeSize
        case editingRegularSize
        case editingLargeSize

    }

    enum TabsStyle: String {

        case list = "tabsToggleList"
        case grid = "tabsToggleGrid"

        var accessibilityLabel: String {
            switch self {
            case .list: "Switch to grid view"
            case .grid: "Switch to list view"
            }
        }

        var image: UIImage {
            switch self {
            case .list:
                return UIImage(resource: .tabsToggleList)
            case .grid:
                return UIImage(resource: .tabsToggleGrid)
            }
        }

    }

    @IBOutlet weak var topBarView: UINavigationBar!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var toolbar: UIToolbar!

    weak var delegate: TabSwitcherDelegate!
    weak var previewsSource: TabPreviewsSource!
    
    var selectedTabs: [IndexPath] {
        collectionView.indexPathsForSelectedItems ?? []
    }

    private(set) var bookmarksDatabase: CoreDataDatabase
    let syncService: DDGSyncing

    override var canBecomeFirstResponder: Bool { return true }

    var currentSelection: Int?

    var tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings()
    var isProcessingUpdates = false
    private var canUpdateCollection = true

    let favicons: Favicons

    var tabsStyle: TabsStyle = .list
    var interfaceMode: InterfaceMode = .regularSize
    var canShowSelectionMenu = false

    let featureFlagger: FeatureFlagger
    let tabManager: TabManager
    let aiChatSettings: AIChatSettingsProvider
    var tabsModel: TabsModel {
        tabManager.model
    }

    let barsHandler = TabSwitcherBarsStateHandler()
    private var tabObserverCancellable: AnyCancellable?

    required init?(coder: NSCoder,
                   bookmarksDatabase: CoreDataDatabase,
                   syncService: DDGSyncing,
                   featureFlagger: FeatureFlagger,
                   favicons: Favicons = Favicons.shared,
                   tabManager: TabManager,
                   aiChatSettings: AIChatSettingsProvider) {
        self.bookmarksDatabase = bookmarksDatabase
        self.syncService = syncService
        self.featureFlagger = featureFlagger
        self.favicons = favicons
        self.tabManager = tabManager
        self.aiChatSettings = aiChatSettings
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    fileprivate func createTopBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        topBarView.standardAppearance = appearance
        topBarView.scrollEdgeAppearance = appearance
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createTopBar()

        refreshTitle()
        setupBackgroundView()
        currentSelection = tabsModel.currentIndex
        decorate()
        becomeFirstResponder()
        updateUIForSelectionMode()

        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsMultipleSelectionDuringEditing = true

        if !tabSwitcherSettings.hasSeenNewLayout {
            Pixel.fire(pixel: .tabSwitcherNewLayoutSeen)
            tabSwitcherSettings.hasSeenNewLayout = true
        }

        tabObserverCancellable = tabsModel.$tabs.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.collectionView.reloadData()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateUIForSelectionMode()
    }

    private func setupBackgroundView() {
        let view = UIView(frame: collectionView.frame)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(gesture:))))
        collectionView.backgroundView = view
    }

    func refreshDisplayModeButton() {
        tabsStyle = tabSwitcherSettings.isGridViewEnabled ? .grid : .list
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self

        updateUIForSelectionMode()
    }

    func prepareForPresentation() {
        view.layoutIfNeeded()
        self.scrollToInitialTab()
    }
    
    @objc func handleTap(gesture: UITapGestureRecognizer) {
        guard gesture.tappedInWhitespaceAtEndOfCollectionView(collectionView) else { return }
        
        if isEditing {
            transitionFromMultiSelect()
        } else {
            dismiss()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func scrollToInitialTab() {
        let index = tabsModel.currentIndex
        guard index < collectionView.numberOfItems(inSection: 0) else { return }
        let indexPath = IndexPath(row: index, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
    }

    func refreshTitle() {
        topBarView.topItem?.title = UserText.numberOfTabs(tabsModel.count)
        if !selectedTabs.isEmpty {
            topBarView.topItem?.title = UserText.numberOfSelectedTabs(withCount: selectedTabs.count)
        }
    }

    func displayBookmarkAllStatusMessage(with results: BookmarkAllResult, openTabsCount: Int) {
        if results.newCount == 1 {
            ActionMessageView.present(message: UserText.tabsBookmarked(withCount: results.newCount), actionTitle: UserText.actionGenericEdit, onAction: {
                self.editBookmark(results.urls.first)
            })
        } else if results.newCount > 0 {
            ActionMessageView.present(message: UserText.tabsBookmarked(withCount: results.newCount), actionTitle: UserText.actionGenericUndo, onAction: {
                self.removeBookmarks(results.urls)
            })
        } else { // Zero
            ActionMessageView.present(message: UserText.tabsBookmarked(withCount: results.newCount))
        }
    }
    
    func removeBookmarks(_ url: [URL]) {
        let model = BookmarkListViewModel(bookmarksDatabase: self.bookmarksDatabase, parentID: nil, favoritesDisplayMode: .default, errorEvents: nil)
        url.forEach {
            guard let entity = model.bookmark(for: $0) else { return }
            model.softDeleteBookmark(entity)
        }
    }
    
    func editBookmark(_ url: URL?) {
        guard let url else { return }
        delegate?.tabSwitcher(self, editBookmarkForUrl: url)
    }

    func bookmarkTabs(withIndexPaths indexPaths: [IndexPath], viewModel: MenuBookmarksInteracting) -> BookmarkAllResult {
        let tabs = self.tabsModel.tabs
        var newCount = 0
        var urls = [URL]()

        indexPaths.compactMap {
            tabsModel.safeGetTabAt($0.row)
        }.forEach { tab in
            guard let link = tab.link else { return }
            if viewModel.bookmark(for: link.url) == nil {
                viewModel.createBookmark(title: link.displayTitle, url: link.url)
                favicons.loadFavicon(forDomain: link.url.host, intoCache: .fireproof, fromCache: .tabs)
                newCount += 1
                urls.append(link.url)
            }
        }
        return .init(newCount: newCount, existingCount: tabs.count - newCount, urls: urls)
    }

    @IBAction func onAddPressed(_ sender: UIBarButtonItem) {
        addNewTab()
    }

    @IBAction func onDonePressed(_ sender: UIBarButtonItem) {
        if isEditing {
            transitionFromMultiSelect()
        } else {
            dismiss()
        }
    }
    
    func markCurrentAsViewedAndDismiss() {
        // Will be dismissed, so no need to process incoming updates
        canUpdateCollection = false

        if let current = currentSelection {
            let tab = tabsModel.get(tabAt: current)
            tab.viewed = true
            tabManager.save()
            delegate?.tabSwitcher(self, didSelectTab: tab)
        }
        dismiss()
    }

    @IBAction func onFirePressed(sender: AnyObject) {
        burn(sender: sender)
    }

    func forgetAll() {
        self.delegate.tabSwitcherDidRequestForgetAll(tabSwitcher: self)
    }

    func dismiss() {
        dismiss(animated: true, completion: nil)
    }

    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        canUpdateCollection = false
        tabsModel.tabs.forEach { $0.removeObserver(self) }
        super.dismiss(animated: animated, completion: completion)
    }
}

extension TabSwitcherViewController: TabViewCellDelegate {

    func deleteTabsAtIndexPaths(_ indexPaths: [IndexPath]) {
        let shouldDismiss = tabsModel.count == indexPaths.count

        collectionView.performBatchUpdates {
            isProcessingUpdates = true
            tabManager.bulkRemoveTabs(indexPaths)
            collectionView.deleteItems(at: indexPaths)
        } completion: { _ in
            self.currentSelection = self.tabsModel.currentIndex
            self.isProcessingUpdates = false
            if self.tabsModel.tabs.isEmpty {
                self.tabsModel.add(tab: Tab())
            }
            self.delegate?.tabSwitcherDidBulkCloseTabs(tabSwitcher: self)
            self.refreshTitle()
            self.updateUIForSelectionMode()
            if shouldDismiss {
                self.dismiss()
            }
        }
    }
    
    func deleteTab(tab: Tab) {
        guard let index = tabsModel.indexOf(tab: tab) else { return }
        deleteTabsAtIndexPaths([
            IndexPath(row: index, section: 0)
        ])
    }

    func isCurrent(tab: Tab) -> Bool {
        return currentSelection == tabsModel.indexOf(tab: tab)
    }

    private func removeFavicon(forTab tab: Tab) {
        DispatchQueue.global(qos: .background).async {
            if let currentHost = tab.link?.url.host,
               !self.tabsModel.tabExists(withHost: currentHost) {
                Favicons.shared.removeTabFavicon(forDomain: currentHost)
            }
        }
    }

}

extension TabSwitcherViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabsModel.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cellIdentifier = tabSwitcherSettings.isGridViewEnabled ? TabViewCell.gridReuseIdentifier : TabViewCell.listReuseIdentifier
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as? TabViewCell else {
            fatalError("Failed to dequeue cell \(cellIdentifier) as TabViewCell")
        }
        cell.delegate = self
        cell.isDeleting = false
        
        if indexPath.row < tabsModel.count {
            let tab = tabsModel.get(tabAt: indexPath.row)
            tab.addObserver(self)
            cell.update(withTab: tab,
                        isSelectionModeEnabled: self.isEditing,
                        preview: previewsSource.preview(for: tab))
        }
        
        return cell
    }

}

extension TabSwitcherViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isEditing {
            Pixel.fire(pixel: .tabSwitcherTabSelected)
            (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
            updateUIForSelectionMode()
            refreshTitle()
        } else {
            currentSelection = indexPath.row
            Pixel.fire(pixel: .tabSwitcherSwitchTabs)
            markCurrentAsViewedAndDismiss()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
        updateUIForSelectionMode()
        refreshTitle()
        Pixel.fire(pixel: .tabSwitcherTabDeselected)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return !isEditing
    }

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        // This can happen if you long press in the whitespace
        guard !indexPaths.isEmpty else { return nil }
        
        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            Pixel.fire(pixel: .tabSwitcherLongPress)
            DailyPixel.fire(pixel: .tabSwitcherLongPressDaily)
            return self.createLongPressMenuForTabs(atIndexPaths: indexPaths)
        }

        return configuration
    }

}

extension TabSwitcherViewController: UICollectionViewDelegateFlowLayout {

    private func calculateColumnWidth(minimumColumnWidth: CGFloat, maxColumns: Int) -> CGFloat {
        // Spacing is supposed to be equal between cells and on left/right side of the collection view
        let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        let spacing = layout?.sectionInset.left ?? 0.0
        
        let contentWidth = collectionView.bounds.width - spacing
        let numberOfColumns = min(maxColumns, Int(contentWidth / minimumColumnWidth))
        return contentWidth / CGFloat(numberOfColumns) - spacing
    }
    
    private func calculateRowHeight(columnWidth: CGFloat) -> CGFloat {
        
        // Calculate height based on the view size
        let contentAspectRatio = collectionView.bounds.width / collectionView.bounds.height
        let heightToFit = (columnWidth / contentAspectRatio) + TabViewCell.Constants.cellHeaderHeight
        
        // Try to display at least `preferredMinNumberOfRows`
        let preferredMaxHeight = collectionView.bounds.height / Constants.preferredMinNumberOfRows
        let preferredHeight = min(preferredMaxHeight, heightToFit)
        
        return min(Constants.cellMaxHeight,
                   max(Constants.cellMinHeight, preferredHeight))
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        if tabSwitcherSettings.isGridViewEnabled {
            let columnWidth = calculateColumnWidth(minimumColumnWidth: 150, maxColumns: 4)
            let rowHeight = calculateRowHeight(columnWidth: columnWidth)
            return CGSize(width: floor(columnWidth),
                          height: floor(rowHeight))
        } else {
            let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let spacing = layout?.sectionInset.left ?? 0.0
            
            let width = min(664, collectionView.bounds.size.width - 2 * spacing)
            
            return CGSize(width: width, height: 70)
        }
    }
    
}

extension TabSwitcherViewController: TabObserver {
    
    func didChange(tab: Tab) {
        // Reloading when updates are processed will result in a crash
        guard !isProcessingUpdates, canUpdateCollection else {
            return
        }
        
        collectionView.performBatchUpdates({}, completion: { [weak self] completed in
            guard completed, let self = self else { return }
            if let index = self.tabsModel.indexOf(tab: tab), index < self.collectionView.numberOfItems(inSection: 0) {
                UIView.performWithoutAnimation {
                    self.collectionView.reconfigureItems(at: [IndexPath(row: index, section: 0)])
                }
            }
        })
    }
}

extension TabSwitcherViewController {
    
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = theme.backgroundColor
        
        refreshDisplayModeButton()
        
        topBarView.tintColor = theme.barTintColor

        toolbar.barTintColor = theme.barBackgroundColor
        toolbar.tintColor = theme.barTintColor
                
        collectionView.reloadData()
    }

}

// These don't appear to do anything but at least one needs to exist for dragging to even work
extension TabSwitcherViewController: UICollectionViewDragDelegate {

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        return isEditing ? [] : [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        return [UIDragItem(itemProvider: NSItemProvider())]
    }

}

extension TabSwitcherViewController: UICollectionViewDropDelegate {

    func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        return .init(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {

        guard let destination = coordinator.destinationIndexPath,
              let item = coordinator.items.first,
              let source = item.sourceIndexPath
        else {
            // This can happen if the menu is shown and the user then drags to an invalid location
            return
        }

        collectionView.performBatchUpdates {
            tabsModel.moveTab(from: source.row, to: destination.row)
            currentSelection = tabsModel.currentIndex
            collectionView.deleteItems(at: [source])
            collectionView.insertItems(at: [destination])
        } completion: { _ in
            if self.isEditing {
                collectionView.reloadData() // Clears the selection
                collectionView.selectItem(at: destination, animated: true, scrollPosition: [])
                self.refreshBarButtons()
            } else {
                collectionView.reloadItems(at: [IndexPath(row: self.currentSelection ?? 0, section: 0)])
            }
            self.delegate.tabSwitcherDidReorderTabs(tabSwitcher: self)
            coordinator.drop(item.dragItem, toItemAt: destination)
        }

    }

}

extension UITapGestureRecognizer {
    
    func tappedInWhitespaceAtEndOfCollectionView(_ collectionView: UICollectionView) -> Bool {
        guard collectionView.indexPathForItem(at: self.location(in: collectionView)) == nil else { return false }
        let location = self.location(in: collectionView)
           
        // Now check if the tap is in the whitespace area at the end
        let lastSection = collectionView.numberOfSections - 1
        let lastItemIndex = collectionView.numberOfItems(inSection: lastSection) - 1
        
        // Get the frame of the last item
        // If there are no items in the last section, the entire area is whitespace
       guard lastItemIndex >= 0 else { return true }
        
        let lastItemIndexPath = IndexPath(item: lastItemIndex, section: lastSection)
        let lastItemFrame = collectionView.layoutAttributesForItem(at: lastItemIndexPath)?.frame ?? .zero
        
        // Check if the tap is below the last item.
        // Add 10px buffer to ensure it's whitespace.
        if location.y > lastItemFrame.maxY + 15 // below the bottom of the last item is definitely the end
            || (location.x > lastItemFrame.maxX + 15 && location.y > lastItemFrame.minY) // to the right of the last item is the end as long as it's also at least below the start of the frame
        {
            // The tap is in the whitespace area at the end
           return true
        }

        return false
    }
}
