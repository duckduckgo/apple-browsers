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

    private(set) var chrome: TabSwitcherChrome!

    private(set) var pagingScrollView: UIScrollView!
    private var firePageContainer: UIView!
    private var normalPageContainer: UIView!
    private(set) var firePageController: TabSwitcherPageViewController?
    private(set) var normalPageController: TabSwitcherPageViewController!
    private var modeChangeFromSwipe = false

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

    private let floatingUIManaging: FloatingUIManaging

    let featureFlagger: FeatureFlagger
    let tabManager: TabManager
    let historyManager: HistoryManaging
    let fireproofing: Fireproofing
    let aiChatSettings: AIChatSettingsProvider
    let privacyStats: PrivacyStatsProviding
    let keyValueStore: ThrowingKeyValueStoring
    let daxDialogsManager: DaxDialogsManaging
    private let duckAIGridContentProvider: DuckAIGridContentProviding?
    private let duckAIVoiceSessionTracker: DuckAIVoiceSessionTracking?
    var tabsModel: TabsModelManaging {
        tabManager.tabsModel(for: selectedBrowsingMode)
    }

    var canDismissOnEmpty: Bool {
        !tabsModel.allowsEmpty
    }
    
    private let appSettings: AppSettings
    private let initialTrackerCountState: TabSwitcherTrackerCountViewModel.State
    
    private(set) var aichatFullModeFeature: AIChatFullModeFeatureProviding

    private let productSurfaceTelemetry: ProductSurfaceTelemetry

    private var pickerViewModel: ImageSegmentedPickerViewModel
    private let pickerItems: [ImageSegmentedPickerItem]
    private let tabCountModel: TabCountModel
    private(set) var selectedBrowsingMode: BrowsingMode
    private(set) var segmentedPickerHostingController: UIHostingController<ImageSegmentedPickerView>?
    private var pickerSelectionCancellable: AnyCancellable?
    var fireModeCapability: FireModeCapable {
        FireModeCapability.create()
    }

    init(bookmarksDatabase: CoreDataDatabase,
         syncService: DDGSyncing,
         featureFlagger: FeatureFlagger,
         favicons: FaviconManaging,
         tabManager: TabManager,
         aiChatSettings: AIChatSettingsProvider,
         appSettings: AppSettings,
         aichatFullModeFeature: AIChatFullModeFeatureProviding = AIChatFullModeFeature(),
         privacyStats: PrivacyStatsProviding,
         productSurfaceTelemetry: ProductSurfaceTelemetry,
         historyManager: HistoryManaging,
         fireproofing: Fireproofing,
         keyValueStore: ThrowingKeyValueStoring,
         tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings(),
         daxDialogsManager: DaxDialogsManaging,
         initialTrackerCountState: TabSwitcherTrackerCountViewModel.State,
         duckAIGridContentProvider: DuckAIGridContentProviding?,
         duckAIVoiceSessionTracker: DuckAIVoiceSessionTracking?,
         floatingUIManaging: FloatingUIManaging? = nil) {
        self.bookmarksDatabase = bookmarksDatabase
        self.syncService = syncService
        self.featureFlagger = featureFlagger
        self.floatingUIManaging = floatingUIManaging ?? FloatingUIManager(featureFlagger: featureFlagger)
        self.keyValueStore = keyValueStore
        self.favicons = favicons
        self.tabManager = tabManager
        self.aiChatSettings = aiChatSettings
        self.appSettings = appSettings
        self.aichatFullModeFeature = aichatFullModeFeature
        self.privacyStats = privacyStats
        self.productSurfaceTelemetry = productSurfaceTelemetry
        self.historyManager = historyManager
        self.fireproofing = fireproofing
        self.tabSwitcherSettings = tabSwitcherSettings
        self.daxDialogsManager = daxDialogsManager
        self.initialTrackerCountState = initialTrackerCountState
        self.duckAIGridContentProvider = duckAIGridContentProvider
        self.duckAIVoiceSessionTracker = duckAIVoiceSessionTracker
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
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupModeToggle() {
        guard fireModeCapability.isFireModeEnabled else {
            return
        }
        let pickerView = ImageSegmentedPickerView(viewModel: pickerViewModel)
        let hostingController = UIHostingController(rootView: pickerView)
        hostingController.view.backgroundColor = .clear
        segmentedPickerHostingController = hostingController

        addChild(hostingController)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.widthAnchor.constraint(equalToConstant: Constants.modePickerWidth),
        ])
        chrome.setCenterView(hostingController.view)

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
        let source = modeChangeFromSwipe ? "swipe" : "tap"
        modeChangeFromSwipe = false
        selectedBrowsingMode = newMode
        Pixel.fire(pixel: .tabSwitcherModeToggled, withAdditionalParameters: [
            PixelParameters.browsingMode: newMode.pixelParamValue,
            PixelParameters.source: source
        ])
        syncPagingScrollViewToCurrentMode(animated: true)
        scrollToInitialTab()
        updateUIForSelectionMode()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupPagingScrollView()

        chrome = makeChrome()
        chrome.install(in: view, contentView: pagingScrollView)
        chrome.actions = makeChromeActions()
        chrome.configurePlusButtonLongPressMenu(isFireModeEnabled: fireModeCapability.isFireModeEnabled)

        setupModeToggle()

        decorate()
        becomeFirstResponder()
    }

    private func makeChrome() -> TabSwitcherChrome {
        let isFloating = floatingUIManaging.isFloatingUIEnabled
        let chrome = TabSwitcherChromeFactory.makeChrome(isFloatingUIEnabled: isFloating,
                                                         appSettings: appSettings)
        return chrome
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
        if #available(iOS 17.0, *) {
            pagingScrollView.allowsKeyboardScrolling = false
        }

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
                isFireModeEnabled: isFireModeEnabled,
                duckAIGridContentProvider: duckAIGridContentProvider,
                duckAIVoiceSessionTracker: duckAIVoiceSessionTracker)
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
            isFireModeEnabled: isFireModeEnabled,
            duckAIGridContentProvider: duckAIGridContentProvider,
            duckAIVoiceSessionTracker: duckAIVoiceSessionTracker)
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

    private func makeChromeActions() -> TabSwitcherChromeActions {
        var actions = TabSwitcherChromeActions()

        actions.onPlusTapped = { [weak self] in
            self?.addNewTab()
        }

        actions.onNewFireTabTapped = { [weak self] in
            self?.addNewFireTab(source: .tabSwitcherLongPress)
        }

        actions.onNewNormalTabTapped = { [weak self] in
            self?.addNewNormalTab()
        }

        actions.onFireTapped = { [weak self] in
            guard let self else { return }
            self.burn(sender: self.chrome.fireButton)
        }

        actions.onDoneTapped = { [weak self] in
            self?.doneAction()
        }

        actions.onEditMenuRequested = { [weak self] in
            return self?.createEditMenu()
        }

        actions.onSelectTabsStyle = { [weak self] style in
            self?.setTabsStyle(style)
        }

        actions.onToggleTabsStyle = { [weak self] in
            self?.onTabStyleChange()
        }

        actions.onSelectAllTapped = { [weak self] in
            self?.selectAllTabs()
        }

        actions.onDeselectAllTapped = { [weak self] in
            self?.deselectAllTabs()
        }

        actions.onMultiSelectMenuRequested = { [weak self] in
            return self?.createMultiSelectionMenu()
        }

        actions.onCloseTabsTapped = { [weak self] in
            self?.closeSelectedTabs()
        }

        actions.onDuckChatTapped = { [weak self] in
            guard let self else { return }
            if self.aichatFullModeFeature.isAvailable || DevicePlatform.isIpad {
                self.addNewAIChatTab()
            } else {
                self.delegate.tabSwitcherDidRequestAIChat(tabSwitcher: self)
            }
        }

        return actions
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        productSurfaceTelemetry.tabManagerUsed()
        showFireButtonPulseIfNeeded()
    }

    private func showFireButtonPulseIfNeeded() {
        guard daxDialogsManager.isShowingFireDialog,
              let window = view.window else { return }

        if let view = chrome.fireButton.customView {
            // Pre-floating UI
            ViewHighlighter.showIn(window, focussedOnView: view)
        } else {
            // Floating UI
            ViewHighlighter.showIn(window, focussedOnButton: chrome.fireButton)
        }
    }

    func refreshDisplayModeButton() {
        tabsStyle = tabSwitcherSettings.isGridViewEnabled ? .grid : .list
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTitleViews()
        currentSelection = tabsModel.currentIndex
        updateUIForSelectionMode()
        chrome.layout(addressBarPosition: appSettings.currentAddressBarPosition, interfaceMode: interfaceMode)
        firePageController?.updateEmptyStateVisibility()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        _ = AppWidthObserver.shared.willResize(toWidth: size.width)
        updateUIForSelectionMode()
        chrome.layout(addressBarPosition: appSettings.currentAddressBarPosition, interfaceMode: interfaceMode)
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
        chrome.setTitle(title)
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

        Pixel.fire(pixel: .tabSwitcherNewTab, withAdditionalParameters: [
            PixelParameters.browsingMode: selectedBrowsingMode.pixelParamValue
        ])
        dismissIfPossible(forceDismissOnEmpty: true)
        // This call needs to be after the dismiss to allow OmniBarEditingStateViewController
        // to present on top of MainVC instead of TabSwitcher.
        // If these calls are switched it'll be immediately dismissed along with this controller.
        delegate.tabSwitcherDidRequestNewTab(tabSwitcher: self)
    }

    func addNewFireTab(source: FireModeSwitchSource) {
        guard !isProcessingUpdates else { return }
        canUpdateCollection = false

        Pixel.fire(pixel: .tabSwitcherNewTab, withAdditionalParameters: [
            PixelParameters.browsingMode: BrowsingMode.fire.pixelParamValue
        ])
        dismissIfPossible(forceDismissOnEmpty: true)
        delegate.tabSwitcherDidRequestNewFireTab(tabSwitcher: self, source: source)
    }

    func addNewNormalTab() {
        guard !isProcessingUpdates else { return }
        canUpdateCollection = false

        Pixel.fire(pixel: .tabSwitcherNewTab, withAdditionalParameters: [
            PixelParameters.browsingMode: BrowsingMode.normal.pixelParamValue
        ])
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

    func doneAction() {
        if isEditing {
            transitionFromMultiSelect()
        } else {
            dismissIfPossible()
        }
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
        // When a presented child (e.g. TipKit popover) is being dismissed, skip
        // tab-switcher teardown — only forward to super so the child is removed.
        if presentedViewController != nil {
            super.dismiss(animated: animated, completion: completion)
            return
        }

        canUpdateCollection = false
        if let firePC = firePageController {
            tabManager.tabsModel(for: .fire).tabs.forEach { $0.removeObserver(firePC) }
        }
        if let normalPC = normalPageController {
            tabManager.tabsModel(for: .normal).tabs.forEach { $0.removeObserver(normalPC) }
        }

        let tabsModel = tabManager.tabsModel(for: selectedBrowsingMode)

        if selectedBrowsingMode.allowsEmpty && tabsModel.isEmpty {
            tabManager.setBrowsingMode(selectedBrowsingMode, source: .tabSelection)
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

        chrome.decorate(theme: theme)
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
            modeChangeFromSwipe = true
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
            updateUIForSelectionMode()
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
