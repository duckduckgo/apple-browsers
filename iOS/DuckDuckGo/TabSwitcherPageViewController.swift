//
//  TabSwitcherPageViewController.swift
//  DuckDuckGo
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


import UIKit
import Common
import FoundationExtensions
import Core
import DDGSync
import WebKit
import Bookmarks
import Persistence
import os.log
import SwiftUI
import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import BrowserServicesKit
import PrivacyConfig
import AIChat
import UIComponents

protocol TabSwitcherPageDelegate: AnyObject {
    func page(_ page: TabSwitcherPageViewController, didSelectTabAt index: Int)
    func page(_ page: TabSwitcherPageViewController, didDeselectTab: Void)
    func page(_ page: TabSwitcherPageViewController, willDeleteTabs tabs: [Tab], allDeleted: Bool)
    func pageDidDeleteTabs(_ page: TabSwitcherPageViewController, allDeleted: Bool)
    func page(_ page: TabSwitcherPageViewController, didReorderTabs: Void)
    func page(_ page: TabSwitcherPageViewController, contextMenuForTabsAt indexPaths: [IndexPath]) -> UIMenu?
    func pageDidRequestDismiss(_ page: TabSwitcherPageViewController)
    func pageCellDidBeginSwipe(_ page: TabSwitcherPageViewController)
    func pageCellDidEndSwipe(_ page: TabSwitcherPageViewController)
    func pageCellDidBeginDrag(_ page: TabSwitcherPageViewController)
    func pageCellDidEndDrag(_ page: TabSwitcherPageViewController)

    var isEditing: Bool { get }
    var isProcessingUpdates: Bool { get set }
    var canDismissOnEmpty: Bool { get }
}

class TabSwitcherPageViewController: UIViewController {
    
    private(set) var collectionView: UICollectionView!
    let tabsModel: TabsModelManaging
    weak var pageDelegate: TabSwitcherPageDelegate?
    var onNewFireTab: (() -> Void)?
    var currentSelection: Int?


    private let browsingMode: BrowsingMode
    private weak var previewsSource: TabPreviewsSource?
    private let tabSwitcherSettings: TabSwitcherSettings
    private var isFireModeEnabled: Bool
    private let isFloatingUIEnabled: Bool
    private var tabObserverCancellable: AnyCancellable?
    private var trackerCountViewModel: TabSwitcherTrackerCountViewModel?
    private var trackerCountCancellable: AnyCancellable?
    private var lastAppliedTrackerCountState: TabSwitcherTrackerCountViewModel.State?
    private var trackerInfoModel: InfoPanelView.Model?
    private var fireModeEmptyStateHostingController: UIHostingController<FireModeEmptyStateView>?
    private let duckAIGridContentProvider: DuckAIGridContentProviding?
    private let duckAIVoiceSessionTracker: DuckAIVoiceSessionTracking?
    private var voiceSessionChangesCancellable: AnyCancellable?

    var canUpdateCollection = true

    var selectedIndexPaths: [IndexPath] {
        collectionView.indexPathsForSelectedItems ?? []
    }

    init(browsingMode: BrowsingMode,
         tabsModel: TabsModelManaging,
         previewsSource: TabPreviewsSource,
         tabSwitcherSettings: TabSwitcherSettings,
         trackerCountViewModel: TabSwitcherTrackerCountViewModel?,
         isFireModeEnabled: Bool,
         isFloatingUIEnabled: Bool = false,
         duckAIGridContentProvider: DuckAIGridContentProviding?,
         duckAIVoiceSessionTracker: DuckAIVoiceSessionTracking?) {
        self.browsingMode = browsingMode
        self.tabsModel = tabsModel
        self.previewsSource = previewsSource
        self.tabSwitcherSettings = tabSwitcherSettings
        self.trackerCountViewModel = trackerCountViewModel
        self.isFireModeEnabled = isFireModeEnabled
        self.isFloatingUIEnabled = isFloatingUIEnabled
        self.currentSelection = tabsModel.currentIndex
        self.duckAIGridContentProvider = duckAIGridContentProvider
        self.duckAIVoiceSessionTracker = duckAIVoiceSessionTracker
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 14
        layout.minimumInteritemSpacing = 14
        layout.sectionInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = true
        collectionView.isMultipleTouchEnabled = true
        if #available(iOS 17.0, *) {
            collectionView.allowsKeyboardScrolling = false
        }
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsMultipleSelectionDuringEditing = true

        collectionView.register(TabViewGridCell.self, forCellWithReuseIdentifier: TabViewGridCell.reuseIdentifier)
        collectionView.register(TabViewListCell.self, forCellWithReuseIdentifier: TabViewListCell.reuseIdentifier)
        collectionView.register(
            TabSwitcherTrackerInfoHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: TabSwitcherTrackerInfoHeaderView.reuseIdentifier
        )

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let backgroundView = UIView(frame: collectionView.frame)
        backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(gesture:))))
        collectionView.backgroundView = backgroundView
        
        subscribeToTabChanges()
        subscribeToVoiceSessionChanges()
        bindTrackerCount()
        trackerCountViewModel?.refresh()
        setupFireModeEmptyState()
    }

    private var lastLayoutSize: CGSize = .zero

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let currentSize = view.bounds.size
        guard currentSize != lastLayoutSize, currentSize != .zero else { return }
        lastLayoutSize = currentSize
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        trackerCountViewModel?.refresh()
    }
    
    private func subscribeToTabChanges() {
        tabObserverCancellable = tabsModel.tabsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.canUpdateCollection else { return }
                self.reloadData()
            }
    }

    private func setupFireModeEmptyState() {
        guard browsingMode == .fire, isFireModeEnabled else { return }
        let emptyStateView = FireModeEmptyStateView(type: .tabSwitcher(onNewFireTab: { [weak self] in
            Pixel.fire(pixel: .fireModeEmptyStateNewTab)
            self?.onNewFireTab?()
        }))
        let hostingController = UIHostingController(rootView: emptyStateView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        let topConstraint = isFloatingUIEnabled
            ? hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                                          constant: FireModeEmptyStateMetrics.floatingNavigationBarClearance)
            : hostingController.view.topAnchor.constraint(equalTo: view.topAnchor)

        NSLayoutConstraint.activate([
            topConstraint,
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        fireModeEmptyStateHostingController = hostingController
    }

    private enum FireModeEmptyStateMetrics {
        static let floatingNavigationBarClearance: CGFloat = 60
    }

    func updateEmptyStateVisibility() {
        guard browsingMode == .fire else { return }
        let shouldShowEmptyState = tabsModel.tabs.isEmpty
        fireModeEmptyStateHostingController?.view.isHidden = !shouldShowEmptyState
        collectionView.isHidden = shouldShowEmptyState
    }

    // MARK: - Tracker Count
    
    private func bindTrackerCount() {
        trackerCountCancellable = trackerCountViewModel?.$state
            .sink { [weak self] state in
                self?.applyTrackerCountState(state)
            }
    }

    private func applyTrackerCountState(_ state: TabSwitcherTrackerCountViewModel.State) {
        guard state != lastAppliedTrackerCountState else { return }
        lastAppliedTrackerCountState = state

        guard state.isVisible else {
            trackerInfoModel = nil
            updateTrackerInfoHeaderIfVisible()
            collectionView.collectionViewLayout.invalidateLayout()
            return
        }

        trackerInfoModel = .trackerInfoPanel(
            state: state,
            onTap: { },
            onDismiss: { [weak self] in
                self?.presentHideTrackerCountAlert()
            }
        )
        updateTrackerInfoHeaderIfVisible()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func updateTrackerInfoHeaderIfVisible() {
        let indexPath = IndexPath(item: 0, section: 0)
        guard let header = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: indexPath
        ) as? TabSwitcherTrackerInfoHeaderView else {
            return
        }
        header.configure(in: self, model: trackerInfoModel)
    }

    private func presentHideTrackerCountAlert() {
        let alert = UIAlertController(title: UserText.tabSwitcherTrackerCountHideTitle,
                                      message: UserText.tabSwitcherTrackerCountHideMessage,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: UserText.tabSwitcherTrackerCountKeepAction, style: .cancel))
        alert.addAction(UIAlertAction(title: UserText.tabSwitcherTrackerCountHideAction, style: .default) { [weak self] _ in
            Pixel.fire(pixel: .tabSwitcherTrackerCountHidden)
            self?.trackerCountViewModel?.hide()
        })
        present(alert, animated: true)
    }

    // MARK: - Public API
    
    var selectedTab: Tab? {
        return tabsModel.get(tabAt: currentSelection)
    }

    func reloadData() {
        collectionView.reloadData()
        updateEmptyStateVisibility()
    }

    func refreshCurrentTabIndicators() {
        guard currentSelection != nil else { return }
        for cell in collectionView.visibleCells {
            guard let tabCell = cell as? TabViewCell,
                  let tab = tabCell.tab else { continue }
            tabCell.isCurrent = isCurrent(tab: tab)
            tabCell.updateCurrentTabBorder()
        }
    }
    
    func scrollToInitialTab() {
        guard let index = tabsModel.currentIndex,
              index < collectionView.numberOfItems(inSection: 0) else { return }
        collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .bottom, animated: false)
    }

    func enterEditingMode() {
        collectionView.reloadData()
    }

    func exitEditingMode(reloadData: Bool) {
        if reloadData {
            collectionView.reloadData()
        }
    }

    func selectAll() {
        for row in 0..<tabsModel.count {
            collectionView.selectItem(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: [])
        }
    }

    func deselectAll() {
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: false)
        }
    }

    func deleteTabsAtIndexPaths(_ indexPaths: [IndexPath]) {
        guard let pageDelegate else { return }
        let allTabsDeleted = tabsModel.count == indexPaths.count
        let tabsToClose = indexPaths.compactMap { tabsModel.get(tabAt: $0.row) }

        collectionView.performBatchUpdates {
            pageDelegate.isProcessingUpdates = true
            pageDelegate.page(self, willDeleteTabs: tabsToClose, allDeleted: allTabsDeleted)
            collectionView.deleteItems(at: indexPaths)
            currentSelection = tabsModel.currentIndex
            refreshCurrentTabIndicators()
        } completion: { _ in
            pageDelegate.isProcessingUpdates = false
            pageDelegate.pageDidDeleteTabs(self, allDeleted: allTabsDeleted)
        }
    }

    // MARK: - Private

    @objc private func handleBackgroundTap(gesture: UITapGestureRecognizer) {
        guard gesture.tappedInWhitespaceAtEndOfCollectionView(collectionView) else { return }
        pageDelegate?.pageDidRequestDismiss(self)
    }

    /// Resolves the rich-card grid item for `tab`, or `nil` for non-AI tabs and
    /// when no provider is wired in (release builds without an explicit injection).
    /// `nil` keeps the cell on the existing screenshot path.
    private func duckAIGridItem(for tab: Tab) -> DuckAIGridItem? {
        guard tab.isAITab else { return nil }
        let liveVoiceActive = duckAIVoiceSessionTracker?.isVoiceSessionActive(for: tab) ?? false
        return duckAIGridContentProvider?.gridItem(for: tab, liveVoiceActive: liveVoiceActive)
    }

    /// Applies the current tab state (preview/rich card) to `cell`.
    private func configure(_ cell: TabViewCell, with tab: Tab) {
        cell.update(withTab: tab,
                    isSelectionModeEnabled: pageDelegate?.isEditing ?? false,
                    preview: previewsSource?.preview(for: tab),
                    isFireModeEnabled: isFireModeEnabled,
                    duckAIGridItem: duckAIGridItem(for: tab),
                    thumbnailLoader: duckAIGridContentProvider)
    }

    /// Refreshes visible Duck.ai cells when a voice session starts/ends (end-timing lives in `DuckAIVoiceSessionTracker`).
    private func subscribeToVoiceSessionChanges() {
        voiceSessionChangesCancellable = duckAIVoiceSessionTracker?.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshVisibleAITabCells() }
    }

    private func refreshVisibleAITabCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard indexPath.row < tabsModel.count,
                  let tab = tabsModel.get(tabAt: indexPath.row),
                  tab.isAITab,
                  let cell = collectionView.cellForItem(at: indexPath) as? TabViewCell else { continue }
            configure(cell, with: tab)
        }
    }
}

// MARK: - UICollectionViewDataSource

extension TabSwitcherPageViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabsModel.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cellIdentifier = tabSwitcherSettings.isGridViewEnabled ? TabViewGridCell.reuseIdentifier : TabViewListCell.reuseIdentifier
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as? TabViewCell else {
            fatalError("Failed to dequeue cell \(cellIdentifier) as TabViewCell")
        }
        cell.delegate = self
        cell.isDeleting = false

        if indexPath.row < tabsModel.count,
           let tab = tabsModel.get(tabAt: indexPath.row) {
            tab.removeObserver(self)
            tab.addObserver(self)
            configure(cell, with: tab)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }

        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: TabSwitcherTrackerInfoHeaderView.reuseIdentifier,
            for: indexPath
        ) as? TabSwitcherTrackerInfoHeaderView else {
            return UICollectionReusableView()
        }

        header.configure(in: self, model: trackerInfoModel)
        return header
    }
}

// MARK: - UICollectionViewDelegate

extension TabSwitcherPageViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if pageDelegate?.isEditing == true {
            Pixel.fire(pixel: .tabSwitcherTabSelected)
            (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
            pageDelegate?.page(self, didSelectTabAt: indexPath.row)
        } else {
            currentSelection = indexPath.row
            Pixel.fire(pixel: .tabSwitcherSwitchTabs, withAdditionalParameters: [
                PixelParameters.browsingMode: browsingMode.pixelParamValue
            ])
            if let tab = tabsModel.get(tabAt: indexPath.row) {
                if tab.isAITab {
                    DailyPixel.fireDailyAndCount(pixel: .tabManagerSwitchToAITab)
                } else {
                    DailyPixel.fireDailyAndCount(pixel: .tabManagerSwitchToWebTab)
                }
            }
            pageDelegate?.pageDidRequestDismiss(self)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
        pageDelegate?.page(self, didDeselectTab: ())
        Pixel.fire(pixel: .tabSwitcherTabDeselected)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return !(pageDelegate?.isEditing ?? false)
    }

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard !indexPaths.isEmpty else { return nil }

        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let modeParam = [PixelParameters.browsingMode: self.browsingMode.pixelParamValue]
            Pixel.fire(pixel: .tabSwitcherLongPress, withAdditionalParameters: modeParam)
            DailyPixel.fire(pixel: .tabSwitcherLongPressDaily, withAdditionalParameters: modeParam)
            return self.pageDelegate?.page(self, contextMenuForTabsAt: indexPaths)
        }
        return configuration
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension TabSwitcherPageViewController: UICollectionViewDelegateFlowLayout {

    private func calculateColumnWidth(minimumColumnWidth: CGFloat, maxColumns: Int) -> CGFloat {
        let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        let spacing = layout?.sectionInset.left ?? 0.0
        let contentWidth = collectionView.bounds.width - spacing
        let numberOfColumns = min(maxColumns, Int(contentWidth / minimumColumnWidth))
        return contentWidth / CGFloat(numberOfColumns) - spacing
    }

    private func calculateRowHeight(columnWidth: CGFloat) -> CGFloat {
        let contentAspectRatio = collectionView.bounds.width / collectionView.bounds.height
        let heightToFit = (columnWidth / contentAspectRatio) + TabViewCell.Constants.cellHeaderHeight
        let preferredMaxHeight = collectionView.bounds.height / TabSwitcherViewController.Constants.preferredMinNumberOfRows
        let preferredHeight = min(preferredMaxHeight, heightToFit)
        return min(TabSwitcherViewController.Constants.cellMaxHeight,
                   max(TabSwitcherViewController.Constants.cellMinHeight, preferredHeight))
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if tabSwitcherSettings.isGridViewEnabled {
            let columnWidth = calculateColumnWidth(minimumColumnWidth: 150, maxColumns: 4)
            let rowHeight = calculateRowHeight(columnWidth: columnWidth)
            return CGSize(width: floor(columnWidth), height: floor(rowHeight))
        } else {
            let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let spacing = layout?.sectionInset.left ?? 0.0
            let width = min(664, collectionView.bounds.size.width - 2 * spacing)
            return CGSize(width: width, height: 70)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard trackerInfoModel != nil else { return .zero }
        return CGSize(width: collectionView.bounds.width, height: TabSwitcherTrackerInfoHeaderView.estimatedHeight)
    }
}

// MARK: - TabViewCellDelegate

extension TabSwitcherPageViewController: TabViewCellDelegate {

    func deleteTab(tab: Tab) {
        guard let index = tabsModel.indexOf(tab: tab) else { return }
        deleteTabsAtIndexPaths([IndexPath(row: index, section: 0)])
    }

    func isCurrent(tab: Tab) -> Bool {
        return currentSelection == tabsModel.indexOf(tab: tab)
    }

    func tabViewCellDidBeginSwipe(_ cell: TabViewCell) {
        pageDelegate?.pageCellDidBeginSwipe(self)
    }

    func tabViewCellDidEndSwipe(_ cell: TabViewCell) {
        pageDelegate?.pageCellDidEndSwipe(self)
    }
}

// MARK: - TabObserver

extension TabSwitcherPageViewController: TabObserver {

    func didChange(tab: Tab) {
        guard let index = tabsModel.indexOf(tab: tab),
              let cell = collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? TabViewCell else {
            return
        }
        guard cell.tab?.uid == tab.uid else {
            DailyPixel.fireDaily(.debugTabSwitcherDidChangeInvalidState)
            return
        }
        configure(cell, with: tab)
    }
}

// MARK: - UICollectionViewDragDelegate

extension TabSwitcherPageViewController: UICollectionViewDragDelegate {

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        return (pageDelegate?.isEditing ?? false) ? [] : [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        return [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: any UIDragSession) {
        pageDelegate?.pageCellDidBeginDrag(self)
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
        pageDelegate?.pageCellDidEndDrag(self)
    }
}

// MARK: - UICollectionViewDropDelegate

extension TabSwitcherPageViewController: UICollectionViewDropDelegate {

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
        else { return }

        collectionView.performBatchUpdates {
            guard let tab = tabsModel.get(tabAt: source.row) else { return }
            tabsModel.move(tab: tab, to: destination.row)
            currentSelection = tabsModel.currentIndex
            collectionView.deleteItems(at: [source])
            collectionView.insertItems(at: [destination])
        } completion: { [weak self] _ in
            guard let self else { return }
            if self.pageDelegate?.isEditing == true {
                self.reloadData()
                collectionView.selectItem(at: destination, animated: true, scrollPosition: [])
            } else {
                collectionView.reloadItems(at: [IndexPath(row: self.currentSelection ?? 0, section: 0)])
            }
            self.pageDelegate?.page(self, didReorderTabs: ())
            coordinator.drop(item.dragItem, toItemAt: destination)
        }
    }
}

// MARK: - UITapGestureRecognizer Helpers

private extension UITapGestureRecognizer {
    
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
            || (location.x > lastItemFrame.maxX + 15 && location.y > lastItemFrame.minY) { // to the right of the last item is the end as long as it's also at least below the start of the frame
            // The tap is in the whitespace area at the end
        return true
    }
    
        return false
    }
}
