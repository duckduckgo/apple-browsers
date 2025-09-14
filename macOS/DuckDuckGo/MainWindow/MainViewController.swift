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

import BrokenSitePrompt
import BrowserServicesKit
import Cocoa
import Carbon.HIToolbox
import Combine
import Common
import History
import NetworkProtectionIPC
import os.log
import PixelKit
import VPN

final class MainViewController: NSViewController {
    private(set) lazy var mainView = MainView(frame: NSRect(x: 0, y: 0, width: 600, height: 660))

    static let watchdog = Watchdog()

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
    let featureFlagger: FeatureFlagger
    let fireCoordinator: FireCoordinator
    private let bookmarksBarVisibilityManager: BookmarksBarVisibilityManager
    private let defaultBrowserAndDockPromptPresenting: DefaultBrowserAndDockPromptPresenting
    private let visualStyle: VisualStyleProviding
    private let vpnUpsellPopoverPresenter: VPNUpsellPopoverPresenter

    let tabCollectionViewModel: TabCollectionViewModel
    let bookmarkManager: BookmarkManager
    let historyCoordinator: HistoryCoordinator
    let fireproofDomains: FireproofDomains
    let isBurner: Bool

    private var addressBarBookmarkIconVisibilityCancellable: AnyCancellable?
    private var selectedTabViewModelCancellable: AnyCancellable?
    private var selectedTabViewModelForHistoryViewOnboardingCancellable: AnyCancellable?
    private var viewEventsCancellables = Set<AnyCancellable>()
    private var tabViewModelCancellables = Set<AnyCancellable>()
    private var bookmarksBarVisibilityChangedCancellable: AnyCancellable?
    private var appearanceChangedCancellable: AnyCancellable?
    private var bannerPromptObserver: Any?
    private var bannerDismissedCancellable: AnyCancellable?

    private var bookmarksBarIsVisible: Bool {
        return bookmarksBarViewController.parent != nil
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
         defaultBrowserAndDockPromptPresenting: DefaultBrowserAndDockPromptPresenting = NSApp.delegateTyped.defaultBrowserAndDockPromptPresenter,
         visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle,
         fireCoordinator: FireCoordinator = NSApp.delegateTyped.fireCoordinator,
         pixelFiring: PixelFiring? = PixelKit.shared,
         visualizeFireAnimationDecider: VisualizeFireSettingsDecider = NSApp.delegateTyped.visualizeFireSettingsDecider,
         vpnUpsellPopoverPresenter: VPNUpsellPopoverPresenter = NSApp.delegateTyped.vpnUpsellPopoverPresenter,
         sessionRestorePromptCoordinator: SessionRestorePromptCoordinating = NSApp.delegateTyped.sessionRestorePromptCoordinator
    ) {

        self.aiChatMenuConfig = aiChatMenuConfig
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.historyCoordinator = historyCoordinator
        self.fireproofDomains = fireproofDomains
        self.isBurner = tabCollectionViewModel.isBurner
        self.featureFlagger = featureFlagger
        self.defaultBrowserAndDockPromptPresenting = defaultBrowserAndDockPromptPresenting
        self.visualStyle = visualStyle
        self.fireCoordinator = fireCoordinator

        tabBarViewController = TabBarViewController.create(
            tabCollectionViewModel: tabCollectionViewModel,
            bookmarkManager: bookmarkManager,
            fireproofDomains: fireproofDomains,
            activeRemoteMessageModel: NSApp.delegateTyped.activeRemoteMessageModel
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

            let vpnUninstaller = VPNUninstaller(ipcClient: vpnXPCClient)

            return NetworkProtectionNavBarPopoverManager(
                ipcClient: vpnXPCClient,
                vpnUninstaller: vpnUninstaller,
                vpnUIPresenting: Application.appDelegate.windowControllersManager)
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
                statusObserver: vpnXPCClient.ipcStatusObserver,
                serverInfoObserver: vpnXPCClient.ipcServerInfoObserver,
                connectionErrorObserver: vpnXPCClient.ipcConnectionErrorObserver,
                connectivityIssuesObserver: connectivityIssuesObserver,
                controllerErrorMessageObserver: controllerErrorMessageObserver,
                dataVolumeObserver: vpnXPCClient.ipcDataVolumeObserver,
                knownFailureObserver: KnownFailureObserverThroughDistributedNotifications()
            )
        }()

        browserTabViewController = BrowserTabViewController(tabCollectionViewModel: tabCollectionViewModel, bookmarkManager: bookmarkManager)
        aiChatSidebarPresenter = AIChatSidebarPresenter(
            sidebarHost: browserTabViewController,
            sidebarProvider: aiChatSidebarProvider,
            aiChatMenuConfig: aiChatMenuConfig,
            aiChatTabOpener: aiChatTabOpener,
            featureFlagger: featureFlagger,
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
                                                                         bookmarkManager: bookmarkManager,
                                                                         bookmarkDragDropManager: bookmarkDragDropManager,
                                                                         historyCoordinator: historyCoordinator,
                                                                         contentBlocking: contentBlocking,
                                                                         fireproofDomains: fireproofDomains,
                                                                         permissionManager: permissionManager,
                                                                         networkProtectionPopoverManager: networkProtectionPopoverManager,
                                                                         networkProtectionStatusReporter: networkProtectionStatusReporter,
                                                                         autofillPopoverPresenter: autofillPopoverPresenter,
                                                                         brokenSitePromptLimiter: brokenSitePromptLimiter,
                                                                         aiChatMenuConfig: aiChatMenuConfig,
                                                                         aiChatSidebarPresenter: aiChatSidebarPresenter,
                                                                         vpnUpsellPopoverPresenter: vpnUpsellPopoverPresenter,
                                                                         sessionRestorePromptCoordinator: sessionRestorePromptCoordinator)

        findInPageViewController = FindInPageViewController.create()
        fireViewController = FireViewController.create(tabCollectionViewModel: tabCollectionViewModel, fireViewModel: fireCoordinator.fireViewModel, visualizeFireAnimationDecider: visualizeFireAnimationDecider)
        bookmarksBarViewController = BookmarksBarViewController.create(
            tabCollectionViewModel: tabCollectionViewModel,
            bookmarkManager: bookmarkManager,
            dragDropManager: bookmarkDragDropManager
        )
        self.vpnUpsellPopoverPresenter = vpnUpsellPopoverPresenter

        super.init(nibName: nil, bundle: nil)
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

    func windowDidBecomeKey() {
        updateBackMenuItem()
        updateForwardMenuItem()
        updateReloadMenuItem()
        updateStopMenuItem()
        browserTabViewController.windowDidBecomeKey()
        showSetAsDefaultAndAddToDockIfNeeded()
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
    }

    deinit {
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
            if visualStyle.addToolbarShadow {
                if mainView.isBannerViewShown {
                    mainView.divider.backgroundColor = .bannerViewDivider
                } else {
                    mainView.divider.backgroundColor = .shadowSecondary
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

        selectedTabViewModelForHistoryViewOnboardingCancellable = tabCollectionViewModel.$selectedTabViewModel
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                navigationBarViewController.presentHistoryViewOnboardingIfNeeded()
            }
    }

    private func subscribeToTitleChange(of selectedTabViewModel: TabViewModel?) {
        guard let selectedTabViewModel else { return }

        // Only subscribe once the view is added to the window.
        let windowPublisher = view.publisher(for: \.window).filter({ $0 != nil }).prefix(1).asVoid()

        windowPublisher
            .combineLatest(selectedTabViewModel.$title) { $1 }
            .map {
                $0.truncated(length: MainMenu.Constants.maxTitleLength)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                guard let self else { return }
                guard !isBurner else {
                    // Fire Window: don‘t display active Tab title as the Window title
                    view.window?.title = UserText.burnerWindowHeader
                    return
                }

                view.window?.title = title
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

    @objc private func showSetAsDefaultAndAddToDockIfNeeded() {
        defaultBrowserAndDockPromptPresenting.tryToShowPrompt(
            popoverAnchorProvider: getSourceViewToShowSetAsDefaultAndAddToDockPopover,
            bannerViewHandler: showMessageBanner
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

    // MARK: - First responder

    func adjustFirstResponder(selectedTabViewModel: TabViewModel? = nil, tabContent: Tab.TabContent? = nil, force: Bool = false) {
        guard let selectedTabViewModel = selectedTabViewModel ?? tabCollectionViewModel.selectedTabViewModel else {
            return
        }
        let tabContent = tabContent ?? selectedTabViewModel.tab.content

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

    // swiftlint:disable:next cyclomatic_complexity
    func customKeyDown(with event: NSEvent) -> Bool {
        guard let locWindow = self.view.window,
              NSApplication.shared.keyWindow === locWindow else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isWebViewFocused = view.window?.firstResponder is WebView

        // Handle Enter
        if event.keyCode == kVK_Return,
           navigationBarViewController.addressBarViewController?.addressBarTextField.isFirstResponder == true {
            if flags.contains(.shift) && aiChatMenuConfig.shouldDisplayAddressBarShortcut {
                navigationBarViewController.addressBarViewController?.addressBarButtonsViewController?.aiChatButtonAction(self)
            } else {
                navigationBarViewController.addressBarViewController?.addressBarTextField.addressBarEnterPressed()
            }
            return true
        }

        // Handle Escape
        if event.keyCode == kVK_Escape {
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

        // Handle tab switching (CMD+1 through CMD+9)
        if [.command, [.command, .numericPad]].contains(flags), "123456789".contains(key) {
            if isWebViewFocused {
                NSApp.menu?.performKeyEquivalent(with: event)
                return true
            }
            return false
        }

        if event.keyCode == kVK_Tab, [.control, [.control, .shift]].contains(flags) {
            NSApp.menu?.performKeyEquivalent(with: event)
            return true
        }

        // Handle browser tab/window actions
        if isWebViewFocused {
            switch (key, flags, flags.contains(.command)) {
            case ("n", [.command], _),
                 ("t", [.command], _), ("t", [.command, .shift], _),
                 ("w", _, true),
                 ("q", [.command], _),
                 ("r", [.command], _):
                NSApp.menu?.performKeyEquivalent(with: event)
                return true
            default:
                break
            }
        }

        // Handle CMD+Y (history view)
        if key == "y", flags == .command {
            if !NSApp.delegateTyped.featureFlagger.isFeatureOn(.historyView) {
                (NSApp.mainMenuTyped.historyMenu.accessibilityParent() as? NSMenuItem)?.accessibilityPerformPress()
                return true
            }
            return false
        }

        return false
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
            TabsPreferences.shared.pinnedTabsMode == .shared
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
            window.performClose(self)
            return true
        }
        return false
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

    let vc = MainViewController(tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection()), bookmarkManager: bkman, autofillPopoverPresenter: DefaultAutofillPopoverPresenter(), aiChatSidebarProvider: AIChatSidebarProvider())
    var c: AnyCancellable!
    c = vc.publisher(for: \.view.window).sink { window in
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        withExtendedLifetime(c) {}
    }

    return vc
}
#endif
