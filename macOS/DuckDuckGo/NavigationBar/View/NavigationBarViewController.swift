//
//  NavigationBarViewController.swift
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
import Combine
import Common
import Freemium
import History
import VPN
import NetworkProtectionIPC
import NetworkProtectionUI
import os.log
import PageRefreshMonitor
import PixelKit
import Subscription
import SubscriptionUI

final class NavigationBarViewController: NSViewController {

    enum Constants {
        static let downloadsButtonAutoHidingInterval: TimeInterval = 5 * 60
        static let maxDragDistanceToExpandHoveredFolder: CGFloat = 4
        static let dragOverFolderExpandDelay: TimeInterval = 0.3
    }

    @IBOutlet weak var goBackButton: MouseOverButton!
    @IBOutlet weak var goForwardButton: MouseOverButton!
    @IBOutlet weak var refreshOrStopButton: MouseOverButton!
    @IBOutlet weak var optionsButton: MouseOverButton!
    @IBOutlet weak var overflowButton: MouseOverButton!
    @IBOutlet weak var bookmarkListButton: MouseOverButton!
    @IBOutlet weak var passwordManagementButton: MouseOverButton!
    @IBOutlet weak var homeButton: MouseOverButton!
    @IBOutlet weak var homeButtonSeparator: NSView!
    @IBOutlet weak var downloadsButton: MouseOverButton!
    @IBOutlet weak var networkProtectionButton: MouseOverButton!
    @IBOutlet weak var navigationButtons: NSStackView!
    @IBOutlet weak var addressBarContainer: NSView!
    @IBOutlet weak var daxLogo: NSImageView!
    @IBOutlet weak var addressBarStack: NSStackView!

    @IBOutlet weak var menuButtons: NSStackView!

    @IBOutlet var addressBarLeftToNavButtonsConstraint: NSLayoutConstraint!
    @IBOutlet var addressBarProportionalWidthConstraint: NSLayoutConstraint!
    @IBOutlet var navigationBarButtonsLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var addressBarTopConstraint: NSLayoutConstraint!
    @IBOutlet var addressBarBottomConstraint: NSLayoutConstraint!
    @IBOutlet var navigationBarHeightConstraint: NSLayoutConstraint!
    @IBOutlet var buttonsTopConstraint: NSLayoutConstraint!
    @IBOutlet var addressBarMinWidthConstraint: NSLayoutConstraint!
    @IBOutlet var logoWidthConstraint: NSLayoutConstraint!
    @IBOutlet var backgroundColorView: MouseOverView!
    @IBOutlet var backgroundBaseColorView: ColorView!
    @IBOutlet weak var goBackButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var goBackButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var goForwardButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var goForwardButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var refreshButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var refreshButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var homeButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var homeButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var downloadsButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var downloadsButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var passwordsButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var passwordsButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var bookmarksButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var bookmarksButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var vpnButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var vpnButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var overflowButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var overflowButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var optionsButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var optionsButtonHeightConstraint: NSLayoutConstraint!

    private let downloadListCoordinator: DownloadListCoordinator

    lazy var downloadsProgressView: CircularProgressView = {
        let bounds = downloadsButton.bounds
        let width: CGFloat = 27.0
        let frame = NSRect(x: (bounds.width - width) * 0.5, y: (bounds.height - width) * 0.5, width: width, height: width)
        let progressView = CircularProgressView(frame: frame)
        downloadsButton.addSubview(progressView)
        return progressView
    }()

    private let bookmarkDragDropManager: BookmarkDragDropManager
    private let bookmarkManager: BookmarkManager
    private let historyCoordinator: HistoryCoordinator
    private let fireproofDomains: FireproofDomains
    private let contentBlocking: ContentBlockingProtocol
    private let permissionManager: PermissionManagerProtocol

    private var subscriptionManager: SubscriptionAuthV1toV2Bridge {
        Application.appDelegate.subscriptionAuthV1toV2Bridge
    }

    var addressBarViewController: AddressBarViewController?

    private var tabCollectionViewModel: TabCollectionViewModel
    private var burnerMode: BurnerMode { tabCollectionViewModel.burnerMode }

    // swiftlint:disable weak_delegate
    private let goBackButtonMenuDelegate: NavigationButtonMenuDelegate
    private let goForwardButtonMenuDelegate: NavigationButtonMenuDelegate
    // swiftlint:enable weak_delegate

    private var popovers: NavigationBarPopovers

    // used to show Bookmarks when dragging over the Bookmarks button
    private var dragDestination: (mouseLocation: NSPoint, hoverStarted: Date)?

    var isDownloadsPopoverShown: Bool {
        popovers.isDownloadsPopoverShown
    }
    var isAutoFillAutosaveMessageVisible: Bool = false

    private var urlCancellable: AnyCancellable?
    private var selectedTabViewModelCancellable: AnyCancellable?
    private var credentialsToSaveCancellable: AnyCancellable?
    private var vpnToggleCancellable: AnyCancellable?
    private var feedbackFormCancellable: AnyCancellable?
    private var passwordManagerNotificationCancellable: AnyCancellable?
    private var pinnedViewsNotificationCancellable: AnyCancellable?
    private var navigationButtonsCancellables = Set<AnyCancellable>()
    private var downloadsCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private let brokenSitePromptLimiter: BrokenSitePromptLimiter
    private let featureFlagger: FeatureFlagger
    private let visualStyle: VisualStyleProviding
    private let aiChatSidebarPresenter: AIChatSidebarPresenting

    private var leftFocusSpacer: NSView?
    private var rightFocusSpacer: NSView?

    @UserDefaultsWrapper(key: .homeButtonPosition, defaultValue: .right)
    static private var homeButtonPosition: HomeButtonPosition
    static private let homeButtonTag = 3
    static private let homeButtonLeftPosition = 0

    private let networkProtectionButtonModel: NetworkProtectionNavBarButtonModel

    static func create(tabCollectionViewModel: TabCollectionViewModel,
                       downloadListCoordinator: DownloadListCoordinator = .shared,
                       bookmarkManager: BookmarkManager,
                       bookmarkDragDropManager: BookmarkDragDropManager,
                       historyCoordinator: HistoryCoordinator,
                       contentBlocking: ContentBlockingProtocol,
                       fireproofDomains: FireproofDomains,
                       permissionManager: PermissionManagerProtocol,
                       networkProtectionPopoverManager: NetPPopoverManager,
                       networkProtectionStatusReporter: NetworkProtectionStatusReporter,
                       autofillPopoverPresenter: AutofillPopoverPresenter,
                       brokenSitePromptLimiter: BrokenSitePromptLimiter,
                       featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
                       visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle,
                       aiChatSidebarPresenter: AIChatSidebarPresenting
    ) -> NavigationBarViewController {
        NSStoryboard(name: "NavigationBar", bundle: nil).instantiateInitialController { coder in
            self.init(
                coder: coder,
                tabCollectionViewModel: tabCollectionViewModel,
                downloadListCoordinator: downloadListCoordinator,
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
                featureFlagger: featureFlagger,
                visualStyle: visualStyle,
                aiChatSidebarPresenter: aiChatSidebarPresenter
            )
        }!
    }

    init?(
        coder: NSCoder,
        tabCollectionViewModel: TabCollectionViewModel,
        downloadListCoordinator: DownloadListCoordinator,
        bookmarkManager: BookmarkManager,
        bookmarkDragDropManager: BookmarkDragDropManager,
        historyCoordinator: HistoryCoordinator,
        contentBlocking: ContentBlockingProtocol,
        fireproofDomains: FireproofDomains,
        permissionManager: PermissionManagerProtocol,
        networkProtectionPopoverManager: NetPPopoverManager,
        networkProtectionStatusReporter: NetworkProtectionStatusReporter,
        autofillPopoverPresenter: AutofillPopoverPresenter,
        brokenSitePromptLimiter: BrokenSitePromptLimiter,
        featureFlagger: FeatureFlagger,
        visualStyle: VisualStyleProviding,
        aiChatSidebarPresenter: AIChatSidebarPresenting
    ) {

        self.popovers = NavigationBarPopovers(
            bookmarkManager: bookmarkManager,
            bookmarkDragDropManager: bookmarkDragDropManager,
            contentBlocking: contentBlocking,
            fireproofDomains: fireproofDomains,
            permissionManager: permissionManager,
            networkProtectionPopoverManager: networkProtectionPopoverManager,
            autofillPopoverPresenter: autofillPopoverPresenter,
            isBurner: tabCollectionViewModel.isBurner
        )
        self.tabCollectionViewModel = tabCollectionViewModel
        self.networkProtectionButtonModel = NetworkProtectionNavBarButtonModel(popoverManager: networkProtectionPopoverManager,
                                                                               statusReporter: networkProtectionStatusReporter,
                                                                               iconProvider: visualStyle.iconsProvider.vpnNavigationIconsProvider)
        self.downloadListCoordinator = downloadListCoordinator
        self.bookmarkManager = bookmarkManager
        self.bookmarkDragDropManager = bookmarkDragDropManager
        self.historyCoordinator = historyCoordinator
        self.contentBlocking = contentBlocking
        self.permissionManager = permissionManager
        self.fireproofDomains = fireproofDomains
        self.brokenSitePromptLimiter = brokenSitePromptLimiter
        self.featureFlagger = featureFlagger
        self.visualStyle = visualStyle
        self.aiChatSidebarPresenter = aiChatSidebarPresenter
        goBackButtonMenuDelegate = NavigationButtonMenuDelegate(buttonType: .back, tabCollectionViewModel: tabCollectionViewModel, historyCoordinator: historyCoordinator)
        goForwardButtonMenuDelegate = NavigationButtonMenuDelegate(buttonType: .forward, tabCollectionViewModel: tabCollectionViewModel, historyCoordinator: historyCoordinator)
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("NavigationBarViewController: Bad initializer")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.masksToBounds = false
        addressBarContainer.wantsLayer = true
        addressBarContainer.layer?.masksToBounds = false

        setupBackgroundViewsAndColors()
        setupNavigationButtonsCornerRadius()
        setupNavigationButtonMenus()
        setupNavigationButtonIcons()
        setupNavigationButtonColors()
        setupNavigationButtonsSize()
        addContextMenu()
        setupOverflowMenu()

        menuButtons.spacing = visualStyle.navigationToolbarButtonsSpacing
        navigationButtons.spacing = visualStyle.navigationToolbarButtonsSpacing

        optionsButton.sendAction(on: .leftMouseDown)
        bookmarkListButton.sendAction(on: .leftMouseDown)
        bookmarkListButton.registerForDraggedTypes(BookmarkDragDropManager.draggedTypes)
        bookmarkListButton.delegate = self
        bookmarkListButton.setAccessibilityIdentifier("NavigationBarViewController.bookmarkListButton")
        downloadsButton.sendAction(on: .leftMouseDown)
        downloadsButton.setAccessibilityIdentifier("NavigationBarViewController.downloadsButton")
        networkProtectionButton.sendAction(on: .leftMouseDown)
        passwordManagementButton.sendAction(on: .leftMouseDown)

        optionsButton.toolTip = UserText.applicationMenuTooltip
        optionsButton.setAccessibilityIdentifier("NavigationBarViewController.optionsButton")

        networkProtectionButton.toolTip = UserText.networkProtectionButtonTooltip

        setupNetworkProtectionButton()

#if DEBUG || REVIEW
        addDebugNotificationListeners()
#endif

#if !APPSTORE && WEB_EXTENSIONS_ENABLED
        if #available(macOS 15.4, *), !burnerMode.isBurner {
            Task { @MainActor in
                await WebExtensionNavigationBarUpdater(container: menuButtons).runUpdateLoop()
            }
        }
#endif
    }

    override func viewWillAppear() {
        subscribeToSelectedTabViewModel()
        listenToVPNToggleNotifications()
        listenToPasswordManagerNotifications()
        listenToPinningManagerNotifications()
        listenToMessageNotifications()
        listenToFeedbackFormNotifications()
        subscribeToDownloads()
        subscribeToNavigationBarWidthChanges()

        updateDownloadsButton(source: .default)
        updatePasswordManagementButton()
        updateBookmarksButton()
        updateHomeButton()

        if view.window?.isPopUpWindow == true {
            goBackButton.isHidden = true
            goForwardButton.isHidden = true
            refreshOrStopButton.isHidden = true
            optionsButton.isHidden = true
            homeButton.isHidden = true
            homeButtonSeparator.isHidden = true
            overflowButton.isHidden = true
            addressBarTopConstraint.constant = 0
            addressBarBottomConstraint.constant = 0
            addressBarLeftToNavButtonsConstraint.isActive = false
            addressBarProportionalWidthConstraint.isActive = false
            navigationBarButtonsLeadingConstraint.isActive = false

            // This pulls the dashboard button to the left for the popup
            NSLayoutConstraint.activate(addressBarStack.addConstraints(to: view, [
                .leading: .leading(multiplier: 1.0, const: 72)
            ]))
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        updateNavigationBarForCurrentWidth()
    }

    override func viewWillLayout() {
        super.viewWillLayout()

        updateNavigationBarForCurrentWidth()
    }

    /**
     * Presents History View onboarding.
     *
     * This is gater by the decider that takes into account whether the user is new,
     * whether they've seen the popover already and whether the feature flag is enabled.
     *
     * > `force` parameter is only used by `HistoryDebugMenu`.
     */
    func presentHistoryViewOnboardingIfNeeded(force: Bool = false) {
        Task { @MainActor in
            let onboardingDecider = HistoryViewOnboardingDecider()
            guard force || onboardingDecider.shouldPresentOnboarding,
                  !tabCollectionViewModel.isBurner,
                  view.window?.isKeyWindow == true
            else {
                return
            }

            // If we're on history tab, we don't show the onboarding and mark it as shown,
            // assuming that the user is onboarded
            guard tabCollectionViewModel.selectedTabViewModel?.tab.content != .history else {
                onboardingDecider.skipPresentingOnboarding()
                return
            }

            popovers.showHistoryViewOnboardingPopover(from: optionsButton, withDelegate: self) { [weak self] showHistory in
                guard let self else { return }

                popovers.closeHistoryViewOnboardingViewPopover()

                if showHistory {
                    tabCollectionViewModel.insertOrAppendNewTab(.history, selected: true)
                }
            }
        }
    }

    @IBSegueAction func createAddressBarViewController(_ coder: NSCoder) -> AddressBarViewController? {
        let onboardingPixelReporter = OnboardingPixelReporter()
        guard let addressBarViewController = AddressBarViewController(coder: coder,
                                                                      tabCollectionViewModel: tabCollectionViewModel,
                                                                      bookmarkManager: bookmarkManager,
                                                                      historyCoordinator: historyCoordinator,
                                                                      privacyConfigurationManager: contentBlocking.privacyConfigurationManager,
                                                                      permissionManager: permissionManager,
                                                                      burnerMode: burnerMode,
                                                                      popovers: popovers,
                                                                      onboardingPixelReporter: onboardingPixelReporter,
                                                                      aiChatSidebarPresenter: aiChatSidebarPresenter) else {
            fatalError("NavigationBarViewController: Failed to init AddressBarViewController")
        }

        self.addressBarViewController = addressBarViewController
        self.addressBarViewController?.delegate = self
        return addressBarViewController
    }

    @IBAction func goBackAction(_ sender: NSButton) {
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.navigation.error("Selected tab view model is nil")
            return
        }
        if !openBackForwardHistoryItemInNewTabIfNeeded(with: selectedTabViewModel.tab.webView.backForwardList.backItem?.url) {
            selectedTabViewModel.tab.goBack()
        }
    }

    @IBAction func goForwardAction(_ sender: NSButton) {
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.navigation.error("Selected tab view model is nil")
            return
        }
        if !openBackForwardHistoryItemInNewTabIfNeeded(with: selectedTabViewModel.tab.webView.backForwardList.forwardItem?.url) {
            selectedTabViewModel.tab.goForward()
        }
    }

    /// When ⌘+ or middle- clicked open the back/forward item in a new tab
    /// - returns:`true` if opened in a new tab
    private func openBackForwardHistoryItemInNewTabIfNeeded(with url: URL?) -> Bool {
        guard let url,
              // don‘t open a new tab when the window is cmd-clicked in background
              !NSApp.isCommandPressed || (view.window?.isKeyWindow == true && NSApp.isActive) else { return false }

        // Create behavior using current event
        let behavior = LinkOpenBehavior(
            event: NSApp.currentEvent,
            switchToNewTabWhenOpenedPreference: TabsPreferences.shared.switchToNewTabWhenOpened,
            canOpenLinkInCurrentTab: true
        )

        lazy var tab = Tab(content: .url(url, source: .historyEntry), parentTab: tabCollectionViewModel.selectedTabViewModel?.tab, shouldLoadInBackground: true, burnerMode: tabCollectionViewModel.burnerMode)
        switch behavior {
        case .currentTab:
            return false

        case .newTab(let selected):
            tabCollectionViewModel.insert(tab, selected: selected)
        case .newWindow(let selected):
            WindowsManager.openNewWindow(with: tab, showWindow: selected)
        }
        return true
    }

    @IBAction func refreshOrStopAction(_ sender: NSButton) {
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.navigation.error("Selected tab view model is nil")
            return
        }

        if selectedTabViewModel.isLoading {
            selectedTabViewModel.tab.stopLoading()
        } else {
            selectedTabViewModel.reload()
        }
    }

    @IBAction func homeButtonAction(_ sender: NSButton) {
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.navigation.error("Selected tab view model is nil")
            return
        }

        PixelKit.fire(NavigationBarPixel.homeButtonClicked, frequency: .daily)

        let behavior = LinkOpenBehavior(
            event: NSApp.currentEvent,
            switchToNewTabWhenOpenedPreference: TabsPreferences.shared.switchToNewTabWhenOpened,
            canOpenLinkInCurrentTab: true
        )

        let startupPreferences = NSApp.delegateTyped.startupPreferences
        let tabContent: TabContent
        if startupPreferences.launchToCustomHomePage,
           let customURL = URL(string: startupPreferences.formattedCustomHomePageURL) {
            tabContent = .contentFromURL(customURL, source: .ui)
        } else {
            tabContent = .newtab
        }

        lazy var tab = Tab(content: tabContent, parentTab: nil, shouldLoadInBackground: true, burnerMode: tabCollectionViewModel.burnerMode)
        switch behavior {
        case .currentTab:
            selectedTabViewModel.tab.openHomePage()
        case .newTab(let selected):
            tabCollectionViewModel.insert(tab, selected: selected)
        case .newWindow(let selected):
            WindowsManager.openNewWindow(with: tab, showWindow: selected)
        }
    }

    @IBAction func overflowButtonAction(_ sender: NSButton) {
        guard let menu = overflowButton.menu else {
            return
        }
        let location = NSPoint(x: -menu.size.width + sender.bounds.width, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    @IBAction func optionsButtonAction(_ sender: NSButton) {
        let internalUserDecider = NSApp.delegateTyped.internalUserDecider
        let freemiumDBPFeature = Application.appDelegate.freemiumDBPFeature
        var dockCustomization: DockCustomization?
#if SPARKLE
        dockCustomization = Application.appDelegate.dockCustomization
#endif
        let menu = MoreOptionsMenu(tabCollectionViewModel: tabCollectionViewModel,
                                   bookmarkManager: bookmarkManager,
                                   historyCoordinator: historyCoordinator,
                                   fireproofDomains: fireproofDomains,
                                   passwordManagerCoordinator: PasswordManagerCoordinator.shared,
                                   vpnFeatureGatekeeper: DefaultVPNFeatureGatekeeper(subscriptionManager: subscriptionManager),
                                   internalUserDecider: internalUserDecider,
                                   subscriptionManager: subscriptionManager,
                                   freemiumDBPFeature: freemiumDBPFeature,
                                   dockCustomizer: dockCustomization)

        menu.actionDelegate = self
        let location = NSPoint(x: -menu.size.width + sender.bounds.width, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    @IBAction func bookmarksButtonAction(_ sender: NSButton) {
        popovers.bookmarksButtonPressed(bookmarkListButton, popoverDelegate: self, tab: tabCollectionViewModel.selectedTabViewModel?.tab)
        PixelKit.fire(NavigationBarPixel.bookmarksButtonClicked, frequency: .daily)
    }

    @IBAction func passwordManagementButtonAction(_ sender: NSButton) {
        popovers.passwordManagementButtonPressed(passwordManagementButton, withDelegate: self)
        PixelKit.fire(NavigationBarPixel.passwordsButtonClicked, frequency: .daily)
    }

    @IBAction func networkProtectionButtonAction(_ sender: NSButton) {
        toggleNetworkProtectionPopover()
    }

    private func toggleNetworkProtectionPopover() {
        guard Application.appDelegate.subscriptionAuthV1toV2Bridge.isUserAuthenticated else {
            return
        }

        popovers.toggleNetworkProtectionPopover(from: networkProtectionButton, withDelegate: networkProtectionButtonModel)
    }

    @IBAction func downloadsButtonAction(_ sender: NSButton) {
        toggleDownloadsPopover(keepButtonVisible: false)
        PixelKit.fire(NavigationBarPixel.downloadsButtonClicked, frequency: .daily)
    }

    override func mouseDown(with event: NSEvent) {
        if let menu = view.menu, NSEvent.isContextClick(event) {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return
        }

        super.mouseDown(with: event)
    }

    func listenToVPNToggleNotifications() {
        vpnToggleCancellable = NotificationCenter.default.publisher(for: .ToggleNetworkProtectionInMainWindow).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard self?.view.window?.isKeyWindow == true else {
                return
            }

            self?.toggleNetworkProtectionPopover()
        }
    }

    func listenToPasswordManagerNotifications() {
        passwordManagerNotificationCancellable = NotificationCenter.default.publisher(for: .PasswordManagerChanged).sink { [weak self] _ in
            self?.updatePasswordManagementButton()
        }
    }

    func listenToPinningManagerNotifications() {
        pinnedViewsNotificationCancellable = NotificationCenter.default.publisher(for: .PinnedViewsChanged).sink { [weak self] notification in
            guard let self = self else {
                return
            }

            if let userInfo = notification.userInfo as? [String: Any],
               let viewType = userInfo[LocalPinningManager.pinnedViewChangedNotificationViewTypeKey] as? String,
               let view = PinnableView(rawValue: viewType) {
                updateNavigationBarForCurrentWidth()
                switch view {
                case .autofill:
                    self.updatePasswordManagementButton()
                case .bookmarks:
                    self.updateBookmarksButton()
                case .downloads:
                    self.updateDownloadsButton(source: .pinnedViewsNotification)
                case .homeButton:
                    self.updateHomeButton()
                case .networkProtection:
                    self.networkProtectionButtonModel.updateVisibility()
                }
            } else {
                assertionFailure("Failed to get changed pinned view type")
                self.updateBookmarksButton()
                self.updatePasswordManagementButton()
            }
        }
    }

    func listenToMessageNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showFireproofingFeedback(_:)),
                                               name: FireproofDomains.Constants.newFireproofDomainNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showPrivateEmailCopiedToClipboard(_:)),
                                               name: Notification.Name.privateEmailCopiedToClipboard,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showLoginAutosavedFeedback(_:)),
                                               name: .loginAutoSaved,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showPasswordsAutoPinnedFeedback(_:)),
                                               name: .passwordsAutoPinned,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showPasswordsPinningOption(_:)),
                                               name: .passwordsPinningPrompt,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showAutoconsentFeedback(_:)),
                                               name: AutoconsentUserScript.newSitePopupHiddenNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(attemptToShowBrokenSitePrompt(_:)),
                                               name: .pageRefreshMonitorDidDetectRefreshPattern,
                                               object: nil)

        UserDefaults.netP
            .publisher(for: \.networkProtectionShouldShowVPNUninstalledMessage)
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] shouldShowUninstalledMessage in
                if shouldShowUninstalledMessage {
                    self?.showVPNUninstalledFeedback()
                    UserDefaults.netP.networkProtectionShouldShowVPNUninstalledMessage = false
                }
            }
            .store(in: &cancellables)
    }

    func listenToFeedbackFormNotifications() {
        feedbackFormCancellable = NotificationCenter.default.publisher(for: .OpenUnifiedFeedbackForm).receive(on: DispatchQueue.main).sink { notification in
            let source = UnifiedFeedbackSource(userInfo: notification.userInfo)
            Application.appDelegate.windowControllersManager.showShareFeedbackModal(source: source)
        }
    }

    @objc private func showVPNUninstalledFeedback() {
        // Only show the popover if we aren't already presenting one:
        guard view.window?.isKeyWindow == true, (self.presentedViewControllers ?? []).isEmpty else { return }

        DispatchQueue.main.async {
            let viewController = PopoverMessageViewController(message: "DuckDuckGo VPN was uninstalled")
            viewController.show(onParent: self, relativeTo: self.optionsButton)
        }
    }

    @objc private func showPrivateEmailCopiedToClipboard(_ sender: Notification) {
        guard view.window?.isKeyWindow == true else { return }

        DispatchQueue.main.async {
            let viewController = PopoverMessageViewController(message: UserText.privateEmailCopiedToClipboard)
            viewController.show(onParent: self, relativeTo: self.optionsButton)
        }
    }

    @objc private func showFireproofingFeedback(_ sender: Notification) {
        guard view.window?.isKeyWindow == true,
              let domain = sender.userInfo?[FireproofDomains.Constants.newFireproofDomainKey] as? String else { return }

        DispatchQueue.main.async {
            let viewController = PopoverMessageViewController(message: UserText.domainIsFireproof(domain: domain))
            viewController.show(onParent: self, relativeTo: self.optionsButton)
        }
    }

    @objc private func showLoginAutosavedFeedback(_ sender: Notification) {
        guard view.window?.isKeyWindow == true,
              let account = sender.object as? SecureVaultModels.WebsiteAccount else { return }

        guard let domain = account.domain else {
            return
        }

        DispatchQueue.main.async {

            let action = {
                self.showPasswordManagerPopover(selectedWebsiteAccount: account)
            }
            let popoverMessage = PopoverMessageViewController(message: UserText.passwordManagerAutosavePopoverText(domain: domain),
                                                              image: .passwordManagement,
                                                              buttonText: UserText.passwordManagerAutosaveButtonText,
                                                              buttonAction: action,
                                                              onDismiss: {
                                                                    self.isAutoFillAutosaveMessageVisible = false
                                                                    self.passwordManagementButton.isHidden = !LocalPinningManager.shared.isPinned(.autofill)
            }
                                                              )
            self.isAutoFillAutosaveMessageVisible = true
            self.passwordManagementButton.isHidden = false
            popoverMessage.show(onParent: self, relativeTo: self.passwordManagementButton)
        }
    }

    @objc private func showPasswordsAutoPinnedFeedback(_ sender: Notification) {
        DispatchQueue.main.async {
            let popoverMessage = PopoverMessageViewController(message: UserText.passwordManagerAutoPinnedPopoverText)
            popoverMessage.show(onParent: self, relativeTo: self.passwordManagementButton)
        }
    }

    @objc private func showPasswordsPinningOption(_ sender: Notification) {
        guard view.window?.isKeyWindow == true else { return }

        DispatchQueue.main.async {
            self.popovers.showAutofillOnboardingPopover(from: self.passwordManagementButton,
                                                   withDelegate: self) { [weak self] didAddShortcut in
                guard let self = self else { return }
                self.popovers.closeAutofillOnboardingPopover()

                if didAddShortcut {
                    LocalPinningManager.shared.pin(.autofill)
                }
            }
        }
    }

    @objc private func showAutoconsentFeedback(_ sender: Notification) {
        guard view.window?.isKeyWindow == true,
              let topUrl = sender.userInfo?["topUrl"] as? URL,
              let isCosmetic = sender.userInfo?["isCosmetic"] as? Bool
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.tabCollectionViewModel.selectedTabViewModel?.tab.url == topUrl else {
                return // if the tab is not active, don't show the popup
            }
            let animationType: NavigationBarBadgeAnimationView.AnimationType = isCosmetic ? .cookiePopupHidden : .cookiePopupManaged
            self.addressBarViewController?.addressBarButtonsViewController?.showBadgeNotification(animationType)
        }
    }

    @objc private func attemptToShowBrokenSitePrompt(_ sender: Notification) {
        guard brokenSitePromptLimiter.shouldShowToast(),
              let url = tabCollectionViewModel.selectedTabViewModel?.tab.url, !url.isDuckDuckGo,
              isOnboardingFinished
        else { return }
        showBrokenSitePrompt()
    }

    private var isOnboardingFinished: Bool {
        OnboardingActionsManager.isOnboardingFinished && Application.appDelegate.onboardingContextualDialogsManager.state == .onboardingCompleted
    }

    private func showBrokenSitePrompt() {
        guard view.window?.isKeyWindow == true,
              let privacyButton = addressBarViewController?.addressBarButtonsViewController?.privacyEntryPointButton else { return }
        brokenSitePromptLimiter.didShowToast()
        PixelKit.fire(GeneralPixel.siteNotWorkingShown)
        let popoverMessage = PopoverMessageViewController(message: UserText.BrokenSitePrompt.title,
                                                          buttonText: UserText.BrokenSitePrompt.buttonTitle,
                                                          buttonAction: {
            self.brokenSitePromptLimiter.didOpenReport()
            self.addressBarViewController?.addressBarButtonsViewController?.openPrivacyDashboardPopover(entryPoint: .prompt)
            PixelKit.fire(GeneralPixel.siteNotWorkingWebsiteIsBroken)
        },
                                                          shouldShowCloseButton: true,
                                                          autoDismissDuration: nil,
                                                          onDismiss: {
            self.brokenSitePromptLimiter.didDismissToast()
        }
        )
        popoverMessage.show(onParent: self, relativeTo: privacyButton, behavior: .semitransient)
    }

    func toggleDownloadsPopover(keepButtonVisible: Bool) {

        downloadsButton.isHidden = false
        if keepButtonVisible {
            setDownloadButtonHidingTimer()
        }

        popovers.toggleDownloadsPopover(from: downloadsButton, popoverDelegate: self, downloadsDelegate: self)
    }

    func showPasswordManagerPopover(selectedCategory: SecureVaultSorting.Category?, source: PasswordManagementSource) {
        popovers.showPasswordManagementPopover(selectedCategory: selectedCategory, from: passwordManagementButton, withDelegate: self, source: source)
    }

    func showPasswordManagerPopover(selectedWebsiteAccount: SecureVaultModels.WebsiteAccount) {
        popovers.showPasswordManagerPopover(selectedWebsiteAccount: selectedWebsiteAccount, from: passwordManagementButton, withDelegate: self)
    }

    private func setupNavigationButtonMenus() {
        let backButtonMenu = NSMenu()
        backButtonMenu.delegate = goBackButtonMenuDelegate
        goBackButton.menu = backButtonMenu
        goBackButton.sendAction(on: [.leftMouseUp, .otherMouseDown])
        let forwardButtonMenu = NSMenu()
        forwardButtonMenu.delegate = goForwardButtonMenuDelegate
        goForwardButton.menu = forwardButtonMenu
        goForwardButton.sendAction(on: [.leftMouseUp, .otherMouseDown])

        homeButton.sendAction(on: [.leftMouseUp, .otherMouseDown])

        goBackButton.toolTip = ShortcutTooltip.back.value
        goForwardButton.toolTip = ShortcutTooltip.forward.value
        refreshOrStopButton.toolTip = ShortcutTooltip.reload.value
    }

    private func setupNavigationButtonIcons() {
        goBackButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.backButtonImage
        goForwardButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.forwardButtonImage
        refreshOrStopButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.reloadButtonImage
        homeButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.homeButtonImage

        downloadsButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.downloadsButtonImage
        passwordManagementButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.passwordManagerButtonImage
        bookmarkListButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.bookmarksButtonImage
        optionsButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.moreOptionsbuttonImage
        overflowButton.image = visualStyle.iconsProvider.navigationToolbarIconsProvider.overflowButtonImage
    }

    private func setupNavigationButtonColors() {
        let allButtons: [MouseOverButton] = [
            goBackButton, goForwardButton, refreshOrStopButton, homeButton,
            downloadsButton, passwordManagementButton, bookmarkListButton, optionsButton]

        allButtons.forEach { button in
            button.normalTintColor = visualStyle.colorsProvider.iconsColor
            button.mouseOverColor = visualStyle.colorsProvider.buttonMouseOverColor
        }
    }

    private func setupNavigationButtonsSize() {
        goBackButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        goBackButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        goForwardButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        goForwardButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        refreshButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        refreshButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        homeButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        homeButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        downloadsButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        downloadsButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        passwordsButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        passwordsButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        bookmarksButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        bookmarksButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        vpnButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        vpnButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        overflowButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        overflowButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        optionsButtonWidthConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
        optionsButtonHeightConstraint.constant = visualStyle.addressBarStyleProvider.addressBarButtonSize
    }

    private func setupBackgroundViewsAndColors() {
        if visualStyle.areNavigationBarCornersRound {
            backgroundBaseColorView.backgroundColor = visualStyle.colorsProvider.baseBackgroundColor
            backgroundColorView.backgroundColor = visualStyle.colorsProvider.navigationBackgroundColor
            backgroundColorView.cornerRadius = 10
            backgroundColorView.maskedCorners = [
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        } else {
            backgroundBaseColorView.backgroundColor = visualStyle.colorsProvider.navigationBackgroundColor
            backgroundColorView.isHidden = true
        }
    }

    private func setupNavigationButtonsCornerRadius() {
        goBackButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        goForwardButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        refreshOrStopButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        homeButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)

        downloadsButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        passwordManagementButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        bookmarkListButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        networkProtectionButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        optionsButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
        overflowButton.setCornerRadius(visualStyle.toolbarButtonsCornerRadius)
    }

    private func subscribeToSelectedTabViewModel() {
        selectedTabViewModelCancellable = tabCollectionViewModel.$selectedTabViewModel.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.subscribeToNavigationActionFlags()
            self?.subscribeToCredentialsToSave()
            self?.subscribeToTabContent()
        }
    }

    private func subscribeToTabContent() {
        urlCancellable = tabCollectionViewModel.selectedTabViewModel?.tab.$content
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] _ in
                self?.updatePasswordManagementButton()
            })
    }

    private var daxFadeInAnimation: DispatchWorkItem?
    private var heightChangeAnimation: DispatchWorkItem?
    func resizeAddressBar(for sizeClass: AddressBarSizeClass, animated: Bool) {
        daxFadeInAnimation?.cancel()
        heightChangeAnimation?.cancel()

        daxLogo.alphaValue = !sizeClass.isLogoVisible ? 1 : 0 // initial value to animate from
        daxLogo.isHidden = visualStyle.addressBarStyleProvider.shouldShowNewSearchIcon

        let performResize = { [weak self] in
            guard let self else { return }

            let isAddressBarFocused = view.window?.firstResponder == addressBarViewController?.addressBarTextField.currentEditor()

            let height: NSLayoutConstraint = animated ? navigationBarHeightConstraint.animator() : navigationBarHeightConstraint
            height.constant = visualStyle.addressBarStyleProvider.navigationBarHeight(for: sizeClass)

            let barTop: NSLayoutConstraint = animated ? addressBarTopConstraint.animator() : addressBarTopConstraint
            barTop.constant = visualStyle.addressBarStyleProvider.addressBarTopPadding(for: sizeClass, focused: isAddressBarFocused)

            let bottom: NSLayoutConstraint = animated ? addressBarBottomConstraint.animator() : addressBarBottomConstraint
            bottom.constant = visualStyle.addressBarStyleProvider.addressBarBottomPadding(for: sizeClass, focused: isAddressBarFocused)

            let logoWidth: NSLayoutConstraint = animated ? logoWidthConstraint.animator() : logoWidthConstraint
            logoWidth.constant = sizeClass.logoWidth

            resizeAddressBarWidth(isAddressBarFocused: isAddressBarFocused)
        }

        let prepareNavigationBar = { [weak self] in
            guard let self else { return }

            addressBarStack.spacing = visualStyle.addressBarStyleProvider.addressBarStackSpacing(for: sizeClass)
            daxLogoWidth = sizeClass.logoWidth + addressBarStack.spacing
        }

        let heightChange: () -> Void
        if animated, let window = view.window, window.isVisible == true {
            heightChange = {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.1
                    prepareNavigationBar()
                    performResize()
                }
            }
            let fadeIn = DispatchWorkItem { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.daxLogo.alphaValue = sizeClass.isLogoVisible ? 1 : 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: fadeIn)
            self.daxFadeInAnimation = fadeIn
        } else {
            daxLogo.alphaValue = sizeClass.isLogoVisible ? 1 : 0
            heightChange = {
                prepareNavigationBar()
                performResize()
            }
        }
        if let window = view.window, window.isVisible {
            let dispatchItem = DispatchWorkItem(block: heightChange)
            DispatchQueue.main.async(execute: dispatchItem)
            self.heightChangeAnimation = dispatchItem
        } else {
            // update synchronously for off-screen view
            prepareNavigationBar()
            heightChange()
        }
    }

    private func resizeAddressBarWidth(isAddressBarFocused: Bool) {
        if visualStyle.addressBarStyleProvider.shouldShowNewSearchIcon {
            if !isAddressBarFocused {
                if leftFocusSpacer == nil {
                    leftFocusSpacer = NSView()
                    leftFocusSpacer?.wantsLayer = true
                    leftFocusSpacer?.translatesAutoresizingMaskIntoConstraints = false
                    leftFocusSpacer?.widthAnchor.constraint(equalToConstant: 1).isActive = true
                }
                if rightFocusSpacer == nil {
                    rightFocusSpacer = NSView()
                    rightFocusSpacer?.wantsLayer = true
                    rightFocusSpacer?.translatesAutoresizingMaskIntoConstraints = false
                    rightFocusSpacer?.widthAnchor.constraint(equalToConstant: 1).isActive = true
                }
                if let left = leftFocusSpacer, !addressBarStack.arrangedSubviews.contains(left) {
                    addressBarStack.insertArrangedSubview(left, at: 0)
                }
                if let right = rightFocusSpacer, !addressBarStack.arrangedSubviews.contains(right) {
                    addressBarStack.insertArrangedSubview(right, at: addressBarStack.arrangedSubviews.count)
                }
            } else {
                if let left = leftFocusSpacer, addressBarStack.arrangedSubviews.contains(left) {
                    addressBarStack.removeArrangedSubview(left)
                    left.removeFromSuperview()
                }
                if let right = rightFocusSpacer, addressBarStack.arrangedSubviews.contains(right) {
                    addressBarStack.removeArrangedSubview(right)
                    right.removeFromSuperview()
                }
            }
        }
    }

    private func subscribeToDownloads() {
        // show Downloads button on download completion for downloads started from non-Fire window
        downloadListCoordinator.updates
            .filter { update in
                // filter download completion events only
                !update.item.isBurner && update.isDownloadCompletedUpdate
            }
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self, !self.isDownloadsPopoverShown,
                      DownloadsPreferences.shared.shouldOpenPopupOnCompletion,
                      Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window === downloadsButton.window else { return }

                self.popovers.showDownloadsPopoverAndAutoHide(from: downloadsButton, popoverDelegate: self, downloadsDelegate: self)
            }
            .store(in: &downloadsCancellables)

        // update Downloads button visibility and state
        downloadListCoordinator.updates
            .throttle(for: 1.0, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] update in
                guard let self, self.view.window?.isVisible == true else { return }
                self.updateDownloadsButton(source: .update(update))
            }
            .store(in: &downloadsCancellables)

        // update Downloads button total progress indicator
        let combinedDownloadProgress = downloadListCoordinator.combinedDownloadProgressCreatingIfNeeded(for: FireWindowSessionRef(window: view.window))
        combinedDownloadProgress.publisher(for: \.totalUnitCount)
            .combineLatest(combinedDownloadProgress.publisher(for: \.completedUnitCount))
            .map { (total, completed) -> Double? in
                guard total > 0, completed < total else { return nil }
                return Double(completed) / Double(total)
            }
            .dropFirst()
            .throttle(for: 0.2, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak downloadsProgressView] progress in
                guard let downloadsProgressView else { return }
                if progress == nil, downloadsProgressView.progress != 1 {
                    // show download completed animation before hiding
                    downloadsProgressView.setProgress(1, animated: true)
                }
                downloadsProgressView.setProgress(progress, animated: true)
            }
            .store(in: &downloadsCancellables)
    }

    private func addContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        self.view.menu = menu
    }

    private func updatePasswordManagementButton() {
        let menu = NSMenu()
        let title = LocalPinningManager.shared.shortcutTitle(for: .autofill)
        menu.addItem(withTitle: title, action: #selector(toggleAutofillPanelPinning), keyEquivalent: "")

        passwordManagementButton.menu = menu
        passwordManagementButton.toolTip = UserText.passwordsShortcutTooltip

        let url = tabCollectionViewModel.selectedTabViewModel?.tab.content.userEditableUrl

        passwordManagementButton.image = .passwordManagement

        if popovers.hasAnySavePopoversVisible() {
            return
        }

        if popovers.isPasswordManagementDirty {
            passwordManagementButton.image = .passwordManagementDirty
            return
        }

        if LocalPinningManager.shared.isPinned(.autofill) {
            passwordManagementButton.isHidden = false
        } else {
            passwordManagementButton.isShown = popovers.isPasswordManagementPopoverShown || isAutoFillAutosaveMessageVisible
        }

        popovers.passwordManagementDomain = nil
        guard let url = url, let hostAndPort = url.hostAndPort() else {
            return
        }

        popovers.passwordManagementDomain = hostAndPort
    }

    private func updateHomeButton() {
        let menu = NSMenu()

        homeButton.menu = menu
        homeButton.toolTip = ShortcutTooltip.home.value

        if LocalPinningManager.shared.isPinned(.homeButton) {
            homeButton.isHidden = false

            if let homeButtonView = navigationButtons.arrangedSubviews.first(where: { $0.tag == Self.homeButtonTag }) {
                navigationButtons.removeArrangedSubview(homeButtonView)
                if Self.homeButtonPosition == .left {
                    navigationButtons.insertArrangedSubview(homeButtonView, at: Self.homeButtonLeftPosition)
                    homeButtonSeparator.isHidden = false
                } else {
                    navigationButtons.insertArrangedSubview(homeButtonView, at: navigationButtons.arrangedSubviews.count)
                    homeButtonSeparator.isHidden = true
                }
            }
        } else {
            homeButton.isHidden = true
            homeButtonSeparator.isHidden = true
        }
    }
    private enum DownloadsButtonUpdateSource {
        case pinnedViewsNotification
        case popoverDidClose
        case update(DownloadListCoordinator.Update)
        case `default`
    }
    private func updateDownloadsButton(source: DownloadsButtonUpdateSource) {
        downloadsButton.menu = NSMenu {
            NSMenuItem(title: LocalPinningManager.shared.shortcutTitle(for: .downloads),
                       action: #selector(toggleDownloadsPanelPinning(_:)),
                       keyEquivalent: "")
        }
        downloadsButton.toolTip = ShortcutTooltip.downloads.value

        if LocalPinningManager.shared.isPinned(.downloads) {
            downloadsButton.isShown = true
            return
        }

        let fireWindowSession = FireWindowSessionRef(window: view.window)
        let hasActiveDownloads = downloadListCoordinator.hasActiveDownloads(for: fireWindowSession)
        downloadsButton.image = hasActiveDownloads ? .downloadsActive : .downloads

        let hasDownloads = downloadListCoordinator.hasDownloads(for: fireWindowSession)
        if !hasDownloads {
            invalidateDownloadButtonHidingTimer()
        }
        let isTimerActive = downloadsButtonHidingTimer != nil

        downloadsButton.isShown = if popovers.isDownloadsPopoverShown {
            true
        } else if case .popoverDidClose = source, hasDownloads {
            true
        } else if hasDownloads, case .update(let update) = source,
                  update.item.fireWindowSession == fireWindowSession,
                  update.item.added.addingTimeInterval(Constants.downloadsButtonAutoHidingInterval) > Date() {
            true
        } else {
            hasActiveDownloads || isTimerActive
        }

        if downloadsButton.isShown {
            setDownloadButtonHidingTimer()
        }

        // If the user has selected Hide Downloads from the navigation bar context menu, and no downloads are active, then force it to be hidden
        // even if the timer is active.
        if case .pinnedViewsNotification = source {
            if !LocalPinningManager.shared.isPinned(.downloads) {
                invalidateDownloadButtonHidingTimer()
                downloadsButton.isShown = hasActiveDownloads
            }
        }
    }

    private var downloadsButtonHidingTimer: Timer?
    private func setDownloadButtonHidingTimer() {
        guard downloadsButtonHidingTimer == nil else { return }

        let timerBlock: (Timer) -> Void = { [weak self] _ in
            guard let self = self else { return }

            self.invalidateDownloadButtonHidingTimer()
            self.hideDownloadButtonIfPossible()
        }

        downloadsButtonHidingTimer = Timer.scheduledTimer(withTimeInterval: Constants.downloadsButtonAutoHidingInterval,
                                                          repeats: false,
                                                          block: timerBlock)
    }

    private func invalidateDownloadButtonHidingTimer() {
        self.downloadsButtonHidingTimer?.invalidate()
        self.downloadsButtonHidingTimer = nil
    }

    private func hideDownloadButtonIfPossible() {
        if LocalPinningManager.shared.isPinned(.downloads) ||
            downloadListCoordinator.hasActiveDownloads(for: FireWindowSessionRef(window: view.window)) ||
            popovers.isDownloadsPopoverShown { return }

        downloadsButton.isHidden = true
    }

    private func updateBookmarksButton() {
        let menu = NSMenu()
        let title = LocalPinningManager.shared.shortcutTitle(for: .bookmarks)
        menu.addItem(withTitle: title, action: #selector(toggleBookmarksPanelPinning(_:)), keyEquivalent: "")

        bookmarkListButton.menu = menu
        bookmarkListButton.toolTip = UserText.bookmarksShortcutTooltip

        if LocalPinningManager.shared.isPinned(.bookmarks) {
            bookmarkListButton.isHidden = false
        } else {
            bookmarkListButton.isHidden = !popovers.bookmarkListPopoverShown
        }
    }

    private func subscribeToCredentialsToSave() {
        credentialsToSaveCancellable = tabCollectionViewModel.selectedTabViewModel?.tab.autofillDataToSavePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self, let data else { return }
                self.promptToSaveAutofillData(data)
                self.tabCollectionViewModel.selectedTabViewModel?.tab.resetAutofillData()
            }
    }

    private func promptToSaveAutofillData(_ data: AutofillData) {
        let autofillPreferences = AutofillPreferences()

        if autofillPreferences.askToSaveUsernamesAndPasswords, let credentials = data.credentials {
            Logger.passwordManager.debug("Presenting Save Credentials popover")
            popovers.displaySaveCredentials(credentials,
                                            automaticallySaved: data.automaticallySavedCredentials,
                                            backfilled: data.backfilled,
                                            usingView: passwordManagementButton,
                                            withDelegate: self)
        } else if autofillPreferences.askToSavePaymentMethods, let card = data.creditCard {
            Logger.passwordManager.debug("Presenting Save Payment Method popover")
            popovers.displaySavePaymentMethod(card,
                                              usingView: passwordManagementButton,
                                              withDelegate: self)
        } else if autofillPreferences.askToSaveAddresses, let identity = data.identity {
            Logger.passwordManager.debug("Presenting Save Identity popover")
            popovers.displaySaveIdentity(identity,
                                         usingView: passwordManagementButton,
                                         withDelegate: self)
        } else {
            Logger.passwordManager.error("Received save autofill data call, but there was no data to present")
        }
    }

    private func subscribeToNavigationActionFlags() {
        navigationButtonsCancellables.removeAll()
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else { return }

        selectedTabViewModel.$canGoBack
            .removeDuplicates()
            .assign(to: \.isEnabled, onWeaklyHeld: goBackButton)
            .store(in: &navigationButtonsCancellables)

        selectedTabViewModel.$canGoForward
            .removeDuplicates()
            .assign(to: \.isEnabled, onWeaklyHeld: goForwardButton)
            .store(in: &navigationButtonsCancellables)

        Publishers.CombineLatest(selectedTabViewModel.$canReload, selectedTabViewModel.$isLoading)
            .map({
                $0.canReload || $0.isLoading
            } as ((canReload: Bool, isLoading: Bool)) -> Bool)
            .removeDuplicates()
            .assign(to: \.isEnabled, onWeaklyHeld: refreshOrStopButton)
            .store(in: &navigationButtonsCancellables)

        selectedTabViewModel.$isLoading
            .removeDuplicates()
            .sink { [weak refreshOrStopButton] isLoading in
                refreshOrStopButton?.image = isLoading ? .stop : .refresh
                refreshOrStopButton?.toolTip = isLoading ? ShortcutTooltip.stopLoading.value : ShortcutTooltip.reload.value
            }
            .store(in: &navigationButtonsCancellables)
    }

    // MARK: - Overflow menu

    var pinnedViews: [PinnableView] {
        let allButtons: [PinnableView] = [.downloads, .autofill, .bookmarks, .networkProtection, .homeButton]
        return allButtons.filter(LocalPinningManager.shared.isPinned)
    }

    private var visiblePinnedItems: [PinnableView] {
        pinnedViews.filter { isVisibleInNavBar($0) }
    }

    private var overflowItems: [PinnableView] {
        pinnedViews.filter { !isVisibleInNavBar($0) }
    }

    private var isAIChatButtonInOverflowMenu: Bool = false

    private var visiblePinnedViewsRequiredWidth: CGFloat {
        let visiblePinnedViewsWidth = visiblePinnedItems.map(navBarWidth).reduce(0, +)
        let overflowButtonWidth = overflowButton.isVisible ? overflowButton.bounds.width : 0
        return visiblePinnedViewsWidth + overflowButtonWidth
    }

    /// Width of displayed address bar buttons that add to the minimum width of the address bar (e.g. zoom, permissions)
    private var addressBarButtonsAddedWidth: CGFloat = 0

    private var daxLogoWidth: CGFloat = 0

    private var overflowThreshold: CGFloat {
        let availableWidth = view.bounds.width - 24 // account for leading and trailing space
        let alwaysVisibleButtonsWidth = [goBackButton, goForwardButton, refreshOrStopButton, optionsButton].map(\.bounds.width).reduce(0, +)
        let addressBarMinWidth = addressBarMinWidthConstraint.constant + addressBarButtonsAddedWidth + 24 // account for leading and trailing space
        return availableWidth - alwaysVisibleButtonsWidth - addressBarMinWidth - daxLogoWidth
    }

    private func setupOverflowMenu() {
        overflowButton.menu = NSMenu()
        overflowButton.isHidden = true
        overflowButton.sendAction(on: .leftMouseDown)
    }

    private func subscribeToNavigationBarWidthChanges() {
        addressBarViewController?.addressBarButtonsViewController?.$buttonsWidth
            .sink { [weak self] totalWidth in
                guard let self,
                        let staticButton = addressBarViewController?.addressBarButtonsViewController?.privacyEntryPointButton else {
                    return
                }
                let optionalButtonsWidth = totalWidth - staticButton.bounds.width
                addressBarButtonsAddedWidth = optionalButtonsWidth
                updateNavigationBarForCurrentWidth()
            }
            .store(in: &cancellables)
    }

    private func updateNavigationBarForCurrentWidth() {
        guard !pinnedViews.isEmpty else {
            return
        }

        // Don't make changes while the address bar text field is active, unless we are on the home page.
        // This allows the address bar to maintain its width when activating it at narrow widths.
        guard let addressBarViewController, !addressBarViewController.isFirstResponder || addressBarViewController.isHomePage else {
            return
        }

        if visiblePinnedViewsRequiredWidth >= overflowThreshold {
            moveButtonsToOverflowMenuIfNeeded()
        } else if isAIChatButtonInOverflowMenu {
            // Restore AI chat button first, if needed
            let newMaximumWidth = visiblePinnedViewsRequiredWidth + 39
            if newMaximumWidth < overflowThreshold {
                toggleAIChatButtonVisibility(isHidden: false)
            }
        } else if !overflowItems.isEmpty {
            removeButtonsFromOverflowMenuIfPossible()
        }
    }

    private func moveButtonsToOverflowMenuIfNeeded() {
        while visiblePinnedViewsRequiredWidth >= overflowThreshold {
            guard visiblePinnedItems.count > 1 else {
                // Leave at least one visible pinned item, but hide AI chat button if needed
                toggleAIChatButtonVisibility(isHidden: true)
                break
            }
            guard let itemToOverflow = visiblePinnedItems.last else {
                break
            }
            updateNavBarViews(with: itemToOverflow, isHidden: true)
        }
    }

    private func removeButtonsFromOverflowMenuIfPossible() {
        while let itemToRestore = overflowItems.first {
            let restorableButtonWidth = navBarWidth(for: itemToRestore)
            let newMaximumWidth = visiblePinnedViewsRequiredWidth + restorableButtonWidth

            if newMaximumWidth < overflowThreshold {
                updateNavBarViews(with: itemToRestore, isHidden: false)
            } else {
                break
            }
        }
    }

    /// Checks whether a pinned view is visible in the navigation bar
    func isVisibleInNavBar(_ viewType: PinnableView) -> Bool {
        navBarButtonViews(for: viewType).contains { !$0.isHidden }
    }

    /// Returns the width of any navigation bar views related to the provided pinned view
    func navBarWidth(for viewType: PinnableView) -> CGFloat {
        navBarButtonViews(for: viewType).map(\.bounds.width).reduce(0, +)
    }

    /// Moves the provided pinned view between the nav bar and overflow menu.
    /// When `isHidden` is `true`, the view is moved from the nav bar to the overflow menu, and vice versa.
    private func updateNavBarViews(with pinnedView: PinnableView, isHidden: Bool) {
        for view in navBarButtonViews(for: pinnedView) {
            view.isHidden = isHidden
        }
        updateOverflowMenu()
    }

    private func toggleAIChatButtonVisibility(isHidden: Bool) {
        guard let addressBarButtonsViewController = addressBarViewController?.addressBarButtonsViewController, isAIChatButtonInOverflowMenu != isHidden else {
            return
        }
        addressBarButtonsViewController.updateAIChatButtonVisibility(isHidden: isHidden)
        isAIChatButtonInOverflowMenu = isHidden
        updateOverflowMenu()
    }

    /// Updates the overflow menu with the expected menu items, and shows/hides the overflow button as needed.
    private func updateOverflowMenu() {
        overflowButton.menu?.removeAllItems()
        if overflowItems.isEmpty {
            overflowButton.isHidden = true
        } else {
            for item in overflowItems {
                let menuItem = overflowMenuItem(for: item, style: visualStyle)
                overflowButton.menu?.addItem(menuItem)
            }
            if isAIChatButtonInOverflowMenu {
                let aiChatItem = NSMenuItem(title: UserText.aiChatAddressBarTooltip, action: #selector(overflowMenuRequestedAIChat), keyEquivalent: "")
                    .targetting(self)
                    .withImage(.aiChat)
                overflowButton.menu?.addItem(aiChatItem)
            }
            overflowButton.isHidden = false
        }
    }

    /// Provides the views to display in the navigation bar for a given pinned view.
    private func navBarButtonViews(for view: PinnableView) -> [NSView] {
        switch view {
        case .autofill:
            return [passwordManagementButton]
        case .bookmarks:
            return [bookmarkListButton]
        case .downloads:
            return [downloadsButton]
        case .homeButton where Self.homeButtonPosition == .left:
            return [homeButton, homeButtonSeparator]
        case .homeButton:
            return [homeButton]
        case .networkProtection:
            return [networkProtectionButton]
        }
    }

    /// Provides the menu items to display in the overflow menu for a given pinned view.
    private func overflowMenuItem(for view: PinnableView,
                                  style: VisualStyleProviding) -> NSMenuItem {
        switch view {
        case .autofill:
            return NSMenuItem(title: UserText.autofill, action: #selector(overflowMenuRequestedLoginsPopover), keyEquivalent: "")
                .targetting(self)
                .withImage(style.iconsProvider.navigationToolbarIconsProvider.passwordManagerButtonImage)
        case .bookmarks:
            return NSMenuItem(title: UserText.bookmarks, action: #selector(overflowMenuRequestedBookmarkPopover), keyEquivalent: "")
                .targetting(self)
                .withImage(style.iconsProvider.navigationToolbarIconsProvider.bookmarksButtonImage)
        case .downloads:
            return NSMenuItem(title: UserText.downloads, action: #selector(overflowMenuRequestedDownloadsPopover), keyEquivalent: "")
                .targetting(self)
                .withImage(style.iconsProvider.navigationToolbarIconsProvider.downloadsButtonImage)
        case .homeButton:
            return NSMenuItem(title: UserText.homeButtonTooltip, action: #selector(overflowMenuRequestedHomeButton), keyEquivalent: "")
                .targetting(self)
                .withImage(style.iconsProvider.navigationToolbarIconsProvider.homeButtonImage)
        case .networkProtection:
            return NSMenuItem(title: UserText.networkProtection, action: #selector(overflowMenuRequestedNetworkProtectionPopover), keyEquivalent: "")
                .targetting(self)
                .withImage(networkProtectionButton.image)
        }
    }

    /// Moves the next pinned view into the overflow menu, to make space to show the provided pinned view.
    /// This is used to ensure there is space to show a pinned view in the nav bar when it is selected from the overflow menu.
    private func makeSpaceInNavBarIfNeeded(for view: PinnableView) {
        guard visiblePinnedViewsRequiredWidth + navBarWidth(for: view) > overflowThreshold else {
            return
        }

        guard let itemToOverflow = visiblePinnedItems.last else {
            return
        }
        updateNavBarViews(with: itemToOverflow, isHidden: true)
    }

    @objc
    func overflowMenuRequestedLoginsPopover(_ menu: NSMenu) {
        makeSpaceInNavBarIfNeeded(for: .autofill)
        updateNavBarViews(with: .autofill, isHidden: false)
        popovers.showPasswordManagementPopover(selectedCategory: nil, from: passwordManagementButton, withDelegate: self, source: .overflow)
    }

    @objc
    func overflowMenuRequestedBookmarkPopover(_ menu: NSMenu) {
        makeSpaceInNavBarIfNeeded(for: .bookmarks)
        updateNavBarViews(with: .bookmarks, isHidden: false)
        popovers.showBookmarkListPopover(from: bookmarkListButton, withDelegate: self, forTab: tabCollectionViewModel.selectedTabViewModel?.tab)
    }

    @objc
    func overflowMenuRequestedNetworkProtectionPopover(_ menu: NSMenu) {
        makeSpaceInNavBarIfNeeded(for: .networkProtection)
        updateNavBarViews(with: .networkProtection, isHidden: false)
        toggleNetworkProtectionPopover()
    }

    @objc
    func overflowMenuRequestedHomeButton(_ menu: NSMenu) {
        guard let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel else {
            Logger.navigation.error("Selected tab view model is nil")
            return
        }
        selectedTabViewModel.tab.openHomePage()
    }

    @objc
    func overflowMenuRequestedDownloadsPopover(_ menu: NSMenu) {
        makeSpaceInNavBarIfNeeded(for: .downloads)
        updateNavBarViews(with: .downloads, isHidden: false)
        toggleDownloadsPopover(keepButtonVisible: true)
    }

    @objc
    func overflowMenuRequestedAIChat(_ menu: NSMenu) {
        addressBarViewController?.addressBarButtonsViewController?.aiChatButtonAction(menu)
    }
}

extension NavigationBarViewController: NSMenuDelegate {

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        BookmarksBarMenuFactory.addToMenu(menu, prefs: NSApp.delegateTyped.appearancePreferences)

        menu.addItem(NSMenuItem.separator())

        HomeButtonMenuFactory.addToMenu(menu, prefs: NSApp.delegateTyped.appearancePreferences)

        let autofillTitle = LocalPinningManager.shared.shortcutTitle(for: .autofill)
        menu.addItem(withTitle: autofillTitle, action: #selector(toggleAutofillPanelPinning), keyEquivalent: "A")

        let bookmarksTitle = LocalPinningManager.shared.shortcutTitle(for: .bookmarks)
        menu.addItem(withTitle: bookmarksTitle, action: #selector(toggleBookmarksPanelPinning), keyEquivalent: "K")

        let downloadsTitle = LocalPinningManager.shared.shortcutTitle(for: .downloads)
        menu.addItem(withTitle: downloadsTitle, action: #selector(toggleDownloadsPanelPinning), keyEquivalent: "J")

        let isPopUpWindow = view.window?.isPopUpWindow ?? false

        if !isPopUpWindow && DefaultVPNFeatureGatekeeper(subscriptionManager: subscriptionManager).isVPNVisible() {
            let networkProtectionTitle = LocalPinningManager.shared.shortcutTitle(for: .networkProtection)
            menu.addItem(withTitle: networkProtectionTitle, action: #selector(toggleNetworkProtectionPanelPinning), keyEquivalent: "")
        }
    }

    @objc
    private func toggleAutofillPanelPinning(_ sender: NSMenuItem) {
        LocalPinningManager.shared.togglePinning(for: .autofill)
    }

    @objc
    private func toggleBookmarksPanelPinning(_ sender: NSMenuItem) {
        LocalPinningManager.shared.togglePinning(for: .bookmarks)
    }

    @objc
    private func toggleDownloadsPanelPinning(_ sender: NSMenuItem) {
        LocalPinningManager.shared.togglePinning(for: .downloads)
    }

    @objc
    private func toggleNetworkProtectionPanelPinning(_ sender: NSMenuItem) {
        LocalPinningManager.shared.togglePinning(for: .networkProtection)
    }

    // MARK: - VPN

    func showNetworkProtectionStatus() {
        popovers.showNetworkProtectionPopover(positionedBelow: networkProtectionButton,
                                              withDelegate: networkProtectionButtonModel)
    }

    /// Sets up the VPN button.
    ///
    /// This method should be run just once during the lifecycle of this view.
    /// .
    private func setupNetworkProtectionButton() {
        assert(networkProtectionButton.menu == nil)

        let menuItem = NSMenuItem(title: LocalPinningManager.shared.shortcutTitle(for: .networkProtection), action: #selector(toggleNetworkProtectionPanelPinning), target: self)
        let menu = NSMenu(items: [menuItem])
        networkProtectionButton.menu = menu

        networkProtectionButtonModel.$shortcutTitle
            .receive(on: RunLoop.main)
            .sink { title in
                menuItem.title = title
            }
            .store(in: &cancellables)

        networkProtectionButtonModel.$showVPNButton
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                let isPopUpWindow = self?.view.window?.isPopUpWindow ?? false
                self?.networkProtectionButton.isHidden = isPopUpWindow || !show
            }
            .store(in: &cancellables)

        networkProtectionButtonModel.$buttonImage
            .receive(on: RunLoop.main)
            .sink { [weak self] image in
                self?.networkProtectionButton.image = image
            }
            .store(in: &cancellables)
    }

}

extension NavigationBarViewController: OptionsButtonMenuDelegate {

    func optionsButtonMenuRequestedDataBrokerProtection(_ menu: NSMenu) {
        Application.appDelegate.windowControllersManager.showDataBrokerProtectionTab()
    }

    func optionsButtonMenuRequestedOpenExternalPasswordManager(_ menu: NSMenu) {
        BWManager.shared.openBitwarden()
    }

    func optionsButtonMenuRequestedBookmarkThisPage(_ sender: NSMenuItem) {
        addressBarViewController?
            .addressBarButtonsViewController?
            .openBookmarkPopover(setFavorite: false, accessPoint: .init(sender: sender, default: .moreMenu))
    }

    func optionsButtonMenuRequestedBookmarkAllOpenTabs(_ sender: NSMenuItem) {
        let websitesInfo = tabCollectionViewModel.tabs.compactMap(WebsiteInfo.init)
        BookmarksDialogViewFactory.makeBookmarkAllOpenTabsView(websitesInfo: websitesInfo, bookmarkManager: bookmarkManager).show()
    }

    func optionsButtonMenuRequestedBookmarkPopover(_ menu: NSMenu) {
        popovers.showBookmarkListPopover(from: bookmarkListButton, withDelegate: self, forTab: tabCollectionViewModel.selectedTabViewModel?.tab)
    }

    func optionsButtonMenuRequestedBookmarkManagementInterface(_ menu: NSMenu) {
        Application.appDelegate.windowControllersManager.showBookmarksTab()
    }

    func optionsButtonMenuRequestedBookmarkImportInterface(_ menu: NSMenu) {
        DataImportView().show()
    }

    func optionsButtonMenuRequestedBookmarkExportInterface(_ menu: NSMenu) {
        NSApp.sendAction(#selector(AppDelegate.openExportBookmarks(_:)), to: nil, from: nil)
    }

    func optionsButtonMenuRequestedLoginsPopover(_ menu: NSMenu, selectedCategory: SecureVaultSorting.Category) {
        popovers.showPasswordManagementPopover(selectedCategory: selectedCategory, from: passwordManagementButton, withDelegate: self, source: .overflow)
    }

    func optionsButtonMenuRequestedNetworkProtectionPopover(_ menu: NSMenu) {
        toggleNetworkProtectionPopover()
    }

    func optionsButtonMenuRequestedDownloadsPopover(_ menu: NSMenu) {
        toggleDownloadsPopover(keepButtonVisible: true)
    }

    func optionsButtonMenuRequestedPrint(_ menu: NSMenu) {
        Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController.printWebView(self)
    }

    func optionsButtonMenuRequestedPreferences(_ menu: NSMenu) {
        Application.appDelegate.windowControllersManager.showPreferencesTab()
    }

    func optionsButtonMenuRequestedAppearancePreferences(_ menu: NSMenu) {
        Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .appearance)
    }

    func optionsButtonMenuRequestedAccessibilityPreferences(_ menu: NSMenu) {
        Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .accessibility)
    }

    func optionsButtonMenuRequestedSubscriptionPurchasePage(_ menu: NSMenu) {
        let url = subscriptionManager.url(for: .purchase)
        Application.appDelegate.windowControllersManager.showTab(with: .subscription(url.appendingParameter(name: AttributionParameter.origin, value: SubscriptionFunnelOrigin.appMenu.rawValue)))
        PixelKit.fire(PrivacyProPixel.privacyProOfferScreenImpression)
    }

    func optionsButtonMenuRequestedSubscriptionPreferences(_ menu: NSMenu) {
        Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .subscriptionSettings)
    }

    func optionsButtonMenuRequestedIdentityTheftRestoration(_ menu: NSMenu) {
        let url = subscriptionManager.url(for: .identityTheftRestoration)
        Application.appDelegate.windowControllersManager.showTab(with: .identityTheftRestoration(url))
    }
}

// MARK: - NSPopoverDelegate

extension NavigationBarViewController: NSPopoverDelegate {

    /// We check references here because these popovers might be on other windows.
    func popoverDidClose(_ notification: Notification) {
        guard view.window?.isVisible == true else { return }
        if let popover = popovers.downloadsPopover, notification.object as AnyObject? === popover {
            popovers.downloadsPopoverClosed()
            updateDownloadsButton(source: .popoverDidClose)
        } else if let popover = popovers.bookmarkListPopover, notification.object as AnyObject? === popover {
            popovers.bookmarkListPopoverClosed()
            updateBookmarksButton()
        } else if let popover = popovers.saveIdentityPopover, notification.object as AnyObject? === popover {
            popovers.saveIdentityPopoverClosed()
            updatePasswordManagementButton()
        } else if let popover = popovers.saveCredentialsPopover, notification.object as AnyObject? === popover {
            popovers.saveCredentialsPopoverClosed()
            updatePasswordManagementButton()
        } else if let popover = popovers.savePaymentMethodPopover, notification.object as AnyObject? === popover {
            popovers.savePaymentMethodPopoverClosed()
            updatePasswordManagementButton()
        } else if let popover = popovers.autofillOnboardingPopover, notification.object as AnyObject? === popover {
            popovers.autofillOnboardingPopoverClosed()
            updatePasswordManagementButton()
        }
    }
}

extension NavigationBarViewController: DownloadsViewControllerDelegate {

    func clearDownloadsActionTriggered() {
        invalidateDownloadButtonHidingTimer()
        hideDownloadButtonIfPossible()
    }

}

extension NavigationBarViewController: MouseOverButtonDelegate {

    func mouseOverButton(_ sender: MouseOverButton, draggingEntered info: any NSDraggingInfo, isMouseOver: UnsafeMutablePointer<Bool>) -> NSDragOperation {
        guard sender === bookmarkListButton else { return .none }
        let operation = bookmarkDragDropManager.validateDrop(info, to: PseudoFolder.bookmarks)
        isMouseOver.pointee = (operation != .none)
        return operation
    }

    func mouseOverButton(_ sender: MouseOverButton, draggingUpdatedWith info: any NSDraggingInfo, isMouseOver: UnsafeMutablePointer<Bool>) -> NSDragOperation {
        guard sender === bookmarkListButton else { return .none }
        cursorDraggedOverBookmarkListButton(with: info)

        let operation = bookmarkDragDropManager.validateDrop(info, to: PseudoFolder.bookmarks)
        isMouseOver.pointee = (operation != .none)
        return operation
    }

    private func cursorDraggedOverBookmarkListButton(with info: any NSDraggingInfo) {
        guard !popovers.bookmarkListPopoverShown else { return }
        let cursorPosition = info.draggingLocation

        // show folder bookmarks menu after 0.3
        if let dragDestination,
           dragDestination.mouseLocation.distance(to: cursorPosition) < Constants.maxDragDistanceToExpandHoveredFolder {

            if Date().timeIntervalSince(dragDestination.hoverStarted) >= Constants.dragOverFolderExpandDelay {
                popovers.showBookmarkListPopover(from: bookmarkListButton, withDelegate: self, forTab: tabCollectionViewModel.selectedTabViewModel?.tab)
            }
        } else {
            self.dragDestination = (mouseLocation: cursorPosition, hoverStarted: Date())
        }
    }

}

extension NavigationBarViewController: AddressBarViewControllerDelegate {

    func resizeAddressBarForHomePage(_ addressBarViewController: AddressBarViewController) {
        let addressBarSizeClass: AddressBarSizeClass = tabCollectionViewModel.selectedTabViewModel?.tab.content == .newtab ? .homePage : .default

        if visualStyle.addressBarStyleProvider.shouldShowNewSearchIcon {
            resizeAddressBar(for: addressBarSizeClass, animated: false)
        }
    }
}

#if DEBUG || REVIEW
extension NavigationBarViewController {

    fileprivate func addDebugNotificationListeners() {
        NotificationCenter.default.publisher(for: .ShowSaveCredentialsPopover)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showMockSaveCredentialsPopover()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ShowCredentialsSavedPopover)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showMockCredentialsSavedPopover()
            }
            .store(in: &cancellables)
    }

    fileprivate func showMockSaveCredentialsPopover() {
        let account = SecureVaultModels.WebsiteAccount(title: nil, username: "example-username", domain: "example.com")
        let mockCredentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)

        popovers.displaySaveCredentials(mockCredentials,
                                        automaticallySaved: false,
                                        backfilled: false,
                                        usingView: passwordManagementButton,
                                        withDelegate: self)
    }

    fileprivate func showMockCredentialsSavedPopover() {
        let account = SecureVaultModels.WebsiteAccount(title: nil, username: "example-username", domain: "example.com")
        let mockCredentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)

        popovers.displaySaveCredentials(mockCredentials,
                                        automaticallySaved: true,
                                        backfilled: false,
                                        usingView: passwordManagementButton,
                                        withDelegate: self)
    }

}
#endif

extension Notification.Name {
    static let ToggleNetworkProtectionInMainWindow = Notification.Name("com.duckduckgo.vpn.toggle-popover-in-main-window")
    static let OpenUnifiedFeedbackForm = Notification.Name("com.duckduckgo.subscription.open-unified-feedback-form")
}
