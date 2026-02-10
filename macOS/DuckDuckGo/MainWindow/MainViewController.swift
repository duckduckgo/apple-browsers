//
//  MainViewController.swift
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

import AIChat
import BrokenSitePrompt
import Cocoa
import Carbon.HIToolbox
import Combine
import Common
import History
import NetworkProtectionIPC
import NetworkQualityMonitor
import os.log
import PerformanceTest
import PixelKit
import PrivacyConfig
import SwiftUI
import VPN

final class MainViewController: NSViewController {
    private(set) lazy var mainView = MainView(frame: NSRect(x: 0, y: 0, width: 600, height: 660))

    let tabBarViewController: TabBarViewController
    let navigationBarViewController: NavigationBarViewController
    let browserTabViewController: BrowserTabViewController
    let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    let aiChatSidebarPresenter: AIChatSidebarPresenting
    let aiChatSummarizer: AIChatSummarizer
    let aiChatTranslator: AIChatTranslator
    let findInPageViewController: FindInPageViewController
    let fireViewController: FireViewController
    let bookmarksBarViewController: BookmarksBarViewController
    let aiChatOmnibarContainerViewController: AIChatOmnibarContainerViewController
    let aiChatOmnibarTextContainerViewController: AIChatOmnibarTextContainerViewController
    let featureFlagger: FeatureFlagger
    let fireCoordinator: FireCoordinator
    private let bookmarksBarVisibilityManager: BookmarksBarVisibilityManager
    private let defaultBrowserAndDockPromptPresenting: DefaultBrowserAndDockPromptPresenting
    private let vpnUpsellPopoverPresenter: VPNUpsellPopoverPresenter
    private let winBackOfferPromptPresenting: WinBackOfferPromptPresenting
    let tabsPreferences: TabsPreferences
    private let duckPlayer: DuckPlayer

    let tabCollectionViewModel: TabCollectionViewModel
    let bookmarkManager: BookmarkManager
    let historyCoordinator: HistoryCoordinator
    let fireproofDomains: FireproofDomains
    let downloadManager: FileDownloadManagerProtocol
    let isBurner: Bool
    let pinningManager: PinningManager

    private var addressBarBookmarkIconVisibilityCancellable: AnyCancellable?
    private var selectedTabViewModelCancellable: AnyCancellable?
    private var viewEventsCancellables = Set<AnyCancellable>()
    private var tabViewModelCancellables = Set<AnyCancellable>()
    private var bookmarksBarVisibilityChangedCancellable: AnyCancellable?
    private var appearanceChangedCancellable: AnyCancellable?
    private var bannerPromptObserver: Any?
    private var bannerDismissedCancellable: AnyCancellable?

    private var bookmarksBarIsVisible: Bool {
        return bookmarksBarViewController.parent != nil
    }

    private let themeManager: ThemeManaging
    private var theme: ThemeStyleProviding {
        themeManager.theme
    }

    var shouldShowBookmarksBar: Bool {
        return !isInPopUpWindow
        && bookmarksBarVisibilityManager.isBookmarksBarVisible
        && (!(view.window?.isFullScreen ?? false) || NSApp.delegateTyped.appearancePreferences.showTabsAndBookmarksBarOnFullScreen)
    }

    var isInPopUpWindow: Bool {
        tabCollectionViewModel.isPopup
    }

    required init?(coder: NSCoder) {
        fatalError("MainViewController: Bad initializer")
    }

    init(tabCollectionViewModel: TabCollectionViewModel,
         bookmarkManager: BookmarkManager = NSApp.delegateTyped.bookmarkManager,
         bookmarkDragDropManager: BookmarkDragDropManager = NSApp.delegateTyped.bookmarkDragDropManager,
         historyCoordinator: HistoryCoordinator = NSApp.delegateTyped.historyCoordinator,
         recentlyClosedCoordinator: RecentlyClosedCoordinating = NSApp.delegateTyped.recentlyClosedCoordinator,
         contentBlocking: ContentBlockingProtocol = NSApp.delegateTyped.privacyFeatures.contentBlocking,
         fireproofDomains: FireproofDomains = NSApp.delegateTyped.fireproofDomains,
         windowControllersManager: WindowControllersManager = NSApp.delegateTyped.windowControllersManager,
         permissionManager: PermissionManagerProtocol = NSApp.delegateTyped.permissionManager,
         autofillPopoverPresenter: AutofillPopoverPresenter,
         vpnXPCClient: VPNControllerXPCClient = .shared,
         aiChatMenuConfig: AIChatMenuVisibilityConfigurable = NSApp.delegateTyped.aiChatMenuConfiguration,
         aiChatSidebarProvider: AIChatSidebarProviding,
         aiChatTabOpener: AIChatTabOpening = NSApp.delegateTyped.aiChatTabOpener,
         brokenSitePromptLimiter: BrokenSitePromptLimiter = NSApp.delegateTyped.brokenSitePromptLimiter,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         searchPreferences: SearchPreferences = NSApp.delegateTyped.searchPreferences,
         defaultBrowserPreferences: DefaultBrowserPreferences = NSApp.delegateTyped.defaultBrowserPreferences,
         defaultBrowserAndDockPromptPresenting: DefaultBrowserAndDockPromptPresenting = NSApp.delegateTyped.defaultBrowserAndDockPromptService.presenter,
         downloadManager: FileDownloadManagerProtocol = NSApp.delegateTyped.downloadManager,
         downloadListCoordinator: DownloadListCoordinator = NSApp.delegateTyped.downloadListCoordinator,
         downloadsPreferences: DownloadsPreferences = NSApp.delegateTyped.downloadsPreferences,
         tabsPreferences: TabsPreferences = NSApp.delegateTyped.tabsPreferences,
         webTrackingProtectionPreferences: WebTrackingProtectionPreferences = NSApp.delegateTyped.webTrackingProtectionPreferences,
         cookiePopupProtectionPreferences: CookiePopupProtectionPreferences = NSApp.delegateTyped.cookiePopupProtectionPreferences,
         aiChatPreferences: AIChatPreferences = NSApp.delegateTyped.aiChatPreferences,
         aboutPreferences: AboutPreferences = NSApp.delegateTyped.aboutPreferences,
         accessibilityPreferences: AccessibilityPreferences = NSApp.delegateTyped.accessibilityPreferences,
         duckPlayer: DuckPlayer = NSApp.delegateTyped.duckPlayer,
         themeManager: ThemeManager = NSApp.delegateTyped.themeManager,
         fireCoordinator: FireCoordinator = NSApp.delegateTyped.fireCoordinator,
         tabDragAndDropManager: TabDragAndDropManager = NSApp.delegateTyped.tabDragAndDropManager,
         pixelFiring: PixelFiring? = PixelKit.shared,
         visualizeFireAnimationDecider: VisualizeFireSettingsDecider = NSApp.delegateTyped.visualizeFireSettingsDecider,
         vpnUpsellPopoverPresenter: VPNUpsellPopoverPresenter = NSApp.delegateTyped.vpnUpsellPopoverPresenter,
         sessionRestorePromptCoordinator: SessionRestorePromptCoordinating = NSApp.delegateTyped.sessionRestorePromptCoordinator,
         winBackOfferPromptPresenting: WinBackOfferPromptPresenting = NSApp.delegateTyped.winBackOfferPromptPresenter,
         pinningManager: PinningManager = NSApp.delegateTyped.pinningManager,
         memoryUsageMonitor: MemoryUsageMonitor = NSApp.delegateTyped.memoryUsageMonitor
    ) {

        self.aiChatMenuConfig = aiChatMenuConfig
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.historyCoordinator = historyCoordinator
        self.fireproofDomains = fireproofDomains
        self.isBurner = tabCollectionViewModel.isBurner
        self.featureFlagger = featureFlagger
        self.defaultBrowserAndDockPromptPresenting = defaultBrowserAndDockPromptPresenting
        self.downloadManager = downloadManager
        self.themeManager = themeManager
        self.fireCoordinator = fireCoordinator
        self.winBackOfferPromptPresenting = winBackOfferPromptPresenting
        self.tabsPreferences = tabsPreferences
        self.duckPlayer = duckPlayer
        self.pinningManager = pinningManager

        tabBarViewController = TabBarViewController.create(
            tabCollectionViewModel: tabCollectionViewModel,
            bookmarkManager: bookmarkManager,
            fireproofDomains: fireproofDomains,
            activeRemoteMessageModel: NSApp.delegateTyped.activeRemoteMessageModel,
            featureFlagger: featureFlagger,
            tabDragAndDropManager: tabDragAndDropManager,
            autoconsentStatsPopoverCoordinator: NSApp.delegateTyped.autoconsentStatsPopoverCoordinator
        )
        bookmarksBarVisibilityManager = BookmarksBarVisibilityManager(selectedTabPublisher: tabCollectionViewModel.$selectedTabViewModel.eraseToAnyPublisher())

        let networkProtectionPopoverManager: NetPPopoverManager = { @MainActor in
#if DEBUG
            guard case .normal = AppVersion.runType else {
                return NetPPopoverManagerMock()
            }
#endif

            vpnXPCClient.register { error in
                NetworkProtectionKnownFailureStore().lastKnownFailure = KnownFailure(error)
            }

            let vpnUninstaller = VPNUninstaller(pinningManager: pinningManager, ipcClient: vpnXPCClient)

            return NetworkProtectionNavBarPopoverManager(
                ipcClient: vpnXPCClient,
                vpnUninstaller: vpnUninstaller,
                vpnUIPresenting: Application.appDelegate.windowControllersManager,
                freeTrialConversionService: Application.appDelegate.freeTrialConversionService)
        }()
        let networkProtectionStatusReporter: NetworkProtectionStatusReporter = {
            var connectivityIssuesObserver: ConnectivityIssueObserver!
            var controllerErrorMessageObserver: ControllerErrorMesssageObserver!
#if DEBUG
            if ![.normal, .integrationTests].contains(AppVersion.runType) {
                connectivityIssuesObserver = ConnectivityIssueObserverMock()
                controllerErrorMessageObserver = ControllerErrorMesssageObserverMock()
            }
#endif
            connectivityIssuesObserver = connectivityIssuesObserver ?? DisabledConnectivityIssueObserver()
            controllerErrorMessageObserver = controllerErrorMessageObserver ?? ControllerErrorMesssageObserverThroughDistributedNotifications()

            return DefaultNetworkProtectionStatusReporter(
                vpnEnabledObserver: vpnXPCClient.ipcVPNEnabledObserver,
                statusObserver: vpnXPCClient.ipcStatusObserver,
                serverInfoObserver: vpnXPCClient.ipcServerInfoObserver,
                connectionErrorObserver: vpnXPCClient.ipcConnectionErrorObserver,
                connectivityIssuesObserver: connectivityIssuesObserver,
                controllerErrorMessageObserver: controllerErrorMessageObserver,
                dataVolumeObserver: vpnXPCClient.ipcDataVolumeObserver,
                knownFailureObserver: KnownFailureObserverThroughDistributedNotifications()
            )
        }()

        browserTabViewController = BrowserTabViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            bookmarkManager: bookmarkManager,
            defaultBrowserPreferences: defaultBrowserPreferences,
            downloadsPreferences: downloadsPreferences,
            searchPreferences: searchPreferences,
            tabsPreferences: tabsPreferences,
            webTrackingProtectionPreferences: webTrackingProtectionPreferences,
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
            aiChatPreferences: aiChatPreferences,
            aboutPreferences: aboutPreferences,
            accessibilityPreferences: accessibilityPreferences,
            duckPlayer: duckPlayer,
            pinningManager: pinningManager
        )
        aiChatSidebarPresenter = AIChatSidebarPresenter(
            sidebarHost: browserTabViewController,
            sidebarProvider: aiChatSidebarProvider,
            aiChatMenuConfig: aiChatMenuConfig,
            aiChatTabOpener: aiChatTabOpener,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixelFiring
        )
        aiChatSummarizer = AIChatSummarizer(
            aiChatMenuConfig: aiChatMenuConfig,
            aiChatSidebarPresenter: aiChatSidebarPresenter,
            aiChatTabOpener: aiChatTabOpener,
            pixelFiring: pixelFiring
        )

        aiChatTranslator = AIChatTranslator(
            aiChatMenuConfig: aiChatMenuConfig,
            aiChatSidebarPresenter: aiChatSidebarPresenter,
            aiChatTabOpener: aiChatTabOpener,
            pixelFiring: pixelFiring
        )

        navigationBarViewController = NavigationBarViewController.create(tabCollectionViewModel: tabCollectionViewModel,
                                                                         downloadListCoordinator: downloadListCoordinator,
                                                                         bookmarkManager: bookmarkManager,
                                                                         bookmarkDragDropManager: bookmarkDragDropManager,
                                                                         historyCoordinator: historyCoordinator,
                                                                         recentlyClosedCoordinator: recentlyClosedCoordinator,
                                                                         contentBlocking: contentBlocking,
                                                                         fireproofDomains: fireproofDomains,
                                                                         permissionManager: permissionManager,
                                                                         networkProtectionPopoverManager: networkProtectionPopoverManager,
                                                                         networkProtectionStatusReporter: networkProtectionStatusReporter,
                                                                         autofillPopoverPresenter: autofillPopoverPresenter,
                                                                         brokenSitePromptLimiter: brokenSitePromptLimiter,
                                                                         searchPreferences: searchPreferences,
                                                                         webTrackingProtectionPreferences: webTrackingProtectionPreferences,
                                                                         aiChatMenuConfig: aiChatMenuConfig,
                                                                         aiChatSidebarPresenter: aiChatSidebarPresenter,
                                                                         vpnUpsellPopoverPresenter: vpnUpsellPopoverPresenter,
                                                                         sessionRestorePromptCoordinator: sessionRestorePromptCoordinator,
                                                                         defaultBrowserPreferences: defaultBrowserPreferences,
                                                                         downloadsPreferences: downloadsPreferences,
                                                                         tabsPreferences: tabsPreferences,
                                                                         accessibilityPreferences: accessibilityPreferences,
                                                                         pinningManager: pinningManager,
                                                                         memoryUsageMonitor: memoryUsageMonitor)

        findInPageViewController = FindInPageViewController.create()
        fireViewController = FireViewController.create(tabCollectionViewModel: tabCollectionViewModel, fireViewModel: fireCoordinator.fireViewModel, visualizeFireAnimationDecider: visualizeFireAnimationDecider)
        bookmarksBarViewController = BookmarksBarViewController.create(
            tabCollectionViewModel: tabCollectionViewModel,
            bookmarkManager: bookmarkManager,
            dragDropManager: bookmarkDragDropManager,
            pinningManager: pinningManager
        )

        // Create the shared AI Chat omnibar controller
        let suggestionsReader = AIChatSuggestionsReader(
            suggestionsReader: SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: contentBlocking.privacyConfigurationManager),
            historySettings: AIChatHistorySettings(privacyConfig: contentBlocking.privacyConfigurationManager)
        )
        let aiChatOmnibarController = AIChatOmnibarController(
            aiChatTabOpener: aiChatTabOpener,
            tabCollectionViewModel: tabCollectionViewModel,
            suggestionsReader: suggestionsReader
        )

        aiChatOmnibarContainerViewController = AIChatOmnibarContainerViewController(
            themeManager: themeManager,
            omnibarController: aiChatOmnibarController
        )
        aiChatOmnibarTextContainerViewController = AIChatOmnibarTextContainerViewController(
            omnibarController: aiChatOmnibarController,
            themeManager: themeManager
        )
        self.vpnUpsellPopoverPresenter = vpnUpsellPopoverPresenter

        super.init(nibName: nil, bundle: nil)

        aiChatOmnibarController.delegate = self
        browserTabViewController.delegate = self
        findInPageViewController.delegate = self
    }

    override func loadView() {
        view = mainView

        addAndLayoutChild(tabBarViewController, into: mainView.tabBarContainerView)
        addAndLayoutChild(bookmarksBarViewController, into: mainView.bookmarksBarContainerView)
        addAndLayoutChild(navigationBarViewController, into: mainView.navigationBarContainerView)
        addAndLayoutChild(browserTabViewController, into: mainView.webContainerView)
        addAndLayoutChild(findInPageViewController, into: mainView.findInPageContainerView)
        addAndLayoutChild(fireViewController, into: mainView.fireContainerView)
        addAndLayoutChild(aiChatOmnibarContainerViewController, into: mainView.aiChatOmnibarContainerView)
        addAndLayoutChild(aiChatOmnibarTextContainerViewController, into: mainView.aiChatOmnibarTextContainerView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        listenToKeyDownEvents()
        subscribeToMouseTrackingArea()
        subscribeToSelectedTabViewModel()
        subscribeToBookmarkBarVisibility()
        subscribeToAppearanceChanges()
        subscribeToSetAsDefaultAndAddToDockPromptsNotifications()
        mainView.findInPageContainerView.applyDropShadow()

        view.registerForDraggedTypes([.URL, .fileURL])

        mainView.setupAIChatOmnibarTextContainerConstraints(addressBarStack: navigationBarViewController.addressBarStack)
        mainView.setupAIChatOmnibarContainerConstraints(addressBarStack: navigationBarViewController.addressBarStack)

        wireAIChatOmnibarUpdates()
    }

    override func viewWillAppear() {
        subscribeToFirstResponder()

        if isInPopUpWindow {
            tabBarViewController.view.isHidden = true
            mainView.tabBarContainerView.isHidden = true
            mainView.setTabBarShown(false, animated: false)
            resizeNavigationBar(isHomePage: false, animated: false)

            updateBookmarksBarViewVisibility(visible: false)
        } else {
            mainView.navigationBarContainerView.wantsLayer = true
            mainView.navigationBarContainerView.layer?.masksToBounds = false

            if tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab {
                resizeNavigationBar(isHomePage: true, animated: lastTabContent != .newtab)
            } else {
                resizeNavigationBar(isHomePage: false, animated: false)
            }
        }

        updateDividerColor(isShowingHomePage: tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab)
    }

    override func viewDidAppear() {
        initPreloader()

        mainView.setMouseAboveWebViewTrackingAreaEnabled(true)
        registerForBookmarkBarPromptNotifications()

        adjustFirstResponder(force: true)
    }

    var bookmarkBarPromptObserver: Any?
    func registerForBookmarkBarPromptNotifications() {
        guard !bookmarksBarViewController.bookmarksBarPromptShown else { return }
        bookmarkBarPromptObserver = NotificationCenter.default.addObserver(
            forName: .bookmarkPromptShouldShow,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.showBookmarkPromptIfNeeded()
            }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        mainView.setMouseAboveWebViewTrackingAreaEnabled(false)
        if let bookmarkBarPromptObserver {
            NotificationCenter.default.removeObserver(bookmarkBarPromptObserver)
        }
    }

    override func viewDidLayout() {
        mainView.findInPageContainerView.applyDropShadow()
    }

    /// Called when this window becomes the key window (gains focus).
    func windowDidBecomeKey() {
        updateBackMenuItem()
        updateForwardMenuItem()
        updateReloadMenuItem()
        updateStopMenuItem()
        browserTabViewController.windowDidBecomeKey()
        if !isInPopUpWindow {
            // Evaluate and potentially show default browser/dock prompt
            // See showSetAsDefaultAndAddToDockIfNeeded() for full flow documentation
            showSetAsDefaultAndAddToDockIfNeeded()
        }
        showWinBackOfferIfNeeded()
    }

    func windowDidResignKey() {
        browserTabViewController.windowDidResignKey()
        tabBarViewController.hideTabPreview()
    }

    func windowDidEndLiveResize() {
        tabCollectionViewModel.newTabPageTabPreloader?.reloadTab()
    }

    func showBookmarkPromptIfNeeded() {
        guard !isInPopUpWindow,
              !bookmarksBarViewController.bookmarksBarPromptShown,
              OnboardingActionsManager.isOnboardingFinished else { return }
        if bookmarksBarIsVisible {
            // Don't show this to users who obviously know about the bookmarks bar already
            bookmarksBarViewController.bookmarksBarPromptShown = true
            return
        }

        updateBookmarksBarViewVisibility(visible: true)
        // This won't work until the bookmarks bar is actually visible which it isn't until the next ui cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + NSAnimationContext.current.duration) {
            self.bookmarksBarViewController.showBookmarksBarPrompt()
        }
    }

    override func encodeRestorableState(with coder: NSCoder) {
        fatalError("Default AppKit State Restoration should not be used")
    }

    func windowWillClose() {
        viewEventsCancellables.removeAll()
        aiChatOmnibarContainerViewController.cleanup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)

#if DEBUG

        // Check that TabCollectionViewModel deallocates
        tabCollectionViewModel.ensureObjectDeallocated(after: 1.0, do: .interrupt)

        if isViewLoaded {
            view.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        }
        tabBarViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        navigationBarViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        browserTabViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        findInPageViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        fireViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        bookmarksBarViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        aiChatOmnibarContainerViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        aiChatOmnibarTextContainerViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    func windowWillMiniaturize() {
        tabBarViewController.hideTabPreview()
    }

    func windowWillEnterFullScreen() {
        tabBarViewController.hideTabPreview()
    }

    func disableTabPreviews() {
        tabBarViewController.tabPreviewsEnabled = false
    }

    func enableTabPreviews() {
        tabBarViewController.tabPreviewsEnabled = true
    }

    func toggleBookmarksBarVisibility() {
        updateBookmarksBarViewVisibility(visible: !isInPopUpWindow && !mainView.isBookmarksBarShown)
    }

    func updateAIChatOmnibarContainerVisibility(visible: Bool, shouldKeepSelection: Bool = false) {
        if visible {
            let desiredHeight = aiChatOmnibarTextContainerViewController.calculateDesiredPanelHeight()
            let suggestionsHeight = aiChatOmnibarContainerViewController.suggestionsHeight
            let totalHeight = desiredHeight + suggestionsHeight
            mainView.updateAIChatOmnibarContainerHeight(totalHeight, animated: false)
            // Allow clicks to pass through text container to reach suggestions and tool buttons
            let passthroughHeight = aiChatOmnibarContainerViewController.totalPassthroughHeight
            mainView.updateAIChatOmnibarTextContainerPassthrough(passthroughHeight)
            aiChatOmnibarTextContainerViewController.setPassthroughBottomHeight(passthroughHeight)
        }

        mainView.isAIChatOmnibarContainerShown = visible

        navigationBarViewController.addressBarViewController?.setAIChatOmnibarVisible(visible, shouldKeepSelection: shouldKeepSelection)

        if visible {
            aiChatOmnibarContainerViewController.startEventMonitoring()
            aiChatOmnibarTextContainerViewController.startEventMonitoring()
            aiChatOmnibarTextContainerViewController.focusTextView()

            // Suppress mouse hover until mouse actually moves
            aiChatOmnibarContainerViewController.omnibarController.suggestionsViewModel.suppressMouseHoverUntilMouseMoves()

            // Trigger suggestions fetch
            aiChatOmnibarContainerViewController.omnibarController.onOmnibarActivated()

            let maxHeight = mainView.calculateMaxAIChatOmnibarHeight()
            aiChatOmnibarTextContainerViewController.updateScrollingBehavior(maxHeight: maxHeight)
        } else {
            aiChatOmnibarContainerViewController.cleanup()
            aiChatOmnibarTextContainerViewController.stopEventMonitoring()

            if !shouldKeepSelection {
                aiChatOmnibarContainerViewController.omnibarController.suggestionsViewModel.clearSelection()
            }
        }
    }

    private func wireToggleReferenceToAIChatTextContainer() {
        /// This enables TAB key navigation from AI Chat mode to the toggle
        if let searchModeToggleControl = navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.searchModeToggleControl {
            aiChatOmnibarTextContainerViewController.customToggleControl = searchModeToggleControl
        }

        /// This enables TAB key navigation from toggle back to AI Chat text view
        navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.onToggleTabPressedInAIChatMode = { [weak self] in
            self?.aiChatOmnibarTextContainerViewController.focusTextViewWithCursorAtEnd()
        }
    }

    private func wireAIChatOmnibarHeightUpdates() {
        aiChatOmnibarTextContainerViewController.heightDidChange = { [weak self] desiredHeight in
            guard let self = self else { return }

            let suggestionsHeight = self.aiChatOmnibarContainerViewController.suggestionsHeight
            let totalHeight = desiredHeight + suggestionsHeight

            self.mainView.updateAIChatOmnibarContainerHeight(totalHeight, animated: true)

            let maxHeight = self.mainView.calculateMaxAIChatOmnibarHeight()
            self.aiChatOmnibarTextContainerViewController.updateScrollingBehavior(maxHeight: maxHeight)
        }

        // Wire up suggestions height changes
        aiChatOmnibarContainerViewController.onSuggestionsHeightChanged = { [weak self] suggestionsHeight in
            guard let self else { return }

            let textHeight = self.aiChatOmnibarTextContainerViewController.calculateDesiredPanelHeight()
            let totalHeight = textHeight + suggestionsHeight

            self.mainView.updateAIChatOmnibarContainerHeight(totalHeight, animated: false)

            // Allow clicks to pass through text container to reach suggestions and tool buttons
            let passthroughHeight = self.aiChatOmnibarContainerViewController.totalPassthroughHeight
            self.mainView.updateAIChatOmnibarTextContainerPassthrough(passthroughHeight)
            self.aiChatOmnibarTextContainerViewController.setPassthroughBottomHeight(passthroughHeight)

            let maxHeight = self.mainView.calculateMaxAIChatOmnibarHeight()
            self.aiChatOmnibarTextContainerViewController.updateScrollingBehavior(maxHeight: maxHeight)
        }

        // Wire up passthrough height updates when tools visibility changes
        aiChatOmnibarContainerViewController.onPassthroughHeightNeedsUpdate = { [weak self] in
            guard let self, self.mainView.isAIChatOmnibarContainerShown else { return }
            let passthroughHeight = self.aiChatOmnibarContainerViewController.totalPassthroughHeight
            self.mainView.updateAIChatOmnibarTextContainerPassthrough(passthroughHeight)
            self.aiChatOmnibarTextContainerViewController.setPassthroughBottomHeight(passthroughHeight)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: view.window
        )
    }

    private func wireAIChatOmnibarUpdates() {
        wireToggleReferenceToAIChatTextContainer()
        wireAIChatOmnibarHeightUpdates()
        wireAIChatOmnibarHitTesting()
    }

    @objc private func windowDidResize() {
        guard mainView.isAIChatOmnibarContainerShown else { return }

        let textHeight = aiChatOmnibarTextContainerViewController.calculateDesiredPanelHeight()
        let suggestionsHeight = aiChatOmnibarContainerViewController.suggestionsHeight
        let totalHeight = textHeight + suggestionsHeight

        mainView.updateAIChatOmnibarContainerHeight(totalHeight, animated: false)

        let maxHeight = mainView.calculateMaxAIChatOmnibarHeight()
        aiChatOmnibarTextContainerViewController.updateScrollingBehavior(maxHeight: maxHeight)
    }

    private func wireAIChatOmnibarHitTesting() {
        navigationBarViewController.addressBarViewController?.isPointInAIChatOmnibar = { [weak self] locationInWindow in
            guard let self = self else { return false }
            guard self.mainView.isAIChatOmnibarContainerShown else { return false }

            let containerFrame = self.mainView.aiChatOmnibarContainerView.frame
            let pointInMainView = self.mainView.convert(locationInWindow, from: nil)
            if containerFrame.contains(pointInMainView) {
                return true
            }

            let textContainerFrame = self.mainView.aiChatOmnibarTextContainerView.frame
            if textContainerFrame.contains(pointInMainView) {
                return true
            }

            return false
        }
    }

    // Can be updated via keyboard shortcut so needs to be internal visibility
    func updateBookmarksBarViewVisibility(visible showBookmarksBar: Bool) {
        if showBookmarksBar {
            if bookmarksBarViewController.parent == nil {
                addChild(bookmarksBarViewController)

                bookmarksBarViewController.view.frame = mainView.bookmarksBarContainerView.bounds
                mainView.bookmarksBarContainerView.addSubview(bookmarksBarViewController.view)
            }
        } else {
            bookmarksBarViewController.removeFromParent()
            bookmarksBarViewController.view.removeFromSuperview()
        }

        mainView.isBookmarksBarShown = showBookmarksBar
        mainView.layoutSubtreeIfNeeded()
        mainView.updateTrackingAreas()

        updateDividerColor(isShowingHomePage: tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab)
    }

    private func initPreloader() {
        guard tabCollectionViewModel.newTabPageTabPreloader == nil else {
            return
        }

        if featureFlagger.isFeatureOn(.newTabPagePerTab) {
            let preloader = NewTabPageTabPreloader(viewSizeProvider: { [weak self] in
                self?.browserTabViewController.view.bounds.size
            })
            tabCollectionViewModel.newTabPageTabPreloader = preloader
        }
    }

    private func updateDividerColor(isShowingHomePage isHomePage: Bool) {
        NSAppearance.withAppAppearance {
            if theme.addToolbarShadow {
                if mainView.isBannerViewShown {
                    mainView.divider.backgroundColor = .bannerViewDivider
                } else {
                    mainView.divider.backgroundColor = theme.palette.surfaceDecorationPrimary
                }
            } else {
                let backgroundColor: NSColor = {
                    if mainView.isBannerViewShown {
                        return bookmarksBarIsVisible ? .bookmarkBarBackground : .addressBarSolidSeparator
                    } else {
                        return (bookmarksBarIsVisible || isHomePage) ? .bookmarkBarBackground : .addressBarSolidSeparator
                    }
                }()

                mainView.divider.backgroundColor = backgroundColor
            }
        }
    }

    private func subscribeToMouseTrackingArea() {
        addressBarBookmarkIconVisibilityCancellable = mainView.$isMouseAboveWebView
            .sink { [weak self] isMouseAboveWebView in
                self?.navigationBarViewController.addressBarViewController?
                    .addressBarButtonsViewController?.isMouseOverNavigationBar = isMouseAboveWebView
            }
    }

    private func subscribeToSelectedTabViewModel() {
        selectedTabViewModelCancellable = tabCollectionViewModel.$selectedTabViewModel.sink { [weak self] tabViewModel in
            guard let self, let tabViewModel else { return }

            tabViewModelCancellables.removeAll(keepingCapacity: true)
            subscribeToCanGoBackForward(of: tabViewModel)
            subscribeToFindInPage(of: tabViewModel)
            subscribeToTitleChange(of: tabViewModel)
            subscribeToTabContent(of: tabViewModel)
        }
    }

    private func subscribeToTitleChange(of selectedTabViewModel: TabViewModel?) {
        guard let selectedTabViewModel else { return }

        let updateWindowTitle = { [weak self] (title: String) in
            guard let self, let window = self.view.window else { return }
            guard !isBurner else {
                // Fire Window: don‘t display active Tab title as the Window title
                window.title = UserText.burnerWindowHeader
                return
            }
            let truncatedTitle = title.truncated(length: MainMenu.Constants.maxTitleLength)

            window.title = truncatedTitle
        }

        // Update once the view is added to a window.
        view.observe(\.window) { [weak selectedTabViewModel] view, _ in
            guard view.window != nil else { return }
            updateWindowTitle(selectedTabViewModel?.title ?? "")
        }.store(in: &tabViewModelCancellables)

        selectedTabViewModel.$title
            .receive(on: DispatchQueue.main)
            .sink { title in
                updateWindowTitle(title)
            }
            .store(in: &tabViewModelCancellables)
    }

    private func subscribeToBookmarkBarVisibility() {
        bookmarksBarVisibilityChangedCancellable = bookmarksBarVisibilityManager
            .$isBookmarksBarVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateBookmarksBarViewVisibility(visible: self!.shouldShowBookmarksBar)
            }
    }

    private func subscribeToAppearanceChanges() {
        appearanceChangedCancellable = NSApp.publisher(for: \.effectiveAppearance)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tabCollectionViewModel.newTabPageTabPreloader?.reloadTab(force: true)
            }
    }

    private func resizeNavigationBar(isHomePage homePage: Bool, animated: Bool) {
        updateDividerColor(isShowingHomePage: homePage)
        navigationBarViewController.resizeAddressBar(for: homePage ? .homePage : (isInPopUpWindow ? .popUpWindow : .default), animated: animated)
    }

    private var lastTabContent = Tab.TabContent.none
    private func subscribeToTabContent(of selectedTabViewModel: TabViewModel?) {
        selectedTabViewModel?.tab.$content
            .sink { [weak self, weak selectedTabViewModel] content in
                guard let self, let selectedTabViewModel else { return }
                defer { lastTabContent = content }

                if content == .newtab {
                    resizeNavigationBar(isHomePage: true, animated: lastTabContent != .newtab)
                } else {
                    resizeNavigationBar(isHomePage: false, animated: false)
                }
                adjustFirstResponder(selectedTabViewModel: selectedTabViewModel, tabContent: content)
            }
            .store(in: &self.tabViewModelCancellables)
    }

    private func subscribeToFirstResponder() {
        guard let window = view.window else {
            assert([.unitTests, .integrationTests].contains(AppVersion.runType),
                   "MainViewController.subscribeToFirstResponder: view.window is nil")
            return
        }

        NotificationCenter.default
            .publisher(for: MainWindow.firstResponderDidChangeNotification, object: window)
            .sink { [weak self] in
                self?.firstResponderDidChange($0)
            }
            .store(in: &viewEventsCancellables)
    }

    private func firstResponderDidChange(_ notification: Notification) {
        // when window first responder is reset (to the window): activate Tab Content View
        if view.window?.firstResponder === view.window {
            browserTabViewController.adjustFirstResponder()
        }
    }

    private func subscribeToFindInPage(of selectedTabViewModel: TabViewModel?) {
        selectedTabViewModel?.findInPage?
            .$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFindInPage()
            }
            .store(in: &self.tabViewModelCancellables)
    }

    private func subscribeToCanGoBackForward(of selectedTabViewModel: TabViewModel) {
        selectedTabViewModel.$canGoBack.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateBackMenuItem()
        }.store(in: &self.tabViewModelCancellables)
        selectedTabViewModel.$canGoForward.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateForwardMenuItem()
        }.store(in: &self.tabViewModelCancellables)
        selectedTabViewModel.$canReload.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateReloadMenuItem()
        }.store(in: &self.tabViewModelCancellables)
        selectedTabViewModel.$isLoading.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateStopMenuItem()
        }.store(in: &self.tabViewModelCancellables)
    }

    private func updateFindInPage() {
        guard let model = tabCollectionViewModel.selectedTabViewModel?.findInPage else {
            findInPageViewController.makeMeFirstResponder()
            Logger.general.error("MainViewController: Failed to get find in page model")
            return
        }

        mainView.findInPageContainerView.isHidden = !model.isVisible
        findInPageViewController.model = model
        if model.isVisible {
            findInPageViewController.makeMeFirstResponder()
        }
    }

    private func updateBackMenuItem() {
        guard self.view.window?.isMainWindow == true else { return }
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.general.error("MainViewController: No tab view model selected")
            return
        }
        NSApp.mainMenuTyped.backMenuItem.isEnabled = selectedTabViewModel.canGoBack
    }

    private func updateForwardMenuItem() {
        guard self.view.window?.isMainWindow == true else { return }
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.general.error("MainViewController: No tab view model selected")
            return
        }
        NSApp.mainMenuTyped.forwardMenuItem.isEnabled = selectedTabViewModel.canGoForward
    }

    private func updateReloadMenuItem() {
        guard self.view.window?.isMainWindow == true else { return }
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.general.error("MainViewController: No tab view model selected")
            return
        }
        NSApp.mainMenuTyped.reloadMenuItem.isEnabled = selectedTabViewModel.canReload
    }

    private func updateStopMenuItem() {
        guard self.view.window?.isMainWindow == true else { return }
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.general.error("MainViewController: No tab view model selected")
            return
        }
        NSApp.mainMenuTyped.stopMenuItem.isEnabled = selectedTabViewModel.isLoading
    }

    // MARK: - Set As Default and Add To Dock Prompts configuration

    private func subscribeToSetAsDefaultAndAddToDockPromptsNotifications() {
        bannerDismissedCancellable = defaultBrowserAndDockPromptPresenting.bannerDismissedPublisher
            .sink { [weak self] in
                self?.hideBanner()
            }
    }

    /// **ENTRY POINT for Default Browser & Dock Prompts**
    ///
    /// This is called when a main window becomes key (see `windowDidBecomeKey()`).
    /// It triggers the prompt system to evaluate if any prompt should be shown.
    ///
    /// **Flow:**
    /// 1. Calls `DefaultBrowserAndDockPromptPresenter.tryToShowPrompt()`
    /// 2. Presenter asks `DefaultBrowserAndDockPromptCoordinator.getPromptType()` to determine eligibility
    /// 3. Coordinator checks: onboarding status, default browser/dock status, and timing rules
    /// 4. If eligible, shows one of three prompt types:
    ///    - **Popover**: Small popup anchored to address bar (first prompt, shown once)
    ///    - **Banner**: Persistent bar at top of window (shown after popover, can repeat)
    ///    - **Inactive User Modal**: Sheet for users who haven't used the app in 7+ days
    ///
    /// **See also:**
    /// - `DefaultBrowserAndDockPromptPresenter.tryToShowPrompt()` - orchestrates prompt display
    /// - `DefaultBrowserAndDockPromptCoordinator.getPromptType()` - determines which prompt to show
    /// - `DefaultBrowserAndDockPromptTypeDecider` - implements timing logic
    @objc private func showSetAsDefaultAndAddToDockIfNeeded() {
        guard !isInPopUpWindow else { return }

        defaultBrowserAndDockPromptPresenting.tryToShowPrompt(
            popoverAnchorProvider: getSourceViewToShowSetAsDefaultAndAddToDockPopover,
            bannerViewHandler: showMessageBanner,
            inactiveUserModalWindowProvider: getSourceWindowToShowInactiveUserModal
        )
    }

    private func getSourceViewToShowSetAsDefaultAndAddToDockPopover() -> NSView? {
        guard isViewLoaded && view.window?.isKeyWindow == true else {
            return nil
        }

        if bookmarksBarVisibilityManager.isBookmarksBarVisible {
            return bookmarksBarViewController.view
        } else {
            return navigationBarViewController.addressBarViewController?.view
        }
    }

    private func getSourceWindowToShowInactiveUserModal() -> NSWindow? {
        guard isViewLoaded && view.window?.isKeyWindow == true else {
            return nil
        }
        return view.window
    }

    /// **BANNER DISPLAY HANDLER**
    ///
    /// Called by `DefaultBrowserAndDockPromptPresenter` when a banner prompt should be shown.
    /// The banner is a persistent bar displayed at the top of the window with action buttons.
    ///
    /// **Banner Lifecycle:**
    /// - Created in `DefaultBrowserAndDockPromptPresenter.getBanner()`
    /// - Displayed here in the main view's banner container
    /// - Shown in ALL windows until user takes action (confirm, dismiss, or close)
    /// - Dismissed via `hideBanner()` when user interacts or banner is closed
    ///
    /// **See also:**
    /// - `DefaultBrowserAndDockPromptPresenter.getBanner()` - creates the banner view controller
    /// - `hideBanner()` - removes the banner from view
    private func showMessageBanner(banner: BannerMessageViewController) {
        if mainView.isBannerViewShown { return } // If view is being shown already we do not want to show it.

        addAndLayoutChild(banner, into: mainView.bannerContainerView)
        mainView.isBannerViewShown = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateDividerColor(isShowingHomePage: self?.tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab)
        }
    }

    private func hideBanner() {
        mainView.bannerContainerView.subviews.forEach { $0.removeFromSuperview() }
        mainView.isBannerViewShown = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.updateDividerColor(isShowingHomePage: self?.tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab)
        }
    }

    // MARK: - Win-Back Offer

    private func showWinBackOfferIfNeeded() {
        winBackOfferPromptPresenting.tryToShowPrompt(in: view.window)
    }

    // MARK: - First responder

    func adjustFirstResponder(selectedTabViewModel: TabViewModel? = nil, tabContent: Tab.TabContent? = nil, force: Bool = false) {
        guard let selectedTabViewModel = selectedTabViewModel ?? tabCollectionViewModel.selectedTabViewModel else {
            return
        }
        let tabContent = tabContent ?? selectedTabViewModel.tab.content

        /// Close AI Chat omnibar if visible before adjusting first responder
        /// https://app.asana.com/1/137249556945/project/1204167627774280/task/1212252449969913?focus=true
        if mainView.isAIChatOmnibarContainerShown && featureFlagger.isFeatureOn(.aiChatOmnibarToggle) {
            updateAIChatOmnibarContainerVisibility(visible: false, shouldKeepSelection: false)
            aiChatOmnibarContainerViewController.cleanup()
        }

        if case .newtab = tabContent {
            navigationBarViewController.addressBarViewController?.addressBarTextField.makeMeFirstResponder()
        } else {
            // ignore published tab switch: BrowserTabViewController
            // adjusts first responder itself
            guard selectedTabViewModel === tabCollectionViewModel.selectedTabViewModel || force else { return }
            browserTabViewController.adjustFirstResponder(force: force, tabContent: tabContent)
        }
    }

}
extension MainViewController: NSDraggingDestination {

    func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(draggingInfo)
    }

    func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return browserTabViewController.draggingUpdated(draggingInfo)
    }

    func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        // open new tab if url dropped outside of the address bar
        guard let url = draggingInfo.draggingPasteboard.url else {
            return false
        }
        browserTabViewController.openNewTab(with: .url(url, source: .appOpenUrl))
        return true
    }

}

// MARK: - Mouse & Keyboard Events

// This needs to be handled here or else there will be a "beep" even if handled in a different view controller. This now
//  matches Safari behaviour.
extension MainViewController {

    func listenToKeyDownEvents() {
        NSEvent.addLocalCancellableMonitor(forEventsMatching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.customKeyDown(with: event) ? nil : event
        }.store(in: &viewEventsCancellables)
        NSEvent.addLocalCancellableMonitor(forEventsMatching: .otherMouseUp) { [weak self] event in
            guard let self else { return event }
            return self.otherMouseUp(with: event)
        }.store(in: &viewEventsCancellables)
    }

    func customKeyDown(with event: NSEvent) -> Bool {
        guard let locWindow = self.view.window,
              NSApplication.shared.keyWindow === locWindow else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isWebViewFocused = view.window?.firstResponder is WebView

        if handleReturnKey(event: event, flags: flags) {
            return true
        }

        if handleEscapeKey(event: event) {
            return true
        }

        if handleTabSwitching(event: event, flags: flags, key: key, isWebViewFocused: isWebViewFocused) {
            return true
        }

        if handleControlTab(event: event, flags: flags) {
            return true
        }

        if handleBrowserActions(key: key, flags: flags, isWebViewFocused: isWebViewFocused, event: event) {
            return true
        }

        return false
    }

    private func handleReturnKey(event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == kVK_Return,
              navigationBarViewController.addressBarViewController?.addressBarTextField.isFirstResponder == true else {
            return false
        }

        if flags.contains(.option) || flags.contains(.shift),
           featureFlagger.isFeatureOn(.aiChatOmnibarToggle),
           let buttonsViewController = navigationBarViewController.addressBarViewController?.addressBarButtonsViewController {
            let isSwitchingToAIChatMode = buttonsViewController.searchModeToggleControl?.selectedSegment == 0
            buttonsViewController.toggleSearchMode()
            if isSwitchingToAIChatMode {
                let currentText = navigationBarViewController.addressBarViewController?.addressBarTextField.stringValueWithoutSuffix ?? ""
                self.aiChatOmnibarTextContainerViewController.insertNewlineIfHasContent(addressBarText: currentText)
            }
            return true
        } else if flags.contains(.control),
                  featureFlagger.isFeatureOn(.aiChatOmnibarToggle) {
            navigationBarViewController.addressBarViewController?.addressBarTextField.openAIChatWithPrompt()
            return true
        } else if flags.contains(.shift) && aiChatMenuConfig.shouldDisplayAddressBarShortcutWhenTyping {
            navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.aiChatButtonAction(self)
        } else {
            navigationBarViewController.addressBarViewController?.addressBarTextField.addressBarEnterPressed()
        }
        return true
    }

    private func handleEscapeKey(event: NSEvent) -> Bool {
        guard event.keyCode == kVK_Escape else { return false }

        var isHandled = false
        if !mainView.findInPageContainerView.isHidden {
            findInPageViewController.findInPageDone(self)
            isHandled = true
        }
        if let addressBarVC = navigationBarViewController.addressBarViewController {
            isHandled = isHandled || addressBarVC.escapeKeyDown()
        }
        return isHandled
    }

    private func handleTabSwitching(event: NSEvent, flags: NSEvent.ModifierFlags, key: String, isWebViewFocused: Bool) -> Bool {
        guard [.command, [.command, .numericPad]].contains(flags), "123456789".contains(key) else {
            return false
        }

        if isWebViewFocused {
            NSApp.menu?.performKeyEquivalent(with: event)
            return true
        }
        return false
    }

    private func handleControlTab(event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == kVK_Tab, [.control, [.control, .shift]].contains(flags) else {
            return false
        }

        NSApp.menu?.performKeyEquivalent(with: event)
        return true
    }

    private func handleBrowserActions(key: String, flags: NSEvent.ModifierFlags, isWebViewFocused: Bool, event: NSEvent) -> Bool {
        guard isWebViewFocused else { return false }

        switch (key, flags, flags.contains(.command)) {
        case ("n", [.command], _),
            ("t", [.command], _), ("t", [.command, .shift], _),
            ("w", _, true),
            ("q", [.command], _),
            ("r", [.command], _):
            NSApp.menu?.performKeyEquivalent(with: event)
            return true
        default:
            return false
        }
    }

    func otherMouseUp(with event: NSEvent) -> NSEvent? {
        guard event.window === self.view.window,
              mainView.webContainerView.isMouseLocationInsideBounds(event.locationInWindow),
              let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel
        else { return event }

        switch event.button {
        case .back:
            guard selectedTabViewModel.canGoBack else { return nil }
            selectedTabViewModel.tab.goBack()
            return nil
        case .forward:
            guard selectedTabViewModel.canGoForward else { return nil }
            selectedTabViewModel.tab.goForward()
            return nil
        default:
            return event
        }
    }

    // MARK: - Network Quality Testing

    @objc func testNetworkQuality() {
        let windowController = NetworkQualitySwiftUIWindowController()
        windowController.showWindow(nil)
    }

}

// MARK: - Performance Testing

extension MainViewController {

    @objc func testCurrentSitePerformance() {
        // Get the current tab's web view
        guard let currentTab = tabCollectionViewModel.selectedTabViewModel?.tab else {
            let alert = NSAlert()
            alert.messageText = "No Active Page"
            alert.informativeText = "Please navigate to a webpage first to test its performance."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Use the package to handle everything
        let windowController = PerformanceTestWindowController(
            webView: currentTab.webView,
            createNewTab: { @MainActor [weak self] in
                guard let self = self else {
                    Logger.general.error("MainViewController deallocated during performance test - cannot create new tab")
                    return nil
                }

                // Create a new tab with duckduckgo.com for JS warmup
                guard let warmupURL = URL(string: "https://duckduckgo.com") else {
                    Logger.general.error("Failed to create warmup URL")
                    return nil
                }
                self.tabCollectionViewModel.appendNewTab(with: .url(warmupURL, source: .ui), selected: true)

                // Return the newly selected tab's webView
                guard let newWebView = self.tabCollectionViewModel.selectedTabViewModel?.tab.webView else {
                    Logger.general.error("Failed to get webView from newly created tab")
                    return nil
                }

                return newWebView
            },
            closeTab: { @MainActor [weak self] in
                guard let self = self else { return }

                // Close the currently selected tab (the one we just tested in)
                guard let currentIndex = self.tabCollectionViewModel.selectionIndex else {
                    Logger.general.debug("closeTab: No tab selected")
                    return
                }
                Logger.general.debug("closeTab: Closing currently selected tab")
                self.tabCollectionViewModel.remove(at: currentIndex)
                Logger.general.debug("closeTab: Tab closed")
            }
        )
        windowController.showWindow(nil)
    }

}

// MARK: - BrowserTabViewControllerDelegate

extension MainViewController: BrowserTabViewControllerDelegate {

    func highlightFireButton() {
        tabBarViewController.startFireButtonPulseAnimation()
    }

    func dismissViewHighlight() {
        tabBarViewController.stopFireButtonPulseAnimation()
        navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.stopHighlightingPrivacyShield()
    }

    func highlightPrivacyShield() {
        navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.highlightPrivacyShield()
    }

    /// Closes the window if it has no more regular tabs and its pinned tabs are available in other windows
    func closeWindowIfNeeded() -> Bool {
        guard let window = view.window,
              tabCollectionViewModel.tabCollection.tabs.isEmpty else { return false }

        let noPinnedTabs = tabCollectionViewModel.isBurner || tabCollectionViewModel.pinnedTabsManager?.tabCollection.tabs.isEmpty != false

        var isSharedPinnedTabsMode: Bool {
            tabsPreferences.pinnedTabsMode == .shared
        }

        lazy var areOtherWindowsWithPinnedTabsAvailable: Bool = {
            Application.appDelegate.windowControllersManager.mainWindowControllers
                .contains { mainWindowController -> Bool in
                    mainWindowController.mainViewController !== self
                    && mainWindowController.mainViewController.isBurner == false
                    && !mainWindowController.mainViewController.isInPopUpWindow
                }
        }()

        if noPinnedTabs || (isSharedPinnedTabsMode && areOtherWindowsWithPinnedTabsAvailable) {
            window.close()
            return true
        }
        return false
    }

}

// MARK: - AIChatOmnibarControllerDelegate
extension MainViewController: AIChatOmnibarControllerDelegate {
    func aiChatOmnibarControllerDidSubmit(_ controller: AIChatOmnibarController) {
        updateAIChatOmnibarContainerVisibility(visible: false, shouldKeepSelection: false)
    }

    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didRequestNavigationToURL url: URL) {
        updateAIChatOmnibarContainerVisibility(visible: false, shouldKeepSelection: false)
        browserTabViewController.loadURLInCurrentTab(url)
    }

    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didSelectSuggestion suggestion: AIChatSuggestion) {
        updateAIChatOmnibarContainerVisibility(visible: false, shouldKeepSelection: false)
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .existingChat(chatId: suggestion.chatId), behavior: .currentTab)
    }
}

#if DEBUG
@available(macOS 14.0, *)
#Preview(traits: .fixedLayout(width: 700, height: 660)) {

    let bkman = LocalBookmarkManager(
        bookmarkStore: BookmarkStoreMock(
            bookmarks: [
                BookmarkFolder(id: "1", title: "Folder", children: [
                    Bookmark(id: "2", url: URL.duckDuckGo.absoluteString, title: "DuckDuckGo", isFavorite: true)
                ]),
                Bookmark(id: "3", url: URL.duckDuckGo.absoluteString, title: "DuckDuckGo", isFavorite: true, parentFolderUUID: "1")
            ]
        ),
        appearancePreferences: .mock
    )
    bkman.loadBookmarks()

    let vc = MainViewController(tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection()), bookmarkManager: bkman, autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: Application.appDelegate.pinningManager), aiChatSidebarProvider: AIChatSidebarProvider(featureFlagger: MockFeatureFlagger()))
    var c: AnyCancellable!
    c = vc.publisher(for: \.view.window).sink { window in
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        withExtendedLifetime(c) {}
    }

    return vc
}
#endif
