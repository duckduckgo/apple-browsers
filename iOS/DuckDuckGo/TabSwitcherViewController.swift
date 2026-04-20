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
import TipKit
import UIComponents

class TabSwitcherViewController: UIViewController {

    struct Constants {
        static let preferredMinNumberOfRows: CGFloat = 2.7

        static let cellMinHeight: CGFloat = 140.0
        static let cellMaxHeight: CGFloat = 209.0
        static let modePickerWidth: CGFloat = 120
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
    @IBOutlet weak var toolbar: UIToolbar!

    private(set) var pagingScrollView: UIScrollView!
    private var firePageContainer: UIView!
    private var normalPageContainer: UIView!
    private(set) var firePageController: TabSwitcherPageViewController?
    private(set) var normalPageController: TabSwitcherPageViewController!

    var activePageController: TabSwitcherPageViewController {
        if selectedBrowsingMode == .fire, let firePageController {
            return firePageController
        }
        return normalPageController
    }

    var collectionView: UICollectionView {
        activePageController.collectionView
    }

    var currentSelection: Int? {
        get { activePageController.currentSelection }
        set { activePageController.currentSelection = newValue }
    }

    weak var delegate: TabSwitcherDelegate!
    weak var previewsSource: TabPreviewsSource!

    var selectedTabs: [IndexPath] {
        activePageController.selectedIndexPaths
    }

    private(set) var bookmarksDatabase: CoreDataDatabase
    let syncService: DDGSyncing

    let tabSwitcherSettings: TabSwitcherSettings
    var isProcessingUpdates = false

    private var canUpdateCollection = true {
        didSet {
            normalPageController?.canUpdateCollection = canUpdateCollection
            firePageController?.canUpdateCollection = canUpdateCollection
        }
    }

    let favicons: FaviconManaging

    var tabsStyle: TabsStyle = .list
    var interfaceMode: InterfaceMode = .regularSize
    var canShowSelectionMenu = false
    var menuBuilder: TabSwitcherMenuBuilding = DefaultTabSwitcherMenuBuilder()

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

    private let appSettings: AppSettings
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
    private var fireTabsTipTask: Task<Void, Never>?
    var fireModePromotionsCoordinator: FireModePromotionCoordinating?
    private var fireModeCapability: FireModeCapable {
        FireModeCapability.create()
    }

    required init?(coder: NSCoder,
                   bookmarksDatabase: CoreDataDatabase,
                   syncService: DDGSyncing,
                   featureFlagger: FeatureFlagger,
                   favicons: FaviconManaging,
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
                configuration: ImageSegmentedPickerConfiguration(outerHeight: 44,
                                                                 innerHeight: 40,
                                                                 innerHorizontalPadding: 2),
                scrollProgress: nil,
                isScrollProgressDriven: true)
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

        let isBottomBar = appSettings.currentAddressBarPosition.isBottom
        let barHeight: CGFloat = fireModeCapability.isFireModeEnabled ? (isBottomBar ? 72 : 60) : 44
        let heightConstraint = titleBarView.heightAnchor.constraint(greaterThanOrEqualToConstant: barHeight)
        heightConstraint.priority = .required
        heightConstraint.isActive = true
    }
    
    private func setupModeToggle() {
        guard fireModeCapability.isFireModeEnabled else {
            return
        }
        let isBottomBar = appSettings.currentAddressBarPosition.isBottom
        let topPadding: CGFloat = isBottomBar ? 18 : 8
        let bottomPadding: CGFloat = isBottomBar ? 6 : 8
        let wrapper = TabSwitcherPickerWrapper(viewModel: pickerViewModel, topPadding: topPadding, bottomPadding: bottomPadding)
        let hostingController = UIHostingController(rootView: wrapper)
        hostingController.view.backgroundColor = .clear
        segmentedPickerHostingController = hostingController

        addChild(hostingController)
        hostingController.didMove(toParent: self)

        let height: CGFloat = isBottomBar ? 68 : 60
        hostingController.view.frame = CGRect(x: 0, y: 0, width: Constants.modePickerWidth, height: height)
        titleBarView.topItem?.titleView = hostingController.view

        pickerSelectionCancellable = pickerViewModel.$selectedItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedItem in
                self?.modeToggleSelectionChanged(selectedItem)
            }
    }

    // MARK: - Fire Tabs Tip

    func showFireTabsTipIfNeeded() {
        guard #available(iOS 17.0, *) else { return }
        guard fireModeCapability.isFireModeEnabled else { return }
        guard selectedBrowsingMode != .fire else { return }
        guard let sourceView = segmentedPickerHostingController?.view else { return }

        fireTabsTipTask?.cancel()

        let tip = FireTabsTip()

        if fireModePromotionsCoordinator?.isTabSwitcherTipExpired == true {
            tip.invalidate(reason: .displayCountExceeded)
            return
        }

        fireTabsTipTask = Task { @MainActor [weak self] in
            for await shouldDisplay in tip.shouldDisplayUpdates {
                guard let self else { return }
                if shouldDisplay {
                    self.fireModePromotionsCoordinator?.markTabSwitcherTipShown()
                    let popoverController = TipUIPopoverViewController(tip, sourceItem: sourceView)
                    popoverController.popoverPresentationController?.permittedArrowDirections = [.up, .down]
                    self.present(popoverController, animated: true)
                } else if self.presentedViewController is TipUIPopoverViewController {
                    self.dismiss(animated: true)
                }
            }
        }
    }

    private func modeToggleSelectionChanged(_ selectedItem: ImageSegmentedPickerItem) {
        let newMode: BrowsingMode = pickerItems.first == selectedItem ? .fire : .normal
        guard newMode != selectedBrowsingMode else {
            return
        }
        selectedBrowsingMode = newMode
        syncPagingScrollViewToCurrentMode(animated: true)
        scrollToInitialTab()
        updateUIForSelectionMode()

        if newMode == .fire {
            if #available(iOS 17.0, *) {
                FireTabsTip.hasVisitedFireMode = true
            }
            fireModePromotionsCoordinator?.markFireModeVisited()
        }
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
        let topOffset = isBottomBar && fireModeCapability.isFireModeEnabled ? 16 : (isiOS26 ? 4.0 : -6.0)
        let bottomOffset = 8.0
        let navHPadding = isiOS26 ? -6.0 : -2.0
        let toolbarWidthMod = isiOS26 ? 14.0 : 4.0

        // The constants here are to force the ai button to align between the tab switcher and this view
        NSLayoutConstraint.activate([
            titleBarView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: navHPadding),
            titleBarView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -navHPadding),
            isBottomBar ? titleBarView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: topOffset) : nil,
            !isBottomBar ? titleBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: bottomOffset) : nil,

            pagingScrollView.topAnchor.constraint(equalTo: isBottomBar ? view.safeAreaLayoutGuide.topAnchor : titleBarView.bottomAnchor),
            pagingScrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            pagingScrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            interfaceMode.isLarge ? pagingScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor) :
                pagingScrollView.bottomAnchor.constraint(equalTo: isBottomBar ? titleBarView.topAnchor : toolbar.topAnchor),

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
        pagingScrollView.translatesAutoresizingMaskIntoConstraints = false

        let viewsToRemoveConstraintsFor: [UIView] = [titleBarView, toolbar, pagingScrollView, borderView]
        viewsToRemoveConstraintsFor.forEach { targetView in
            targetView.removeFromSuperview()
        }

        view.addSubview(titleBarView)
        view.addSubview(toolbar)
        view.addSubview(pagingScrollView)
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

    override func viewDidLoad() {
        super.viewDidLoad()

        createTitleBar()
        setupModeToggle()
        setupPagingScrollView()

        decorate()
        becomeFirstResponder()
        setupBarButtonActions()
    }

    private func setupPagingScrollView() {
        let isFireModeEnabled = fireModeCapability.isFireModeEnabled

        pagingScrollView = UIScrollView()
        pagingScrollView.isPagingEnabled = isFireModeEnabled
        pagingScrollView.isScrollEnabled = isFireModeEnabled
        pagingScrollView.showsHorizontalScrollIndicator = false
        pagingScrollView.showsVerticalScrollIndicator = false
        pagingScrollView.bounces = false
        pagingScrollView.delegate = self
        pagingScrollView.translatesAutoresizingMaskIntoConstraints = false
        pagingScrollView.contentInsetAdjustmentBehavior = .never

        normalPageContainer = UIView()
        normalPageContainer.translatesAutoresizingMaskIntoConstraints = false

        if isFireModeEnabled {
            firePageContainer = UIView()
            firePageContainer.translatesAutoresizingMaskIntoConstraints = false
            pagingScrollView.addSubview(firePageContainer)
        }

        pagingScrollView.addSubview(normalPageContainer)

        var constraints = [NSLayoutConstraint]()

        if isFireModeEnabled {
            constraints.append(contentsOf: [
                firePageContainer.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor),
                firePageContainer.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
                firePageContainer.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
                firePageContainer.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor),
                firePageContainer.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),

                normalPageContainer.leadingAnchor.constraint(equalTo: firePageContainer.trailingAnchor),
            ])
        } else {
            constraints.append(
                normalPageContainer.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor)
            )
        }

        constraints.append(contentsOf: [
            normalPageContainer.trailingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.trailingAnchor),
            normalPageContainer.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
            normalPageContainer.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
            normalPageContainer.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor),
            normalPageContainer.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),
        ])

        NSLayoutConstraint.activate(constraints)

        if isFireModeEnabled {
            firePageController = TabSwitcherPageViewController(
                browsingMode: .fire,
                tabsModel: tabManager.tabsModel(for: .fire),
                previewsSource: previewsSource,
                tabSwitcherSettings: tabSwitcherSettings,
                trackerCountViewModel: nil,
                isFireModeEnabled: isFireModeEnabled)
            firePageController?.pageDelegate = self
            firePageController?.onNewFireTab = { [weak self] in
                self?.addNewTab()
            }
            embedPageController(firePageController, in: firePageContainer)
        }

        let trackerCountViewModel = TabSwitcherTrackerCountViewModel(
            settings: tabSwitcherSettings,
            privacyStats: privacyStats,
            featureFlagger: featureFlagger,
            initialState: initialTrackerCountState
        )
        normalPageController = TabSwitcherPageViewController(
            browsingMode: .normal,
            tabsModel: tabManager.tabsModel(for: .normal),
            previewsSource: previewsSource,
            tabSwitcherSettings: tabSwitcherSettings,
            trackerCountViewModel: trackerCountViewModel,
            isFireModeEnabled: isFireModeEnabled)
        normalPageController.pageDelegate = self
        embedPageController(normalPageController, in: normalPageContainer)

    }

    private func embedPageController(_ pageController: TabSwitcherPageViewController?, in container: UIView) {
        guard let pageController else { return }
        addChild(pageController)
        container.addSubview(pageController.view)
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageController.view.topAnchor.constraint(equalTo: container.topAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        pageController.didMove(toParent: self)
    }

    private func setupBarButtonActions() {
        barsHandler.onPlusButtonTapped = { [weak self] in
            self?.addNewTab()
        }

        barsHandler.onNewFireTabTapped = { [weak self] in
            self?.addNewFireTab()
        }

        barsHandler.onNewNormalTabTapped = { [weak self] in
            self?.addNewNormalTab()
        }

        barsHandler.configurePlusButtonLongPressMenu(isFireModeEnabled: fireModeCapability.isFireModeEnabled)

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
        showFireTabsTipIfNeeded()
    }

    private func showFireButtonPulseIfNeeded() {
        guard daxDialogsManager.isShowingFireDialog, let window = view.window else { return }
        ViewHighlighter.showIn(window, focussedOnButton: barsHandler.fireButton)
    }

    func refreshDisplayModeButton() {
        tabsStyle = tabSwitcherSettings.isGridViewEnabled ? .grid : .list
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTitleViews()
        currentSelection = tabsModel.currentIndex
        updateUIForSelectionMode()
        setupBarsLayout()
        firePageController?.updateEmptyStateVisibility()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        _ = AppWidthObserver.shared.willResize(toWidth: size.width)
        updateUIForSelectionMode()
        setupBarsLayout()
        for pageController in [self.firePageController, self.normalPageController].compactMap({ $0 }) {
            pageController.view.setNeedsLayout()
            pageController.collectionView.setNeedsLayout()
            pageController.collectionView.collectionViewLayout.invalidateLayout()
        }
        
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.syncPagingScrollViewToCurrentMode(animated: false)
        }, completion: nil)
        
    }

    func prepareForPresentation() {
        view.layoutIfNeeded()
        syncPagingScrollViewToCurrentMode(animated: false)
        self.scrollToInitialTab()
    }

    private func syncPagingScrollViewToCurrentMode(animated: Bool) {
        guard firePageController != nil else { return }
        let targetX: CGFloat = selectedBrowsingMode == .fire ? 0 : pagingScrollView.frame.width
        pagingScrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
    }

    private func scrollToInitialTab() {
        normalPageController.scrollToInitialTab()
        firePageController?.scrollToInitialTab()
    }

    func refreshTitleViews() {
        let fireModeEnabled = fireModeCapability.isFireModeEnabled
        // Suppress the text title in fire mode when NOT editing — the segment picker titleView is
        // visible then and covers the title area. In editing mode the picker is hidden, so a text
        // title is always required.
        let tabsCountTitle = (fireModeEnabled && !isEditing) ? nil : UserText.numberOfTabs(tabsModel.count)
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

    func addNewFireTab() {
        guard !isProcessingUpdates else { return }
        canUpdateCollection = false

        dismissIfPossible(forceDismissOnEmpty: true)
        delegate.tabSwitcherDidRequestNewFireTab(tabSwitcher: self)
    }

    func addNewNormalTab() {
        guard !isProcessingUpdates else { return }
        canUpdateCollection = false

        dismissIfPossible(forceDismissOnEmpty: true)
        delegate.tabSwitcherDidRequestNewNormalTab(tabSwitcher: self)
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
        fireTabsTipTask?.cancel()
        fireTabsTipTask = nil
        canUpdateCollection = false
        if let firePC = firePageController {
            tabManager.tabsModel(for: .fire).tabs.forEach { $0.removeObserver(firePC) }
        }
        if let normalPC = normalPageController {
            tabManager.tabsModel(for: .normal).tabs.forEach { $0.removeObserver(normalPC) }
        }

        let tabsModel = tabManager.tabsModel(for: selectedBrowsingMode)

        if selectedBrowsingMode.allowsEmpty && tabsModel.isEmpty {
            tabManager.setBrowsingMode(selectedBrowsingMode)
        } else {
            let selectedTab = activePageController.selectedTab
            delegate?.tabSwitcher(self, didFinishWithSelectedTab: selectedTab)
        }

        super.dismiss(animated: animated) {
            completion?()
        }
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

    }

}

// MARK: - UIScrollViewDelegate (paging)

extension TabSwitcherViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        let pageWidth = scrollView.frame.width
        guard pageWidth > 0 else { return }

        let progress = max(0, min(1, scrollView.contentOffset.x / pageWidth))
        pickerViewModel.updateScrollProgress(progress)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        let pageWidth = scrollView.frame.width
        guard pageWidth > 0 else { return }
        let currentPage = Int(scrollView.contentOffset.x / pageWidth)
        let newMode: BrowsingMode = currentPage == 0 ? .fire : .normal

        if newMode != selectedBrowsingMode {
            pickerViewModel.selectItem(pickerItems[newMode.rawValue])
        }
    }
}

// MARK: - TabSwitcherPageDelegate

extension TabSwitcherViewController: TabSwitcherPageDelegate {

    func page(_ page: TabSwitcherPageViewController, didSelectTabAt index: Int) {
        updateUIForSelectionMode()
        refreshTitleViews()
    }

    func page(_ page: TabSwitcherPageViewController, didDeselectTab: Void) {
        updateUIForSelectionMode()
        refreshTitleViews()
    }

    func page(_ page: TabSwitcherPageViewController, willDeleteTabs tabs: [Tab], allDeleted: Bool) {
        delegate?.tabSwitcher(self, willCloseTabs: tabs)
        tabManager.bulkRemoveTabs(tabs, in: page.tabsModel)
        // Use page.tabsModel — self.tabsModel can drift via selectedBrowsingMode mid-animation.
        if allDeleted && page.tabsModel.allowsEmpty && isEditing {
            transitionFromMultiSelect(reloadCollectionView: false)
        }
    }

    func pageDidDeleteTabs(_ page: TabSwitcherPageViewController, allDeleted: Bool) {
        // Use page.tabsModel — self.tabsModel can drift via selectedBrowsingMode mid-animation.
        let pageModel = page.tabsModel
        if pageModel.tabs.isEmpty && !pageModel.allowsEmpty {
            let newTab = Tab(fireTab: pageModel.shouldCreateFireTabs)
            pageModel.insert(tab: newTab, placement: .atEnd, selectNewTab: true)
        }
        page.currentSelection = pageModel.currentIndex
        delegate?.tabSwitcherDidBulkCloseTabs(tabSwitcher: self)
        refreshTitleViews()
        updateUIForSelectionMode()
        firePageController?.updateEmptyStateVisibility()
        // Only dismiss for modes that don't allow empty (normal); fire shows empty state instead.
        if allDeleted && !pageModel.allowsEmpty {
            dismissIfPossible()
        }
    }

    func page(_ page: TabSwitcherPageViewController, didReorderTabs: Void) {
        if isEditing {
            barsHandler.configureButtonActions(tabsStyle: tabsStyle, canShowSelectionMenu: canShowSelectionMenu)
        }
        delegate.tabSwitcherDidReorderTabs(tabSwitcher: self)
    }

    func page(_ page: TabSwitcherPageViewController, contextMenuForTabsAt indexPaths: [IndexPath]) -> UIMenu? {
        return createLongPressMenuForTabs(atIndexPaths: indexPaths)
    }

    func pageDidRequestDismiss(_ page: TabSwitcherPageViewController) {
        if isEditing {
            transitionFromMultiSelect()
        } else {
            dismissIfPossible()
        }
    }

    func pageCellDidBeginSwipe(_ page: TabSwitcherPageViewController) {
        pagingScrollView.isScrollEnabled = false
    }

    func pageCellDidEndSwipe(_ page: TabSwitcherPageViewController) {
        pagingScrollView.isScrollEnabled = firePageController != nil && !isEditing
    }

    func pageCellDidBeginDrag(_ page: TabSwitcherPageViewController) {
        pagingScrollView.isScrollEnabled = false
    }

    func pageCellDidEndDrag(_ page: TabSwitcherPageViewController) {
        pagingScrollView.isScrollEnabled = firePageController != nil && !isEditing
    }
}

struct TabSwitcherPickerWrapper: View {
    @ObservedObject var viewModel: ImageSegmentedPickerViewModel
    var topPadding: CGFloat = 0
    var bottomPadding: CGFloat = 0

    var body: some View {
        ImageSegmentedPickerView(viewModel: viewModel)
            .frame(width: TabSwitcherViewController.Constants.modePickerWidth)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
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
