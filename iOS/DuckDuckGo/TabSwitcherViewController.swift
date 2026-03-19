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
import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import BrowserServicesKit
import PrivacyConfig
import AIChat
import UIComponents

class TabSwitcherViewController: UIViewController {

    struct Constants {
        static let preferredMinNumberOfRows: CGFloat = 2.7

        static let cellMinHeight: CGFloat = 140.0
        static let cellMaxHeight: CGFloat = 209.0
        static let modePickerWidth: CGFloat = 114
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
                return DesignSystemImages.Glyphs.Size24.viewList
            case .grid:
                return DesignSystemImages.Glyphs.Size24.viewGrid
            }
        }

    }

    lazy var borderView = StyledTopBottomBorderView()

    @IBOutlet weak var titleBarView: UINavigationBar!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var toolbar: UIToolbar!

    weak var delegate: TabSwitcherDelegate!
    weak var previewsSource: TabPreviewsSource!

    var selectedTabs: [IndexPath] {
        collectionView.indexPathsForSelectedItems ?? []
    }

    private(set) var bookmarksDatabase: CoreDataDatabase
    let syncService: DDGSyncing

    var currentSelection: Int?

    let tabSwitcherSettings: TabSwitcherSettings
    var isProcessingUpdates = false
    private var canUpdateCollection = true

    let favicons: Favicons

    var tabsStyle: TabsStyle = .list
    var interfaceMode: InterfaceMode = .regularSize
    var canShowSelectionMenu = false

    let featureFlagger: FeatureFlagger
    let tabManager: TabManager
    let historyManager: HistoryManaging
    let fireproofing: Fireproofing
    let aiChatSettings: AIChatSettingsProvider
    let privacyStats: PrivacyStatsProviding
    let keyValueStore: ThrowingKeyValueStoring
    let daxDialogsManager: DaxDialogsManaging
    var tabsModel: TabsModelManaging {
        tabManager.tabsModel(for: selectedBrowsingMode)
    }

    var canDismissOnEmpty: Bool {
        !tabsModel.allowsEmpty
    }
    
    var barsHandler: TabSwitcherBarsStateHandling = DefaultTabSwitcherBarsStateHandler()

    private var tabObserverCancellable: AnyCancellable?
    private let appSettings: AppSettings
    private var trackerCountCancellable: AnyCancellable?
    private var trackerCountViewModel: TabSwitcherTrackerCountViewModel?
    private var lastAppliedTrackerCountState: TabSwitcherTrackerCountViewModel.State?
    private var _trackerInfoModel: InfoPanelView.Model?
    private var activeTrackerInfoModel: InfoPanelView.Model? {
        guard selectedBrowsingMode == .normal else { return nil }
        return _trackerInfoModel
    }

    private let initialTrackerCountState: TabSwitcherTrackerCountViewModel.State
    
    private(set) var aichatFullModeFeature: AIChatFullModeFeatureProviding
    private(set) var aichatIPadTabFeature: AIChatIPadTabFeatureProviding

    private let productSurfaceTelemetry: ProductSurfaceTelemetry

    private var pickerViewModel: ImageSegmentedPickerViewModel
    private let pickerItems: [ImageSegmentedPickerItem]
    private let tabCountModel: TabCountModel
    private(set) var selectedBrowsingMode: BrowsingMode
    private(set) var segmentedPickerHostingController: UIHostingController<TabSwitcherPickerWrapper>?
    private var pickerSelectionCancellable: AnyCancellable?
    private var fireModeEmptyStateHostingController: UIHostingController<FireModeEmptyStateView>?
    private var fireModeCapability: FireModeCapable {
        FireModeCapability.create(using: featureFlagger)
    }

    required init?(coder: NSCoder,
                   bookmarksDatabase: CoreDataDatabase,
                   syncService: DDGSyncing,
                   featureFlagger: FeatureFlagger,
                   favicons: Favicons = Favicons.shared,
                   tabManager: TabManager,
                   aiChatSettings: AIChatSettingsProvider,
                   appSettings: AppSettings,
                   aichatFullModeFeature: AIChatFullModeFeatureProviding = AIChatFullModeFeature(),
                   aichatIPadTabFeature: AIChatIPadTabFeatureProviding = AIChatIPadTabFeature(),
                   privacyStats: PrivacyStatsProviding,
                   productSurfaceTelemetry: ProductSurfaceTelemetry,
                   historyManager: HistoryManaging,
                   fireproofing: Fireproofing,
                   keyValueStore: ThrowingKeyValueStoring,
                   tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings(),
                   daxDialogsManager: DaxDialogsManaging,
                   initialTrackerCountState: TabSwitcherTrackerCountViewModel.State) {
        self.bookmarksDatabase = bookmarksDatabase
        self.syncService = syncService
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
        self.favicons = favicons
        self.tabManager = tabManager
        self.aiChatSettings = aiChatSettings
        self.appSettings = appSettings
        self.aichatFullModeFeature = aichatFullModeFeature
        self.aichatIPadTabFeature = aichatIPadTabFeature
        self.privacyStats = privacyStats
        self.productSurfaceTelemetry = productSurfaceTelemetry
        self.historyManager = historyManager
        self.fireproofing = fireproofing
        self.tabSwitcherSettings = tabSwitcherSettings
        self.daxDialogsManager = daxDialogsManager
        self.initialTrackerCountState = initialTrackerCountState
        let tabCountModel = TabCountModel()
        self.tabCountModel = tabCountModel
        self.pickerItems = BrowsingMode.allCases.map { $0.segmentedPickerItem(tabCountModel: tabCountModel) }
        self.selectedBrowsingMode = tabManager.currentBrowsingMode
        self.pickerViewModel = ImageSegmentedPickerViewModel(
                items: pickerItems,
                selectedItem: pickerItems[tabManager.currentBrowsingMode.rawValue],
                configuration: ImageSegmentedPickerConfiguration(),
                scrollProgress: nil,
                isScrollProgressDriven: false)
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    fileprivate func createTitleBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        titleBarView.standardAppearance = appearance
        titleBarView.scrollEdgeAppearance = appearance
    }
    
    private func setupModeToggle() {
        guard fireModeCapability.isFireModeEnabled else {
            return
        }
        let wrapper = TabSwitcherPickerWrapper(viewModel: pickerViewModel)
        let hostingController = UIHostingController(rootView: wrapper)
        hostingController.view.backgroundColor = .clear
        segmentedPickerHostingController = hostingController

        addChild(hostingController)
        hostingController.didMove(toParent: self)

        hostingController.view.frame = CGRect(x: 0, y: 0, width: Constants.modePickerWidth, height: 38)
        titleBarView.topItem?.titleView = hostingController.view

        pickerSelectionCancellable = pickerViewModel.$selectedItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedItem in
                self?.modeToggleSelectionChanged(selectedItem)
            }
    }

    private func modeToggleSelectionChanged(_ selectedItem: ImageSegmentedPickerItem) {
        let newMode: BrowsingMode = pickerItems.first == selectedItem ? .fire : .normal
        guard newMode != selectedBrowsingMode else {
            return
        }
        tabsModel.tabs.forEach { $0.removeObserver(self) }
        let progress: CGFloat = newMode == .fire ? 0 : 1
        pickerViewModel.updateScrollProgress(progress)
        selectedBrowsingMode = newMode
        subscribeToTabChanges()
        currentSelection = tabsModel.currentIndex
        UIView.performWithoutAnimation {
            reloadCollectionView()
            collectionView.layoutIfNeeded()
        }
        updateUIForSelectionMode()
    }

    private func activateLayoutConstraintsBasedOnBarPosition() {
        guard let view = self.view else {
            assertionFailure()
            return
        }
        let isBottomBar = appSettings.currentAddressBarPosition.isBottom

        let isiOS26: Bool
        if #available(iOS 26, *) {
            isiOS26 = true
        } else {
            isiOS26 = false
        }

        // Changing this?  Best change MainView too
        let topOffset = isiOS26 ? 4.0 : -6.0
        let bottomOffset = 8.0
        let navHPadding = isiOS26 ? -6.0 : -2.0
        let toolbarWidthMod = isiOS26 ? 14.0 : 4.0

        // The constants here are to force the ai button to align between the tab switcher and this view
        NSLayoutConstraint.activate([
            titleBarView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: navHPadding),
            titleBarView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -navHPadding),
            isBottomBar ? titleBarView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: topOffset) : nil,
            !isBottomBar ? titleBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: bottomOffset) : nil,

            collectionView.topAnchor.constraint(equalTo: isBottomBar ? view.safeAreaLayoutGuide.topAnchor : titleBarView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            
            // Fire mode empty view
            fireModeEmptyStateHostingController?.view.topAnchor.constraint(equalTo: collectionView.topAnchor),
            fireModeEmptyStateHostingController?.view.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            fireModeEmptyStateHostingController?.view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            fireModeEmptyStateHostingController?.view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),

            interfaceMode.isLarge ? collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor) :
                collectionView.bottomAnchor.constraint(equalTo: isBottomBar ? titleBarView.topAnchor : toolbar.topAnchor),

            borderView.topAnchor.constraint(equalTo: isBottomBar ? view.safeAreaLayoutGuide.topAnchor : titleBarView.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // On iPad large mode constrain to the bottom as the toolbar is hidden
            interfaceMode.isLarge ? borderView.bottomAnchor.constraint(equalTo: view.bottomAnchor) :
                borderView.bottomAnchor.constraint(equalTo: isBottomBar ? titleBarView.topAnchor : toolbar.topAnchor),

            // Always at the bottom
            toolbar.constrainView(view, by: .width, constant: toolbarWidthMod),
            toolbar.constrainView(view, by: .centerX),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ].compactMap { $0 })
    }

    private func setupBarsLayout() {
        // Remove existing constraints to avoid conflicts
        borderView.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        // Clear existing constraints for these views comprehensively
        let viewsToRemoveConstraintsFor: [UIView] = [titleBarView, toolbar, collectionView, borderView]
        viewsToRemoveConstraintsFor.forEach { targetView in
            targetView.removeFromSuperview()
        }

        // Re-add the views to the hierarchy
        view.addSubview(titleBarView)
        view.addSubview(toolbar)
        view.addSubview(collectionView)
        view.addSubview(borderView)

        let toolbarAppearance = UIToolbarAppearance()
        toolbarAppearance.configureWithTransparentBackground()
        toolbarAppearance.shadowColor = .clear
        toolbar.standardAppearance = toolbarAppearance
        toolbar.compactAppearance = toolbarAppearance
        borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
        // On large ipad view don't show the bottom divider
        borderView.isBottomVisible = !interfaceMode.isLarge
        activateLayoutConstraintsBasedOnBarPosition()
    }
    
    func reloadCollectionView() {
        collectionView.reloadData()
        updateFireModeEmptyStateVisibility()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // These should only be done once
        createTitleBar()
        setupModeToggle()
        setupBackgroundView()
        setupFireModeEmptyState()
        collectionView.register(
            TabSwitcherTrackerInfoHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: TabSwitcherTrackerInfoHeaderView.reuseIdentifier
        )
        subscribeToTabChanges()

        // These can be done more than once but don't need to
        decorate()
        becomeFirstResponder()
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsMultipleSelectionDuringEditing = true
        bindTrackerCount()
        trackerCountViewModel?.refresh()
        setupBarButtonActions()

    }

    private func setupBarButtonActions() {
        barsHandler.onPlusButtonTapped = { [weak self] in
            self?.addNewTab()
        }

        barsHandler.onFireButtonTapped = { [weak self] in
            self?.burn(sender: self!.barsHandler.fireButton)
        }

        barsHandler.onDoneButtonTapped = { [weak self] in
            self?.onDonePressed(self!.barsHandler.doneButton)
        }

        barsHandler.onEditButtonTapped = { [weak self] in
            return self?.createEditMenu()
        }

        barsHandler.onTabStyleButtonTapped = { [weak self] in
            self?.onTabStyleChange()
        }

        barsHandler.onSelectAllTapped = { [weak self] in
            self?.selectAllTabs()
        }

        barsHandler.onDeselectAllTapped = { [weak self] in
            self?.deselectAllTabs()
        }

        barsHandler.onMenuButtonTapped = { [weak self] in
            return self?.createMultiSelectionMenu()
        }

        barsHandler.onCloseTabsTapped = { [weak self] in
            self?.closeSelectedTabs()
        }

        barsHandler.onDuckChatTapped = { [weak self] in
            guard let self else { return }
            if self.aichatFullModeFeature.isAvailable || self.aichatIPadTabFeature.isAvailable {
                self.addNewAIChatTab()
            } else {
                self.delegate.tabSwitcherDidRequestAIChat(tabSwitcher: self)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        productSurfaceTelemetry.tabManagerUsed()
        showFireButtonPulseIfNeeded()
    }

    private func showFireButtonPulseIfNeeded() {
        guard daxDialogsManager.isShowingFireDialog, let window = view.window else { return }
        ViewHighlighter.showIn(window, focussedOnButton: barsHandler.fireButton)
    }

    private func setupBackgroundView() {
        let view = UIView(frame: collectionView.frame)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(gesture:))))
        collectionView.backgroundView = view
    }

    private func setupFireModeEmptyState() {
        guard fireModeCapability.isFireModeEnabled else {
            return
        }
        let emptyStateView = FireModeEmptyStateView(type: .tabSwitcher(onNewFireTab: { [weak self] in
            self?.addNewTab()
        }))
        let hostingController = UIHostingController(rootView: emptyStateView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        fireModeEmptyStateHostingController = hostingController
    }

    private func updateFireModeEmptyStateVisibility() {
        let shouldShowEmptyState = selectedBrowsingMode == .fire && tabsModel.tabs.isEmpty
        fireModeEmptyStateHostingController?.view.isHidden = !shouldShowEmptyState
        collectionView.isHidden = shouldShowEmptyState
    }

    func refreshDisplayModeButton() {
        tabsStyle = tabSwitcherSettings.isGridViewEnabled ? .grid : .list
    }

    private func subscribeToTabChanges() {
        tabObserverCancellable = tabsModel.tabsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadCollectionView()
            }
    }

    private func bindTrackerCount() {
        let viewModel = TabSwitcherTrackerCountViewModel(
            settings: tabSwitcherSettings,
            privacyStats: privacyStats,
            featureFlagger: featureFlagger,
            initialState: initialTrackerCountState
        )
        trackerCountViewModel = viewModel
        trackerCountCancellable = viewModel.$state
            .sink { [weak self] state in
                self?.applyTrackerCountState(state)
            }
    }

    private func applyTrackerCountState(_ state: TabSwitcherTrackerCountViewModel.State) {
        guard state != lastAppliedTrackerCountState else { return }
        lastAppliedTrackerCountState = state

        guard state.isVisible else {
            _trackerInfoModel = nil
            updateTrackerInfoHeaderIfVisible()
            collectionView.collectionViewLayout.invalidateLayout()
            return
        }

        _trackerInfoModel = .trackerInfoPanel(
            state: state,
            onTap: { },
            onInfo: { [weak self] in
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

        header.configure(in: self, model: activeTrackerInfoModel)
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTitleViews()
        currentSelection = tabsModel.currentIndex
        updateUIForSelectionMode()
        setupBarsLayout()
        trackerCountViewModel?.refresh()
        updateFireModeEmptyStateVisibility()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        _ = AppWidthObserver.shared.willResize(toWidth: size.width)
        updateUIForSelectionMode()
        setupBarsLayout()
        collectionView.setNeedsLayout()
        collectionView.collectionViewLayout.invalidateLayout()

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
            dismissIfPossible()
        }
    }

    private func scrollToInitialTab() {
        guard let index = tabsModel.currentIndex,
            index < collectionView.numberOfItems(inSection: 0) else { return }
        let indexPath = IndexPath(row: index, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
    }

    func refreshTitleViews() {
        let fireModeEnabled = fireModeCapability.isFireModeEnabled
        let tabsCountTitle = fireModeEnabled ? nil : UserText.numberOfTabs(tabsModel.count)
        let title = selectedTabs.isEmpty ? tabsCountTitle : UserText.numberOfSelectedTabs(withCount: selectedTabs.count)
        titleBarView.topItem?.title = title
        tabCountModel.count = tabManager.normalTabsModel.count
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

    func addNewTab() {
        guard !isProcessingUpdates else { return }
        // Will be dismissed, so no need to process incoming updates
        canUpdateCollection = false

        Pixel.fire(pixel: .tabSwitcherNewTab)
        dismissIfPossible(forceDismissOnEmpty: true)
        // This call needs to be after the dismiss to allow OmniBarEditingStateViewController
        // to present on top of MainVC instead of TabSwitcher.
        // If these calls are switched it'll be immediately dismissed along with this controller.
        delegate.tabSwitcherDidRequestNewTab(tabSwitcher: self)
    }
    
    func addNewAIChatTab() {
        guard !isProcessingUpdates else { return }
        canUpdateCollection = false
        
        dismissIfPossible(forceDismissOnEmpty: true)

        self.delegate.tabSwitcherDidRequestAIChatTab(tabSwitcher: self)
    }

    func bookmarkTabs(withIndexPaths indexPaths: [IndexPath], viewModel: MenuBookmarksInteracting) -> BookmarkAllResult {
        let tabs = self.tabsModel.tabs
        var newCount = 0
        var urls = [URL]()

        indexPaths.compactMap {
            tabsModel.get(tabAt: $0.row)
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
            dismissIfPossible()
        }
    }

    @IBAction func onFirePressed(sender: AnyObject) {
        burn(sender: sender)
    }

    func forgetAll(_ fireRequest: FireRequest) {
        self.delegate.tabSwitcherDidRequestForgetAll(tabSwitcher: self,
                                                     fireRequest: fireRequest)
    }

    /// Dismisses the tab switcher unless fire mode requires the empty state to stay visible.
    ///
    /// Dismiss is allowed when any of these hold:
    /// - `forceDismissOnEmpty`: caller explicitly wants dismiss (e.g. after creating a new tab)
    /// - `canDismissOnEmpty`: normal mode — always safe to dismiss
    /// - `!tabsModel.isEmpty`: fire mode still has tabs, so the user picked one
    func dismissIfPossible(animated: Bool = true, forceDismissOnEmpty: Bool = false) {
        guard forceDismissOnEmpty
                || canDismissOnEmpty
                || !tabsModel.isEmpty else { return }
        ViewHighlighter.hideAll()
        dismiss(animated: animated, completion: nil)
    }

    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        canUpdateCollection = false
        tabManager.allTabsModel.tabs.forEach { $0.removeObserver(self) }

        let tabsModel = tabManager.tabsModel(for: selectedBrowsingMode)

        if selectedBrowsingMode.allowsEmpty && tabsModel.isEmpty {
            tabManager.setBrowsingMode(selectedBrowsingMode)
        } else {
            let selectedTab = tabsModel.get(tabAt: currentSelection)
            delegate?.tabSwitcher(self, didFinishWithSelectedTab: selectedTab)
        }

        super.dismiss(animated: animated) {
            completion?()
        }
    }
}

extension TabSwitcherViewController: TabViewCellDelegate {

    func deleteTabsAtIndexPaths(_ indexPaths: [IndexPath]) {
        let allTabsDeleted = tabsModel.count == indexPaths.count
        let tabsToClose = indexPaths.compactMap { tabsModel.get(tabAt: $0.row) }
        delegate?.tabSwitcher(self, willCloseTabs: tabsToClose)

        collectionView.performBatchUpdates {
            isProcessingUpdates = true
            tabManager.bulkRemoveTabs(tabsToClose, in: tabsModel)
            collectionView.deleteItems(at: indexPaths)
            if allTabsDeleted && !canDismissOnEmpty && isEditing {
                self.transitionFromMultiSelect(reloadCollectionView: false)
            }
        } completion: { _ in
            self.isProcessingUpdates = false
            if self.tabsModel.tabs.isEmpty && !self.tabsModel.allowsEmpty {
                let newTab = Tab(fireTab: self.tabsModel.shouldCreateFireTabs)
                self.tabsModel.insert(tab: newTab, placement: .atEnd, selectNewTab: true)
            }
            self.currentSelection = self.tabsModel.currentIndex
            self.delegate?.tabSwitcherDidBulkCloseTabs(tabSwitcher: self)
            self.refreshTitleViews()
            self.updateUIForSelectionMode()
            self.updateFireModeEmptyStateVisibility()
            if allTabsDeleted {
                self.dismissIfPossible()
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
        
        if indexPath.row < tabsModel.count,
           let tab = tabsModel.get(tabAt: indexPath.row) {
            tab.removeObserver(self)
            tab.addObserver(self)
            let isFireModeEnabled = fireModeCapability.isFireModeEnabled
            cell.update(withTab: tab,
                        isSelectionModeEnabled: self.isEditing,
                        preview: previewsSource.preview(for: tab),
                        isFireModeEnabled: isFireModeEnabled)
        }
        
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView,
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

        header.configure(in: self, model: activeTrackerInfoModel)
        return header
    }

}

extension TabSwitcherViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isEditing {
            Pixel.fire(pixel: .tabSwitcherTabSelected)
            (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
            updateUIForSelectionMode()
            refreshTitleViews()
        } else {
            currentSelection = indexPath.row
            Pixel.fire(pixel: .tabSwitcherSwitchTabs)
            dismissIfPossible()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
        updateUIForSelectionMode()
        refreshTitleViews()
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
        let size: CGSize
        if tabSwitcherSettings.isGridViewEnabled {
            let columnWidth = calculateColumnWidth(minimumColumnWidth: 150, maxColumns: 4)
            let rowHeight = calculateRowHeight(columnWidth: columnWidth)
            size = CGSize(width: floor(columnWidth),
                          height: floor(rowHeight))
        } else {
            let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let spacing = layout?.sectionInset.left ?? 0.0
            
            let width = min(664, collectionView.bounds.size.width - 2 * spacing)
            
            size = CGSize(width: width, height: 70)
        }
        return size
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard activeTrackerInfoModel != nil else { return .zero }
        return CGSize(width: collectionView.bounds.width, height: TabSwitcherTrackerInfoHeaderView.estimatedHeight)
    }

}

extension TabSwitcherViewController: TabObserver {
    
    func didChange(tab: Tab) {
        guard let index = self.tabsModel.indexOf(tab: tab),
              let cell = collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? TabViewCell else {
            return
        }
        // Check the current tab is the one we want to update, if not it might have been updated elsewhere
        guard cell.tab?.uid == tab.uid else {
            DailyPixel.fireDaily(.debugTabSwitcherDidChangeInvalidState)
            return
        }

        let isFireModeEnabled = fireModeCapability.isFireModeEnabled
        cell.update(withTab: tab,
                    isSelectionModeEnabled: self.isEditing,
                    preview: previewsSource.preview(for: tab),
                    isFireModeEnabled: isFireModeEnabled)
    }
}

extension TabSwitcherViewController {
    
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = theme.backgroundColor
        
        refreshDisplayModeButton()
        
        titleBarView.tintColor = theme.barTintColor
        if #available(iOS 26.0, *) {
            titleBarView.backItem?.rightBarButtonItem?.hidesSharedBackground = true
        }

        toolbar.barTintColor = theme.barBackgroundColor
        toolbar.tintColor = UIColor(singleUseColor: .toolbarButton)

        reloadCollectionView()
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
            guard let tab = tabsModel.get(tabAt: source.row) else {
                return
            }
            tabsModel.move(tab: tab, to: destination.row)
            currentSelection = tabsModel.currentIndex
            collectionView.deleteItems(at: [source])
            collectionView.insertItems(at: [destination])
        } completion: { _ in
            if self.isEditing {
                self.reloadCollectionView() // Clears the selection
                collectionView.selectItem(at: destination, animated: true, scrollPosition: [])
                self.barsHandler.configureButtonActions(tabsStyle: self.tabsStyle, canShowSelectionMenu: self.canShowSelectionMenu)
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
            || (location.x > lastItemFrame.maxX + 15 && location.y > lastItemFrame.minY) { // to the right of the last item is the end as long as it's also at least below the start of the frame
            // The tap is in the whitespace area at the end
           return true
        }

        return false
    }
}

struct TabSwitcherPickerWrapper: View {
    @ObservedObject var viewModel: ImageSegmentedPickerViewModel

    var body: some View {
        ImageSegmentedPickerView(viewModel: viewModel)
            .frame(width: TabSwitcherViewController.Constants.modePickerWidth)
    }
}

// MARK: - Picker Items

extension BrowsingMode {
    func segmentedPickerItem(tabCountModel: TabCountModel) -> ImageSegmentedPickerItem {
        switch self {
        case .normal:
            let itemView = AnyView(TabCountBadge(model: tabCountModel))
            return ImageSegmentedPickerItem(text: nil,
                                            selectedCustomView: itemView,
                                            unselectedCustomView: itemView)
            
        case .fire:
            return ImageSegmentedPickerItem(
                text: nil,
                selectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size24.fireTabs),
                unselectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size24.fireTabs))
        }
    }
}
