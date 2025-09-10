//
//  MainViewController.swift
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
import WebKit
import WidgetKit
import Combine
import Common
import Core
import DDGSync
import Kingfisher
import BrowserServicesKit
import Bookmarks
import Persistence
import PrivacyDashboard
import Networking
import Suggestions
import Subscription
import SwiftUI
import VPN
import Onboarding
import os.log
import PageRefreshMonitor
import BrokenSitePrompt
import AIChat
import NetworkExtension
import DesignResourcesKit
import DesignResourcesKitIcons
import Configuration
import PixelKit
import SystemSettingsPiPTutorial
import DataBrokerProtection_iOS

class MainViewController: UIViewController {

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.shared.currentTheme.statusBarStyle
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        return isIPad ? [.left, .right] : []
    }

    weak var findInPageView: FindInPageView!
    weak var findInPageHeightLayoutConstraint: NSLayoutConstraint!
    weak var findInPageBottomLayoutConstraint: NSLayoutConstraint!

    weak var notificationView: UIView?

    var chromeManager: BrowserChromeManager!

    var allowContentUnderflow = false {
        didSet {
            viewCoordinator.constraints.contentContainerTop.constant = allowContentUnderflow ? contentUnderflow : 0
        }
    }

    var contentUnderflow: CGFloat {
        return 3 + (allowContentUnderflow ? -viewCoordinator.navigationBarContainer.frame.size.height : 0)
    }

    var isShowingAutocompleteSuggestions: Bool {
        suggestionTrayController?.isShowingAutocompleteSuggestions == true
    }

    lazy var emailManager: EmailManager = {
        let emailManager = EmailManager()
        emailManager.aliasPermissionDelegate = self
        emailManager.requestDelegate = self
        return emailManager
    }()

    var newTabPageViewController: NewTabPageViewController?
    var tabsBarController: TabsBarViewController?
    var suggestionTrayController: SuggestionTrayViewController?

    let homePageConfiguration: HomePageConfiguration
    let tabManager: TabManager
    let previewsSource: TabPreviewsSource
    let appSettings: AppSettings
    private var launchTabObserver: LaunchTabNotification.Observer?
    var isNewTabPageVisible: Bool {
        newTabPageViewController != nil
    }

    var autoClearInProgress = false
    var autoClearShouldRefreshUIAfterClear = true

    let bookmarksDatabase: CoreDataDatabase
    private weak var bookmarksDatabaseCleaner: BookmarkDatabaseCleaner?
    private var favoritesViewModel: FavoritesListInteracting
    let syncService: DDGSyncing
    let syncDataProviders: SyncDataProviders
    let syncPausedStateManager: any SyncPausedStateManaging
    private let tutorialSettings: TutorialSettings
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    let contextualOnboardingPixelReporter: OnboardingPixelReporting
    private let statisticsStore: StatisticsStore
    let voiceSearchHelper: VoiceSearchHelperProtocol
    let featureFlagger: FeatureFlagger

    @UserDefaultsWrapper(key: .syncDidShowSyncPausedByFeatureFlagAlert, defaultValue: false)
    private var syncDidShowSyncPausedByFeatureFlagAlert: Bool

    @UserDefaultsWrapper(key: .hadVPNEntitlements, defaultValue: false)
    private var hadVPNEntitlements: Bool

    private var localUpdatesCancellable: AnyCancellable?
    private var syncUpdatesCancellable: AnyCancellable?
    private var syncFeatureFlagsCancellable: AnyCancellable?
    private var favoritesDisplayModeCancellable: AnyCancellable?
    private var emailCancellables = Set<AnyCancellable>()
    private var urlInterceptorCancellables = Set<AnyCancellable>()
    private var settingsDeepLinkcancellables = Set<AnyCancellable>()
    private let tunnelDefaults = UserDefaults.networkProtectionGroupDefaults
    private var vpnCancellables = Set<AnyCancellable>()
    private var feedbackCancellable: AnyCancellable?
    private var aiChatCancellables = Set<AnyCancellable>()
    private var refreshButtonCancellables = Set<AnyCancellable>()

    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    let privacyProDataReporter: PrivacyProDataReporting

    let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    private lazy var faviconLoader: FavoritesFaviconLoading = FavoritesFaviconLoader()
    private lazy var faviconsFetcherOnboarding = FaviconsFetcherOnboarding(syncService: syncService, syncBookmarksAdapter: syncDataProviders.bookmarksAdapter)

    lazy var menuBookmarksViewModel: MenuBookmarksInteracting = {
        let viewModel = MenuBookmarksViewModel(bookmarksDatabase: bookmarksDatabase, syncService: syncService)
        viewModel.favoritesDisplayMode = appSettings.favoritesDisplayMode
        return viewModel
    }()

    weak var tabSwitcherController: TabSwitcherViewController?
    var tabSwitcherButton: TabSwitcherButton?

    /// Do not reference directly, use `presentedMenuButton`
    let menuButton = MenuButton()
    var presentedMenuButton: MenuButton {
        AppWidthObserver.shared.isLargeWidth ? viewCoordinator.omniBar.barView.menuButtonContent : menuButton
    }

    let gestureBookmarksButton = GestureToolbarButton()

    private lazy var fireButtonAnimator: FireButtonAnimator = FireButtonAnimator(appSettings: appSettings)

    let bookmarksCachingSearch: BookmarksCachingSearch

    lazy var tabSwitcherTransition = TabSwitcherTransitionDelegate()
    var currentTab: TabViewController? {
        return tabManager.current(createIfNeeded: false)
    }

    var searchBarRect: CGRect {
        let view = UIApplication.shared.firstKeyWindow?.rootViewController?.view
        return viewCoordinator.omniBar.barView.searchContainer.convert(viewCoordinator.omniBar.barView.searchContainer.bounds, to: view)
    }

    var keyModifierFlags: UIKeyModifierFlags?
    var showKeyboardAfterFireButton: DispatchWorkItem?

    // Skip SERP flow (focusing on autocomplete logic) and prepare for new navigation when selecting search bar
    private var skipSERPFlow = true

    var postClear: (() -> Void)?
    var clearInProgress = false
    var dataStoreWarmup: DataStoreWarmup? = DataStoreWarmup()

    required init?(coder: NSCoder) {
        fatalError("Use init?(code:")
    }

    let featureDiscovery: FeatureDiscovery
    let fireproofing: Fireproofing
    let websiteDataManager: WebsiteDataManaging
    let textZoomCoordinator: TextZoomCoordinating

    var historyManager: HistoryManaging
    var viewCoordinator: MainViewCoordinator!
    let aiChatSettings: AIChatSettingsProvider
    

    let customConfigurationURLProvider: CustomConfigurationURLProviding
    let experimentalAIChatManager: ExperimentalAIChatManager
    let daxDialogsManager: DaxDialogsManaging
    let dbpIOSPublicInterface: DBPIOSInterface.PublicInterface?

    var appDidFinishLaunchingStartTime: CFAbsoluteTime?
    let maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging
    private lazy var themeColorManager: SiteThemeColorManager = {
        SiteThemeColorManager(viewCoordinator: viewCoordinator,
                              currentTabViewController: { [weak self] in self?.currentTab }(),
                              appSettings: appSettings,
                              themeManager: themeManager)
    }()

    private lazy var aiChatViewControllerManager: AIChatViewControllerManager = {
        let manager = AIChatViewControllerManager(experimentalAIChatManager: .init(featureFlagger: featureFlagger),
                                                  featureFlagger: featureFlagger,
                                                  aiChatSettings: aiChatSettings)
        manager.delegate = self
        return manager
    }()

    private lazy var omnibarAccessoryHandler: OmnibarAccessoryHandler = {
        let settings = AIChatSettings(privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)

        return OmnibarAccessoryHandler(settings: settings)
    }()

    let isAuthV2Enabled: Bool
    let themeManager: ThemeManaging
    let keyValueStore: ThrowingKeyValueStoring
    let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging

    private var duckPlayerEntryPointVisible = false
    private var subscriptionManager = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge
    
    private let daxEasterEggPresenter: DaxEasterEggPresenting

    private let internalUserCommands: URLBasedDebugCommands = InternalUserCommands()
    private let launchSourceManager: LaunchSourceManaging

    init(
        bookmarksDatabase: CoreDataDatabase,
        bookmarksDatabaseCleaner: BookmarkDatabaseCleaner,
        historyManager: HistoryManaging,
        homePageConfiguration: HomePageConfiguration,
        syncService: DDGSyncing,
        syncDataProviders: SyncDataProviders,
        appSettings: AppSettings,
        previewsSource: TabPreviewsSource,
        tabManager: TabManager,
        syncPausedStateManager: any SyncPausedStateManaging,
        privacyProDataReporter: PrivacyProDataReporting,
        contextualOnboardingLogic: ContextualOnboardingLogic,
        contextualOnboardingPixelReporter: OnboardingPixelReporting,
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
        voiceSearchHelper: VoiceSearchHelperProtocol,
        featureFlagger: FeatureFlagger,
        contentScopeExperimentsManager: ContentScopeExperimentsManaging,
        fireproofing: Fireproofing,
        textZoomCoordinator: TextZoomCoordinating,
        websiteDataManager: WebsiteDataManaging,
        appDidFinishLaunchingStartTime: CFAbsoluteTime?,
        maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging,
        aiChatSettings: AIChatSettingsProvider,
        experimentalAIChatManager: ExperimentalAIChatManager = ExperimentalAIChatManager(),
        featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
        themeManager: ThemeManaging,
        keyValueStore: ThrowingKeyValueStoring,
        customConfigurationURLProvider: CustomConfigurationURLProviding,
        systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
        daxDialogsManager: DaxDialogsManaging,
        daxEasterEggPresenter: DaxEasterEggPresenting = DaxEasterEggPresenter(),
        dbpIOSPublicInterface: DBPIOSInterface.PublicInterface?,
        launchSourceManager: LaunchSourceManaging
    ) {
        self.bookmarksDatabase = bookmarksDatabase
        self.bookmarksDatabaseCleaner = bookmarksDatabaseCleaner
        self.historyManager = historyManager
        self.homePageConfiguration = homePageConfiguration
        self.syncService = syncService
        self.syncDataProviders = syncDataProviders
        self.favoritesViewModel = FavoritesListViewModel(bookmarksDatabase: bookmarksDatabase, favoritesDisplayMode: appSettings.favoritesDisplayMode)
        self.bookmarksCachingSearch = BookmarksCachingSearch(bookmarksStore: CoreDataBookmarksSearchStore(bookmarksStore: bookmarksDatabase))
        self.appSettings = appSettings
        self.aiChatSettings = aiChatSettings
        self.experimentalAIChatManager = experimentalAIChatManager
        self.previewsSource = previewsSource
        self.tabManager = tabManager
        self.featureDiscovery = featureDiscovery
        self.themeManager = themeManager
        self.syncPausedStateManager = syncPausedStateManager
        self.privacyProDataReporter = privacyProDataReporter
        self.tutorialSettings = tutorialSettings
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.contextualOnboardingPixelReporter = contextualOnboardingPixelReporter
        self.statisticsStore = statisticsStore
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.voiceSearchHelper = voiceSearchHelper
        self.featureFlagger = featureFlagger
        self.fireproofing = fireproofing
        self.textZoomCoordinator = textZoomCoordinator
        self.websiteDataManager = websiteDataManager
        self.appDidFinishLaunchingStartTime = appDidFinishLaunchingStartTime
        self.maliciousSiteProtectionPreferencesManager = maliciousSiteProtectionPreferencesManager
        self.contentScopeExperimentsManager = contentScopeExperimentsManager
        self.isAuthV2Enabled = AppDependencyProvider.shared.isUsingAuthV2
        self.keyValueStore = keyValueStore
        self.customConfigurationURLProvider = customConfigurationURLProvider
        self.systemSettingsPiPTutorialManager = systemSettingsPiPTutorialManager
        self.daxDialogsManager = daxDialogsManager
        self.daxEasterEggPresenter = daxEasterEggPresenter
        self.dbpIOSPublicInterface = dbpIOSPublicInterface
        self.launchSourceManager = launchSourceManager
        super.init(nibName: nil, bundle: nil)
        
        tabManager.delegate = self
        bindSyncService()
    }

    func loadFindInPage() {

        let view = FindInPageView.loadFromXib()
        self.view.addSubview(view)
        
        // Avoids coercion swiftlint warnings
        let superview = self.view!
        
        let height = view.constrainAttribute(.height, to: view.frame.height)
        let bottom = superview.constrainView(view, by: .bottom, to: .bottom)
        
        NSLayoutConstraint.activate([
            bottom,
            superview.constrainView(view, by: .width, to: .width),
            height,
            superview.constrainView(view, by: .centerX, to: .centerX)
        ])
        
        findInPageView = view
        findInPageBottomLayoutConstraint = bottom
        findInPageHeightLayoutConstraint = height
    }
    
    var swipeTabsCoordinator: SwipeTabsCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()

        let newTabDaxDialogFactory = NewTabDaxDialogFactory(delegate: self, daxDialogsFlowCoordinator: daxDialogsManager, onboardingPixelReporter: contextualOnboardingPixelReporter)

        let newTabPageDependencies = SuggestionTrayViewController.NewTabPageDependencies(favoritesModel: favoritesViewModel,
                                                                                         homePageMessagesConfiguration: homePageConfiguration,
                                                                                         privacyProDataReporting: privacyProDataReporter,
                                                                                         newTabDialogFactory: newTabDaxDialogFactory,
                                                                                         newTabDaxDialogManager: daxDialogsManager,
                                                                                         faviconLoader: faviconLoader,
                                                                                         messageNavigationDelegate: self,
                                                                                         appSettings: appSettings,
                                                                                         internalUserCommands: internalUserCommands)

        let suggestionTrayDependencies = SuggestionTrayDependencies(favoritesViewModel: favoritesViewModel,
                                                                    bookmarksDatabase: bookmarksDatabase,
                                                                    historyManager: historyManager,
                                                                    tabsModel: tabManager.model,
                                                                    featureFlagger: featureFlagger,
                                                                    appSettings: appSettings,
                                                                    aiChatSettings: aiChatSettings,
                                                                    featureDiscovery: featureDiscovery,
                                                                    newTabPageDependencies: newTabPageDependencies)

        viewCoordinator = MainViewFactory.createViewHierarchy(self,
                                                              aiChatSettings: aiChatSettings,
                                                              voiceSearchHelper: voiceSearchHelper,
                                                              featureFlagger: featureFlagger,
                                                              suggestionTrayDependencies: suggestionTrayDependencies,
                                                              appSettings: appSettings)

        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)

        setUpToolbarButtonsActions()
        installSwipeTabs()
            
        loadSuggestionTray()
        loadTabsBarIfNeeded()
        loadFindInPage()
        attachOmniBar()

        view.addInteraction(UIDropInteraction(delegate: self))
        
        chromeManager = BrowserChromeManager()
        chromeManager.delegate = self
        initTabButton()
        initBookmarksButton()
        loadInitialView()
        previewsSource.prepare()
        addLaunchTabNotificationObserver()
        subscribeToEmailProtectionStatusNotifications()
        subscribeToURLInterceptorNotifications()
        subscribeToSettingsDeeplinkNotifications()
        subscribeToNetworkProtectionEvents()
        subscribeToUnifiedFeedbackNotifications()
        subscribeToAIChatSettingsEvents()
        subscribeToRefreshButtonSettingsEvents()

        checkSubscriptionEntitlements()

        findInPageView.delegate = self
        findInPageBottomLayoutConstraint.constant = 0
        registerForKeyboardNotifications()
        registerForPageRefreshPatterns()
        registerForSyncFeatureFlagsUpdates()

        decorate()

        swipeTabsCoordinator?.refresh(tabsModel: tabManager.model, scrollToSelected: true)

        _ = AppWidthObserver.shared.willResize(toWidth: view.frame.width)
        applyWidth()
        
        registerForApplicationEvents()
        registerForCookiesManagedNotification()
        registerForSettingsChangeNotifications()

        tabManager.cleanupTabsFaviconCache()

        // Needs to be called here to established correct view hierarchy
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        defer {
            if let appDidFinishLaunchingStartTime {
                let launchTime = CFAbsoluteTimeGetCurrent() - appDidFinishLaunchingStartTime
                Pixel.fire(pixel: .appDidShowUITime(time: Pixel.Event.BucketAggregation(number: launchTime)),
                           withAdditionalParameters: [PixelParameters.time: String(launchTime)])
                self.appDidFinishLaunchingStartTime = nil /// We only want this pixel to be fired once
            }
        }

        // Always hide this, we use StyledTopBottomBorderView where needed instead
        viewCoordinator.hideToolbarSeparator()

        // Needs to be called here because sometimes the frames are not the expected size during didLoad
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)

        startOnboardingFlowIfNotSeenBefore()
        tabsBarController?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.model, scrollToSelected: true)

        _ = AppWidthObserver.shared.willResize(toWidth: view.frame.width)
        applyWidth()

        if daxDialogsManager.shouldShowFireButtonPulse {
            showFireButtonPulse()
        }

        presentNewAddressBarPickerIfNeeded()
    }

    override func performSegue(withIdentifier identifier: String, sender: Any?) {
        assertionFailure()
        super.performSegue(withIdentifier: identifier, sender: sender)
    }

    private func fireExperimentalAddressBarPixel() {
        let isEnabledParam = "is_enabled"
        let isEnableValue = "\(aiChatSettings.isAIChatSearchInputUserSettingsEnabled)"

        DailyPixel.fireDaily(.aiChatExperimentalAddressBarIsEnabledDaily,
                             withAdditionalParameters: [isEnabledParam: isEnableValue])
        
    }
    
    private func fireKeyboardSettingsPixels() {
        let keyboardSettings = KeyboardSettings()
        let isEnabledParam = "is_enabled"
        
        let onNewTabValue = "\(keyboardSettings.onNewTab)"
        DailyPixel.fireDaily(.keyboardSettingsOnNewTabEnabledDaily,
                             withAdditionalParameters: [isEnabledParam: onNewTabValue])
        
        let onAppLaunchValue = "\(keyboardSettings.onAppLaunch)"
        DailyPixel.fireDaily(.keyboardSettingsOnAppLaunchEnabledDaily,
                             withAdditionalParameters: [isEnabledParam: onAppLaunchValue])
    }

    private func installSwipeTabs() {
        guard swipeTabsCoordinator == nil else { return }

        let omnibarDependencies = OmnibarDependencies(voiceSearchHelper: voiceSearchHelper,
                                                      featureFlagger: featureFlagger,
                                                      aiChatSettings: aiChatSettings,
                                                      appSettings: appSettings,
                                                      daxEasterEggPresenter: daxEasterEggPresenter)

        swipeTabsCoordinator = SwipeTabsCoordinator(coordinator: viewCoordinator,
                                                    tabPreviewsSource: previewsSource,
                                                    appSettings: appSettings,
                                                    omnibarDependencies: omnibarDependencies,
                                                    omnibarAccessoryHandler: omnibarAccessoryHandler) { [weak self] in

            guard $0 != self?.tabManager.model.currentIndex else { return }
            
            DailyPixel.fire(pixel: .swipeTabsUsedDaily)
            self?.select(tabAt: $0)
            
        } newTab: { [weak self] in
            Pixel.fire(pixel: .swipeToOpenNewTab)
            self?.newTab()
        } onSwipeStarted: { [weak self] in
            self?.performCancel()
            self?.hideKeyboard()
            self?.updatePreviewForCurrentTab()
        }
    }

    func updatePreviewForCurrentTab(completion: (() -> Void)? = nil) {
        assert(Thread.isMainThread)
        
        if !viewCoordinator.logoContainer.isHidden,
           self.tabManager.current()?.link == nil,
           let tab = self.tabManager.model.currentTab {
            // Home screen with logo
            if let image = viewCoordinator.logoContainer.createImageSnapshot(inBounds: viewCoordinator.contentContainer.frame) {
                previewsSource.update(preview: image, forTab: tab)
                completion?()
            }

        } else if let currentTab = self.tabManager.current(), currentTab.link != nil {
            // Web view
            currentTab.preparePreview(completion: { image in
                guard let image else { return }
                self.previewsSource.update(preview: image,
                                           forTab: currentTab.tabModel)
                completion?()
            })
        } else if let tab = self.tabManager.model.currentTab {
            // Favorites, etc
            if let image = viewCoordinator.contentContainer.createImageSnapshot() {
                previewsSource.update(preview: image, forTab: tab)
                completion?()
            }
        } else {
            completion?()
        }
    }

    func loadSuggestionTray() {
        let storyboard = UIStoryboard(name: "SuggestionTray", bundle: nil)

        guard let controller = storyboard.instantiateInitialViewController(creator: { coder in
            SuggestionTrayViewController(coder: coder,
                                         favoritesViewModel: self.favoritesViewModel,
                                         bookmarksDatabase: self.bookmarksDatabase,
                                         historyManager: self.historyManager,
                                         tabsModel: self.tabManager.model,
                                         featureFlagger: self.featureFlagger,
                                         appSettings: self.appSettings,
                                         aiChatSettings: self.aiChatSettings,
                                         featureDiscovery: self.featureDiscovery)
        }) else {
            assertionFailure()
            return
        }

        controller.view.frame = viewCoordinator.suggestionTrayContainer.bounds
        viewCoordinator.suggestionTrayContainer.addSubview(controller.view)

        controller.dismissHandler = dismissSuggestionTray
        controller.autocompleteDelegate = self
        controller.favoritesOverlayDelegate = self
        suggestionTrayController = controller
    }

    func loadTabsBarIfNeeded() {
        guard isPad else { return }

        let controller = TabsBarViewController.createFromXib()

        addChild(controller)
        controller.view.frame = viewCoordinator.tabBarContainer.bounds
        controller.delegate = self
        viewCoordinator.tabBarContainer.addSubview(controller.view)
        tabsBarController = controller
        controller.didMove(toParent: self)
    }

    func startAddFavoriteFlow() {
        contextualOnboardingLogic.enableAddFavoriteFlow()
        if tutorialSettings.hasSeenOnboarding {
            newTab()
        }
    }
    
    func startOnboardingFlowIfNotSeenBefore() {
        // Check if we override onboarding flag and show/hide onboarding accordingly
        // If onboarding is not overridden, show onboarding only if users have not seen it.
        let showOnboarding: Bool
        switch LaunchOptionsHandler().onboardingStatus {
        case .notOverridden:
            showOnboarding = !tutorialSettings.hasSeenOnboarding
        case let .overridden(.developer(isOnboardingCompleted)):
            showOnboarding = !isOnboardingCompleted
        case let .overridden(.uiTests(isOnboardingCompleted)):
            // Set onboarding settings so state is persisted across app re-launches during UI Tests
            tutorialSettings.hasSeenOnboarding = isOnboardingCompleted
            showOnboarding = !tutorialSettings.hasSeenOnboarding
        }

        guard showOnboarding else { return }
        segueToDaxOnboarding()
    }
    
    private func presentNewAddressBarPickerIfNeeded() {
        let validator = NewAddressBarPickerDisplayValidator(
            aiChatSettings: aiChatSettings,
            tutorialSettings: tutorialSettings,
            featureFlagger: featureFlagger,
            experimentalAIChatManager: experimentalAIChatManager,
            appSettings: appSettings,
            pickerStorage: NewAddressBarPickerStorage(),
            launchSourceManager: launchSourceManager
        )
        guard validator.shouldDisplayNewAddressBarPicker() else { return }

        let pickerViewController = NewAddressBarPickerViewController(aiChatSettings: aiChatSettings)
        pickerViewController.modalPresentationStyle = .pageSheet
        pickerViewController.modalTransitionStyle = .coverVertical
        pickerViewController.isModalInPresentation = true
        validator.markPickerDisplayAsSeen()
        self.present(pickerViewController, animated: true)
    }

    func presentNetworkProtectionStatusSettingsModal() {
        Task {
            let subscriptionManager = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge
            if let canShowVPNInUI = try? await subscriptionManager.isFeatureIncludedInSubscription(.networkProtection), canShowVPNInUI {
                segueToVPN()
            } else {
                segueToPrivacyPro()
            }
        }
    }

    private func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow),
                                               name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide),
                                               name: UIResponder.keyboardDidHideNotification, object: nil)
    }


    var keyboardShowing = false
    private var didSendGestureDismissPixel: Bool = false

    @objc
    private func keyboardDidShow() {
        keyboardShowing = true
    }

    @objc
    private func keyboardWillHide() {
        if !didSendGestureDismissPixel, newTabPageViewController?.isDragging == true, keyboardShowing {
            Pixel.fire(pixel: .addressBarGestureDismiss)
            didSendGestureDismissPixel = true
        }
    }

    @objc
    private func keyboardDidHide() {
        keyboardShowing = false
        didSendGestureDismissPixel = false

        if #available(iOS 26, *) {
            // Make sure the UI adjusts properly.
            // Fix for a weird behavior on iOS 26, firing `keyboardWillChangeFrame` event
            // with the same frame when keyboard is shown and hidden rapidly.
            // https://app.asana.com/1/137249556945/project/414709148257752/task/1211140989378405
            adjustUI(withKeyboardFrame: .zero)
        }
    }

    private func setUpToolbarButtonsActions() {

        viewCoordinator.toolbarBackButton.setCustomItemAction(on: self, action: #selector(onBackPressed))
        viewCoordinator.toolbarForwardButton.setCustomItemAction(on: self, action: #selector(onForwardPressed))
        viewCoordinator.toolbarPasswordsButton.setCustomItemAction(on: self, action: #selector(onPasswordsPressed))
        viewCoordinator.toolbarBookmarksButton.setCustomItemAction(on: self, action: #selector(onToolbarBookmarksPressed))
        viewCoordinator.menuToolbarButton.setCustomItemAction(on: self, action: #selector(onMenuPressed))
        viewCoordinator.toolbarFireBarButtonItem.setCustomItemAction(on: self, action: #selector(onFirePressed))
    }

    private func registerForPageRefreshPatterns() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attemptToShowBrokenSitePrompt(_:)),
            name: .pageRefreshMonitorDidDetectRefreshPattern,
            object: nil)
    }

    private func registerForSyncFeatureFlagsUpdates() {
        syncFeatureFlagsCancellable = syncService.featureFlagsPublisher
            .dropFirst()
            .map { $0.contains(.dataSyncing) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isDataSyncingAvailable in
                guard let self else {
                    return
                }
                if isDataSyncingAvailable {
                    self.syncDidShowSyncPausedByFeatureFlagAlert = false
                } else if self.syncService.authState == .active, !self.syncDidShowSyncPausedByFeatureFlagAlert {
                    self.showSyncPausedByFeatureFlagAlert()
                    self.syncDidShowSyncPausedByFeatureFlagAlert = true
                }
            }
    }

    private func showSyncPausedByFeatureFlagAlert(upgradeRequired: Bool = false) {
        let title = UserText.syncPausedTitle
        let description = upgradeRequired ? UserText.syncUnavailableMessageUpgradeRequired : UserText.syncUnavailableMessage
        if self.presentedViewController is SyncSettingsViewController {
            return
        }
        self.presentedViewController?.dismiss(animated: true)
        let alert = UIAlertController(title: title,
                                      message: description,
                                      preferredStyle: .alert)
        if syncService.featureFlags.contains(.userInterface) {
            let learnMoreAction = UIAlertAction(title: UserText.syncPausedAlertLearnMoreButton, style: .default) { _ in
                self.segueToSettingsSync()
            }
            alert.addAction(learnMoreAction)
        }
        alert.addAction(UIAlertAction(title: UserText.syncPausedAlertOkButton, style: .cancel))
        self.present(alert, animated: true)
    }

    func registerForSettingsChangeNotifications() {
        NotificationCenter.default.addObserver(self, selector:
                                                #selector(onAddressBarPositionChanged),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onShowFullURLAddressChanged),
                                               name: AppUserDefaults.Notifications.showsFullURLAddressSettingChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(refreshViewsBasedOnDuckPlayerPresentation),
                                               name: DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated,
                                               object: nil)
        
    }

    @objc func onAddressBarPositionChanged() {
        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
        updateStatusBarBackgroundColor()
        themeColorManager.updateThemeColor()
    }

    @objc private func onShowFullURLAddressChanged() {
        refreshOmniBar()
    }

    @objc func refreshViewsBasedOnDuckPlayerPresentation(notification: Notification) {
        guard let isVisible = notification.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool else { return }
        duckPlayerEntryPointVisible = isVisible
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
    }

    func refreshViewsBasedOnAddressBarPosition(_ position: AddressBarPosition) {
        switch position {
        case .top:
            swipeTabsCoordinator?.addressBarPositionChanged(isTop: true)
            viewCoordinator.constraints.navigationBarContainerBottom.isActive = false
                    
        case .bottom:
            swipeTabsCoordinator?.addressBarPositionChanged(isTop: false)
        }

        omniBar.adjust(for: position)
        adjustNewTabPageSafeAreaInsets(for: position)
        updateChromeForDuckPlayer()
    }

    private func updateChromeForDuckPlayer() {
        themeColorManager.updateThemeColor()
        let position = appSettings.currentAddressBarPosition
        switch position {
        case .top: break // no-op
        case .bottom:
            // Use higher delays then refreshViewsBasedOnAddressBarPosition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) {
                if self.duckPlayerEntryPointVisible {
                    self.viewCoordinator.omniBar.hideSeparator()
                } else {
                    self.viewCoordinator.omniBar.showSeparator()
                }
            }
        }
    }

    private func adjustNewTabPageSafeAreaInsets(for addressBarPosition: AddressBarPosition) {
        switch addressBarPosition {
        case .top:
            newTabPageViewController?.additionalSafeAreaInsets = .zero
        case .bottom:
            newTabPageViewController?.additionalSafeAreaInsets = .init(top: 0, left: 0, bottom: viewCoordinator.omniBar.barView.expectedHeight, right: 0)
        }
    }

    @objc func onShowFullSiteAddressChanged() {
        refreshOmniBar()
    }

    /// Based on https://stackoverflow.com/a/46117073/73479
    ///  Handles iPhone X devices properly.
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {

        guard let userInfo = notification.userInfo,
            let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let duration: TimeInterval = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
        let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

        adjustUI(withKeyboardFrame: keyboardFrame, in: duration, animationCurve: animationCurve)
    }

    private func adjustUI(withKeyboardFrame keyboardFrame: CGRect, in duration: TimeInterval = 0.2, animationCurve: UIView.AnimationOptions = .curveEaseInOut) {
        var keyboardHeight = keyboardFrame.size.height

        let omniBarHeight = viewCoordinator.omniBar.barView.expectedHeight
        let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
        let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 0, dy: -additionalSafeAreaInsets.bottom)
        let intersection = safeAreaFrame.intersection(keyboardFrameInView)
        keyboardHeight = keyboardFrameInView.height

        // On iPad the keyboard will change even if using the hardware keyboard and we don't want FIP to move in that case.
        if intersection.height < 1.0 || intersection.height > (isPad ? 50 : 0) {
            findInPageBottomLayoutConstraint.constant = intersection.height
            let y = self.view.frame.height - intersection.height
            let frame = self.findInPageView.frame
            UIView.animate(withDuration: duration, delay: 0, options: animationCurve, animations: {
                self.findInPageView.frame = CGRect(x: 0, y: y - frame.height, width: frame.width, height: frame.height)
            }, completion: nil)
        }

        if self.appSettings.currentAddressBarPosition.isBottom {
            let intersection = safeAreaFrame.intersection(keyboardFrameInView)
            let containerHeight = keyboardHeight > 0 ? intersection.height - toolbarHeight + omniBarHeight : 0
            self.viewCoordinator.constraints.navigationBarContainerHeight.constant = max(omniBarHeight, containerHeight)

            // Temporary fix, see https://app.asana.com/0/392891325557410/1207990702991361/f
            if let currentTab {
                let inset = intersection.height > 0 ? omniBarHeight : 0
                currentTab.webView.scrollView.contentInset = .init(top: 0, left: 0, bottom: inset, right: 0)

                let bottomOffset = intersection.height > 0 ? containerHeight - omniBarHeight : 0
                currentTab.borderView.bottomOffset = -bottomOffset
            }

            // This NTP stuff is to animate the bottom border divider, but also allow the logo to show.
            //  If we hever have the bottom border and the logo visible at the same... we'll need to do something else.
            if let ntp = self.newTabPageViewController, !ntp.isShowingLogo {
                self.newTabPageViewController?.additionalSafeAreaInsets.bottom = max(omniBarHeight, containerHeight)
            }

            UIView.animate(withDuration: duration, delay: 0, options: animationCurve) {
                self.viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()

                // In case `isAIChatSearchInputUserSettings` is enabled prevent adjusting the bottom containers along with the keyboard to prevent logo on NTP from transitioning too far
                if !self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled, let ntp = self.newTabPageViewController, ntp.isShowingLogo {
                    self.newTabPageViewController?.additionalSafeAreaInsets.bottom = max(omniBarHeight, containerHeight)
                } else {
                    self.newTabPageViewController?.viewSafeAreaInsetsDidChange()
                }
                self.currentTab?.borderView.layoutIfNeeded()
            }
        }
    }

    private func initTabButton() {
        assert(tabSwitcherButton == nil)

        tabSwitcherButton = TabSwitcherStaticButton()

        tabSwitcherButton?.delegate = self
        viewCoordinator.toolbarTabSwitcherButton.customView = tabSwitcherButton

        assert(tabSwitcherButton != nil)

        viewCoordinator.toolbarTabSwitcherButton.isAccessibilityElement = true
        viewCoordinator.toolbarTabSwitcherButton.accessibilityTraits = .button
    }
    
    private func initBookmarksButton() {
        viewCoordinator.omniBar.barView.bookmarksButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                                  action: #selector(quickSaveBookmarkLongPress(gesture:))))
        gestureBookmarksButton.delegate = self

        gestureBookmarksButton.image = DesignSystemImages.Glyphs.Size24.bookmarks
    }

    private func bindFavoritesDisplayMode() {
        favoritesDisplayModeCancellable = NotificationCenter.default.publisher(for: AppUserDefaults.Notifications.favoritesDisplayModeChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.menuBookmarksViewModel.favoritesDisplayMode = self.appSettings.favoritesDisplayMode
                self.favoritesViewModel.favoritesDisplayMode = self.appSettings.favoritesDisplayMode
                WidgetCenter.shared.reloadAllTimelines()
            }
    }

    private func bindSyncService() {
        localUpdatesCancellable = favoritesViewModel.localUpdates
            .sink { [weak self] in
                self?.syncService.scheduler.notifyDataChanged()
            }

        syncUpdatesCancellable = syncDataProviders.bookmarksAdapter.syncDidCompletePublisher
            .sink { [weak self] _ in
                self?.favoritesViewModel.reloadData()
            }
    }

    @objc func quickSaveBookmarkLongPress(gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            quickSaveBookmark()
        }
    }

    @objc func quickSaveBookmark() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        guard currentTab != nil else {
            ActionMessageView.present(message: UserText.webSaveBookmarkNone,
                                      presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom))
            return
        }
        
        Pixel.fire(pixel: .tabBarBookmarksLongPressed)
        currentTab?.saveAsBookmark(favorite: true, viewModel: menuBookmarksViewModel)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let presentedViewController {
            return presentedViewController.supportedInterfaceOrientations
        }
        return tutorialSettings.hasSeenOnboarding ? [.allButUpsideDown] : [.portrait]
    }

    override var shouldAutorotate: Bool {
        return true
    }
        
    @objc func dismissSuggestionTray() {
        omniBar.cancel()
        dismissOmniBar()
    }

    private func addLaunchTabNotificationObserver() {
        launchTabObserver = LaunchTabNotification.addObserver(handler: { [weak self] urlString in
            guard let self = self else { return }
            viewCoordinator.omniBar.endEditing()
            if let url = URL(trimmedAddressBarString: urlString), url.isValid {
                self.loadUrlInNewTab(url, inheritedAttribution: nil)
            } else {
                self.loadQuery(urlString)
            }
        })
    }

    private func loadInitialView() {
        // if let tab = currentTab, tab.link != nil {
        // if let tab = tabManager.current(create: true), tab.link != nil {
        if tabManager.model.currentTab?.link != nil {
            guard let tab = tabManager.current(createIfNeeded: true) else {
                fatalError("Unable to create tab")
            }
            attachTab(tab: tab)
            refreshControls()
        } else {
            attachHomeScreen()
        }
    }

    func handlePressEvent(event: UIPressesEvent?) {
        keyModifierFlags = event?.modifierFlags
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesBegan(presses, with: event)
        handlePressEvent(event: event)
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        handlePressEvent(event: event)
    }

    private func attachOmniBar() {
        viewCoordinator.omniBar.omniDelegate = self
        viewCoordinator.omniBar.barView.menuButtonContent.delegate = self
    }
    
    fileprivate func attachHomeScreen(isNewTab: Bool = false, allowingKeyboard: Bool = false) {
        guard !autoClearInProgress else { return }
        
        viewCoordinator.logoContainer.isHidden = false
        findInPageView.isHidden = true
        chromeManager.detach()
        
        currentTab?.dismiss()
        removeHomeScreen()
        homePageConfiguration.refresh()

        // Access the tab model directly as we don't want to create a new tab controller here
        guard let tabModel = tabManager.model.currentTab else {
            fatalError("No tab model")
        }

        // Attaching HomeScreen means it's going to be displayed immediately.
        // This value gets updated on didAppear so after we leave this function so **after** `refreshControls` is done already, which leads to dot being visible on tab switcher icon on newly opened tab page.
        tabModel.viewed = true

        let newTabDaxDialogFactory = NewTabDaxDialogFactory(delegate: self, daxDialogsFlowCoordinator: daxDialogsManager, onboardingPixelReporter: contextualOnboardingPixelReporter)
        let controller = NewTabPageViewController(tab: tabModel,
                                                  interactionModel: favoritesViewModel,
                                                  homePageMessagesConfiguration: homePageConfiguration,
                                                  privacyProDataReporting: privacyProDataReporter,
                                                  newTabDialogFactory: newTabDaxDialogFactory,
                                                  daxDialogsManager: daxDialogsManager,
                                                  faviconLoader: faviconLoader,
                                                  messageNavigationDelegate: self,
                                                  appSettings: appSettings,
                                                  internalUserCommands: internalUserCommands)

        controller.delegate = self
        controller.chromeDelegate = self

        newTabPageViewController = controller
        addToContentContainer(controller: controller)
        viewCoordinator.logoContainer.isHidden = true
        adjustNewTabPageSafeAreaInsets(for: appSettings.currentAddressBarPosition)

        // This has to happen after the new tab controller is created so that it knows to set the buttons correctly
        // ie remove back/forward and show bookmarks/passwords
        // but also before any other UI updates so that data from the old tab doesn't find its way into the new one
        refreshControls()

        if isNewTab && allowingKeyboard && KeyboardSettings().onNewTab {
            omniBar.beginEditing(animated: true)
        }

        syncService.scheduler.requestSyncImmediately()

        // It's possible for this to be called when in the background of the
        //  switcher, and we only want to show the pixel when it's actually
        // about to shown to the user.
        if presentedViewController == nil || presentedViewController?.isBeingDismissed == true {
            fireNewTabPixels()
        }
    }

    func fireNewTabPixels() {
        Pixel.fire(.homeScreenShown, withAdditionalParameters: [:])
        let favoritesCount = favoritesViewModel.favorites.count
        let bucket = HomePageDisplayDailyPixelBucket(favoritesCount: favoritesCount)
        DailyPixel.fire(pixel: .newTabPageDisplayedDaily, withAdditionalParameters: [
            "FavoriteCount": bucket.value,
        ])
    }

    fileprivate func removeHomeScreen() {
        newTabPageViewController?.willMove(toParent: nil)
        newTabPageViewController?.dismiss()
        newTabPageViewController = nil
    }

    @IBAction func onFirePressed() {

        func showClearDataAlert() {
            let alert = ForgetDataAlert.buildAlert(forgetTabsAndDataHandler: { [weak self] in
                self?.forgetAllWithAnimation {}
            })
            self.present(controller: alert, fromView: self.viewCoordinator.toolbar)
        }

        Pixel.fire(pixel: .forgetAllPressedBrowsing)
        hideNotificationBarIfBrokenSitePromptShown()
        wakeLazyFireButtonAnimator()

        // Dismiss dax dialog and pulse animation when the user taps on the Fire Button.
        currentTab?.dismissContextualDaxFireDialog()
        ViewHighlighter.hideAll()
        showClearDataAlert()
        
        performCancel()
    }

    @objc func onPasswordsPressed() {
        launchAutofillLogins(source: .newTabPageToolbar)
    }

    func onQuickFirePressed() {
        wakeLazyFireButtonAnimator()
        forgetAllWithAnimation {}
        dismiss(animated: true)
        if KeyboardSettings().onAppLaunch {
            enterSearch()
        }
    }
    
    private func wakeLazyFireButtonAnimator() {
        DispatchQueue.main.async {
            _ = self.fireButtonAnimator
        }
    }

    @IBAction func onBackPressed() {
        Pixel.fire(pixel: .tabBarBackPressed)
        performCancel()
        hideSuggestionTray()
        hideNotificationBarIfBrokenSitePromptShown()
        currentTab?.goBack()
    }

    @IBAction func onForwardPressed() {
        Pixel.fire(pixel: .tabBarForwardPressed)
        performCancel()
        hideSuggestionTray()
        hideNotificationBarIfBrokenSitePromptShown()
        currentTab?.goForward()
    }
    
    func onForeground() {
        fireExperimentalAddressBarPixel()
        fireKeyboardSettingsPixels()
        skipSERPFlow = true
        
        // Show Fire Pulse only if Privacy button pulse should not be shown. In control group onboarding `shouldShowPrivacyButtonPulse` is always false.
        if daxDialogsManager.shouldShowFireButtonPulse && !daxDialogsManager.shouldShowPrivacyButtonPulse {
            showFireButtonPulse()
        }
    }

    /// Represents the policy for reusing existing tabs for a query or URL being opened.
    enum ExistingTabReusePolicy: Equatable {
        /// Reuse any existing tab that matches the URL or is a New Tab Page.
        case any
        /// Reuse a specific tab identified by its ID.
        case tabWithId(String)
    }

    /// Loads a search query in a new tab, with an option to reuse an existing tab.
    ///
    /// - Parameters:
    ///   - query: The search query to be loaded.
    ///   - reuseExisting: The policy for reusing an existing tab. Defaults to `none`, meaning no reuse.
    func loadQueryInNewTab(_ query: String, reuseExisting: ExistingTabReusePolicy? = .none) {
        dismissOmniBar()
        guard let url = URL.makeSearchURL(query: query) else {
            Logger.lifecycle.error("Couldn't form URL for query: \(query, privacy: .public)")
            return
        }

        loadUrlInNewTab(url, reuseExisting: reuseExisting, inheritedAttribution: nil)
    }

    /// Load URL in a new tab, with option to reuse an existing tab.
    ///
    /// - Parameters:
    ///   - url: The URL to be loaded.
    ///   - reuseExisting: The policy for reusing an existing tab. Defaults to `none`, meaning no reuse.
    ///   - inheritedAttribution: The attribution state to be inherited from a parent tab, if any.
    ///   - fromExternalLink: A flag indicating if the URL is from an external link. Defaults to `false`.
    func loadUrlInNewTab(_ url: URL, reuseExisting: ExistingTabReusePolicy? = .none, inheritedAttribution: AdClickAttributionLogic.State?, fromExternalLink: Bool = false) {

        func worker() {
            allowContentUnderflow = false
            viewCoordinator.navigationBarContainer.alpha = 1
            loadViewIfNeeded()

            // Check if a specific tab ID should be reused.
            if case .tabWithId(let id) = reuseExisting, let existing = tabManager.first(withId: id) {
                selectTab(existing)
            }
            // Check if an existing tab with the same URL should be reused.
            else if reuseExisting != .none, let existing = tabManager.first(withUrl: url) {
                selectTab(existing)
                return
            }
            // Check if a tab presenting a New Tab page should be reused.
            else if reuseExisting != .none, let existing = tabManager.firstHomeTab() {
                if autoClearInProgress {
                    autoClearShouldRefreshUIAfterClear = false
                }
                tabManager.selectTab(existing)
                loadUrl(url, fromExternalLink: fromExternalLink)
            }
            // Add a new tab if no existing tab is reused.
            else {
                addTab(url: url, inheritedAttribution: inheritedAttribution, fromExternalLink: fromExternalLink)
            }

            refreshOmniBar()
            refreshTabIcon()
            refreshControls()
            tabsBarController?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
            swipeTabsCoordinator?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
        }

        if clearInProgress {
            postClear = worker
        } else {
            worker()
        }
    }

    func enterSearch() {
        if presentedViewController == nil {
            showBars()
            viewCoordinator.omniBar.beginEditing(animated: true)
        }
    }

    fileprivate func loadQuery(_ query: String) {
        guard let url = URL.makeSearchURL(query: query, queryContext: currentTab?.url) else {
            Logger.general.error("Couldn't form URL for query \"\(query, privacy: .public)\" with context \"\(self.currentTab?.url?.absoluteString ?? "<nil>", privacy: .public)\"")
            return
        }
        // Make sure that once query is submitted, we don't trigger the non-SERP flow
        skipSERPFlow = false
        loadUrl(url)
    }

    func stopLoading() {
        currentTab?.stopLoading()
    }

    func loadUrl(_ url: URL, fromExternalLink: Bool = false) {
        prepareTabForRequest {
            self.currentTab?.load(url: url)
            if fromExternalLink {
                self.currentTab?.inferredOpenerContext = .external
            }
        }
    }

    func executeBookmarklet(_ url: URL) {
        if url.isBookmarklet() {
            currentTab?.executeBookmarklet(url: url)
        }
    }

    private func loadBackForwardItem(_ item: WKBackForwardListItem) {
        prepareTabForRequest {
            currentTab?.load(backForwardListItem: item)
        }
    }
    
    private func prepareTabForRequest(request: () -> Void) {
        viewCoordinator.navigationBarContainer.alpha = 1
        allowContentUnderflow = false

        if currentTab == nil {
            if tabManager.current(createIfNeeded: true) == nil {
                fatalError("failed to create tab")
            }
        }

        guard let tab = currentTab else { fatalError("no tab") }
        
        request()
        dismissOmniBar()
        select(tab: tab)
    }

    private func addTab(url: URL?, inheritedAttribution: AdClickAttributionLogic.State?, fromExternalLink: Bool = false) {
        let tab = tabManager.add(url: url, inheritedAttribution: inheritedAttribution)
        tab.inferredOpenerContext = .external
        dismissOmniBar()
        attachTab(tab: tab)
    }

    func select(tabAt index: Int) {
        viewCoordinator.navigationBarContainer.alpha = 1
        allowContentUnderflow = false
        
        if tabManager.model.tabs.indices.contains(index) {
            let tab = tabManager.select(tabAt: index)
            select(tab: tab)
        } else {
            assertionFailure("Invalid index selected")
        }
    }

    fileprivate func select(tab: TabViewController) {
        hideNotificationBarIfBrokenSitePromptShown()
        if tab.link == nil {
            attachHomeScreen()
        } else {
            attachTab(tab: tab)
            refreshControls()
        }
        themeColorManager.updateThemeColor()
        tabsBarController?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
        if daxDialogsManager.shouldShowFireButtonPulse {
            showFireButtonPulse()
        }
    }

    private func attachTab(tab: TabViewController) {
        removeHomeScreen()
        updateFindInPage()
        hideNotificationBarIfBrokenSitePromptShown()
        currentTab?.progressWorker.progressBar = nil
        currentTab?.chromeDelegate = nil
            
        addToContentContainer(controller: tab)

        viewCoordinator.logoContainer.isHidden = true

        tab.progressWorker.progressBar = viewCoordinator.progress
        chromeManager.attach(to: tab.webView.scrollView)
        themeColorManager.attach(to: tab)
        tab.chromeDelegate = self
    }

    private func addToContentContainer(controller: UIViewController) {
        viewCoordinator.contentContainer.isHidden = false
        addChild(controller)
        viewCoordinator.contentContainer.subviews.forEach { $0.removeFromSuperview() }
        viewCoordinator.contentContainer.addSubview(controller.view)

        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.frame = viewCoordinator.contentContainer.bounds
        controller.didMove(toParent: self)
    }

    fileprivate func updateCurrentTab() {
        // prepopulate VC for current tab if needed
        if let currentTab = tabManager.current(createIfNeeded: true) {
            select(tab: currentTab)
            viewCoordinator.omniBar.endEditing()
        } else {
            attachHomeScreen()
        }
    }

    fileprivate func refreshControls() {
        refreshTabIcon()
        refreshMenuButtonState()
        refreshOmniBar()
        refreshBackForwardButtons()
        refreshBackForwardMenuItems()
        updateChromeForDuckPlayer()
    }

    private func refreshTabIcon() {
        viewCoordinator.toolbarTabSwitcherButton.accessibilityHint = UserText.numberOfTabs(tabManager.count)
        assert(tabSwitcherButton != nil)
        tabSwitcherButton?.tabCount = tabManager.count
        tabSwitcherButton?.hasUnread = tabManager.hasUnread
    }

    private func refreshOmniBar() {
        updateOmniBarLoadingState()
        viewCoordinator.omniBar.updateAccessoryType(omnibarAccessoryHandler.omnibarAccessory(for: currentTab?.url))

        guard let tab = currentTab, tab.link != nil else {
            viewCoordinator.omniBar.stopBrowsing()
            // Clear Dax Easter Egg logo when no tab is active
            viewCoordinator.omniBar.setDaxEasterEggLogoURL(nil)
            return
        }

        viewCoordinator.omniBar.refreshText(forUrl: tab.url, forceFullURL: appSettings.showFullSiteAddress)

        if tab.isError {
            viewCoordinator.omniBar.hidePrivacyIcon()
        } else if let privacyInfo = tab.privacyInfo, privacyInfo.url.host == tab.url?.host {
            viewCoordinator.omniBar.updatePrivacyIcon(for: privacyInfo)
        } else {
            viewCoordinator.omniBar.resetPrivacyIcon(for: tab.url)
        }

        // Restore the Dax Easter Egg logo URL for the current tab
        Logger.daxEasterEgg.debug("RefreshOmniBar - Stored Logo: \(tab.tabModel.daxEasterEggLogoURL ?? "nil")")
        viewCoordinator.omniBar.setDaxEasterEggLogoURL(tab.tabModel.daxEasterEggLogoURL)

        viewCoordinator.omniBar.startBrowsing()
    }

    private func updateOmniBarLoadingState() {
        if currentTab?.isLoading == true {
            omniBar.startLoading()
        } else {
            omniBar.stopLoading()
        }
    }

    func dismissOmniBar() {
        hideSuggestionTray()
        viewCoordinator.omniBar.endEditing()
        refreshOmniBar()
    }

    private func hideNotificationBarIfBrokenSitePromptShown(afterRefresh: Bool = false) {
        guard brokenSitePromptViewHostingController != nil else { return }
        brokenSitePromptViewHostingController = nil
        hideNotification()
    }

    fileprivate func refreshBackForwardButtons() {
        viewCoordinator.omniBar.isBackButtonEnabled = viewCoordinator.toolbarBackButton.isEnabled
        viewCoordinator.omniBar.isForwardButtonEnabled = viewCoordinator.toolbarForwardButton.isEnabled
    }
  
    var orientationPixelWorker: DispatchWorkItem?

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if AppWidthObserver.shared.willResize(toWidth: size.width) {
            applyWidth()
        }

        self.showMenuHighlighterIfNeeded()
        updateChromeForDuckPlayer()

        let isKeyboardShowing = omniBar.isTextFieldEditing
        coordinator.animate { _ in
            self.swipeTabsCoordinator?.invalidateLayout()
            self.deferredFireOrientationPixel()
        } completion: { _ in
            if isKeyboardShowing {
                self.omniBar.beginEditing(animated: true)
            }

            ViewHighlighter.updatePositions()
        }

        hideNotificationBarIfBrokenSitePromptShown()
    }

    private func deferredFireOrientationPixel() {
        orientationPixelWorker?.cancel()
        orientationPixelWorker = nil
        if UIDevice.current.orientation.isLandscape {
            let worker = DispatchWorkItem {
                Pixel.fire(pixel: .deviceOrientationLandscape)
            }
            DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + 3, execute: worker)
            orientationPixelWorker = worker
        }
    }

    private func applyWidth() {

        if AppWidthObserver.shared.isLargeWidth {
            applyLargeWidth()
        } else {
            applySmallWidth()
        }

        DispatchQueue.main.async {
            // Do this async otherwise the toolbar buttons skew to the right
            if self.viewCoordinator.constraints.navigationBarContainerTop.constant >= 0 {
                self.showBars()
            }
            // If tabs have been udpated, do this async to make sure size calcs are current
            self.tabsBarController?.refresh(tabsModel: self.tabManager.model)
            self.swipeTabsCoordinator?.refresh(tabsModel: self.tabManager.model)
            
            // Do this on the next UI thread pass so we definitely have the right width
            self.applyWidthToTrayController()
            self.newTabPageViewController?.widthChanged()
        }
    }

    func refreshMenuButtonState() {
        if newTabPageViewController != nil {
            viewCoordinator.omniBar.barView.menuButton.accessibilityLabel = UserText.bookmarksButtonHint
            viewCoordinator.updateToolbarWithState(.newTab)
            presentedMenuButton.setState(.menuImage, animated: false)

        } else {
            let expectedState: MenuButton.State
            if presentedViewController is BrowsingMenuViewController {
                expectedState = .closeImage
            } else {
                expectedState = .menuImage
            }
            viewCoordinator.omniBar.barView.menuButton.accessibilityLabel = UserText.menuButtonHint

            if let currentTab = currentTab {
                viewCoordinator.updateToolbarWithState(.pageLoaded(currentTab: currentTab))
            }
            presentedMenuButton.setState(expectedState, animated: false)
        }
    }

    private func applyWidthToTrayController() {
        if AppWidthObserver.shared.isLargeWidth {
            self.suggestionTrayController?.float(withWidth: self.viewCoordinator.omniBar.barView.searchContainerWidth + 32)
        } else {
            let bottomOmniBarHeight = appSettings.currentAddressBarPosition.isBottom ? omniBar.barView.expectedHeight : 0
            self.suggestionTrayController?.fill(bottomOffset: bottomOmniBarHeight)
        }
    }
    
    private func applyLargeWidth() {
        viewCoordinator.tabBarContainer.isHidden = false
        viewCoordinator.toolbar.isHidden = true
        viewCoordinator.omniBar.enterPadState()
        
        swipeTabsCoordinator?.isEnabled = false
    }

    private func applySmallWidth() {
        viewCoordinator.tabBarContainer.isHidden = true
        viewCoordinator.toolbar.isHidden = false
        viewCoordinator.omniBar.enterPhoneState()
        
        swipeTabsCoordinator?.isEnabled = true
    }

    @discardableResult
    func tryToShowSuggestionTray(_ type: SuggestionTrayViewController.SuggestionType) -> Bool {
        let canShow = suggestionTrayController?.canShow(for: type) ?? false
        if canShow {
            showSuggestionTray(type)
        }
        return canShow
    }
    
    private func showSuggestionTray(_ type: SuggestionTrayViewController.SuggestionType) {
        suggestionTrayController?.show(for: type)
        applyWidthToTrayController()
        if !AppWidthObserver.shared.isLargeWidth {
            if !daxDialogsManager.shouldShowFireButtonPulse {
                ViewHighlighter.hideAll()
            }
            if type.hideOmnibarSeparator() && appSettings.currentAddressBarPosition != .bottom {
                viewCoordinator.omniBar.hideSeparator()
            }
        }
        viewCoordinator.suggestionTrayContainer.isHidden = false
        currentTab?.webView.accessibilityElementsHidden = true
    }
    
    func hideSuggestionTray() {
        viewCoordinator.omniBar.showSeparator()
        viewCoordinator.suggestionTrayContainer.isHidden = true
        currentTab?.webView.accessibilityElementsHidden = false
        suggestionTrayController?.didHide()
    }
    
    func launchAutofillLogins(with currentTabUrl: URL? = nil, currentTabUid: String? = nil, openSearch: Bool = false, source: AutofillSettingsSource, selectedAccount: SecureVaultModels.WebsiteAccount? = nil) {
        let appSettings = AppDependencyProvider.shared.appSettings
        let autofillLoginListViewController = AutofillLoginListViewController(
            appSettings: appSettings,
            currentTabUrl: currentTabUrl,
            currentTabUid: currentTabUid,
            syncService: syncService,
            syncDataProviders: syncDataProviders,
            selectedAccount: selectedAccount,
            openSearch: openSearch,
            source: source,
            bookmarksDatabase: self.bookmarksDatabase,
            favoritesDisplayMode: self.appSettings.favoritesDisplayMode,
            keyValueStore: self.keyValueStore
        )
        autofillLoginListViewController.delegate = self
        let navigationController = UINavigationController(rootViewController: autofillLoginListViewController)
        autofillLoginListViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: UserText.autofillNavigationButtonItemTitleClose,
                                                                                          style: .plain,
                                                                                          target: self,
                                                                                          action: #selector(closeAutofillModal))
        self.present(navigationController, animated: true, completion: nil)

        if selectedAccount == nil, let account = AppDependencyProvider.shared.autofillLoginSession.lastAccessedAccount {
            autofillLoginListViewController.showAccountDetails(account, animated: true)
        }
    }

    func launchDataImport(source: DataImportViewModel.ImportScreen, onFinished: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        let dataImportManager = DataImportManager(reporter: SecureVaultReporter(),
                                                  bookmarksDatabase: self.bookmarksDatabase,
                                                  favoritesDisplayMode: self.appSettings.favoritesDisplayMode,
                                                  tld: AppDependencyProvider.shared.storageCache.tld)
        let dataImportViewController = DataImportViewController(importManager: dataImportManager,
                                                                importScreen: source,
                                                                syncService: syncService,
                                                                keyValueStore: keyValueStore,
                                                                onFinished: onFinished,
                                                                onCancelled: onCancelled)

        let navigationController = UINavigationController(rootViewController: dataImportViewController)
        dataImportViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: UserText.autofillNavigationButtonItemTitleClose,
                                                                                          style: .plain,
                                                                                          target: self,
                                                                                          action: #selector(closeAutofillModal))
        self.present(navigationController, animated: true, completion: nil)
    }

    @objc private func closeAutofillModal() {
        dismiss(animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ViewHighlighter.updatePositions()
    }

    private func showNotification(title: String, message: String, dismissHandler: @escaping NotificationView.DismissHandler) {
        guard notificationView == nil else { return }

        let notificationView = NotificationView.loadFromNib(dismissHandler: dismissHandler)
        notificationView.setTitle(text: title)
        notificationView.setMessage(text: message)

        showNotification(with: notificationView)
    }

    private func showNotification(with contentView: UIView) {
        guard viewCoordinator.topSlideContainer.subviews.isEmpty else { return }
        viewCoordinator.topSlideContainer.addSubview(contentView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: viewCoordinator.topSlideContainer.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: viewCoordinator.topSlideContainer.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: viewCoordinator.topSlideContainer.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: viewCoordinator.topSlideContainer.bottomAnchor),
        ])

        self.notificationView = contentView

        view.layoutIfNeeded()
        view.layoutSubviews()
        viewCoordinator.showTopSlideContainer()
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }

    func hideNotification() {
        view.layoutIfNeeded()
        viewCoordinator.hideTopSlideContainer()
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.notificationView?.removeFromSuperview()
            self.notificationView = nil
        }
    }

    func showHomeRowReminder() {
        // Show the reminder only if users have not seen the Add to Dock promo.
        // iPhone users would have seen Add to Dock promo during the onboarding.
        // iPad users don't see the Add to Dock promo during the onboarding.
        guard !OnboardingManager().userHasSeenAddToDockPromoDuringOnboarding else { return }
        let feature = HomeRowReminder()
        if feature.showNow() {
            showNotification(title: UserText.homeRowReminderTitle, message: UserText.homeRowReminderMessage) { tapped in
                if tapped {
                    self.segueToHomeRow()
                }
                self.hideNotification()
            }
            feature.setShown()
        }
    }

    func fireOnboardingCustomSearchPixelIfNeeded(query: String) {
        if contextualOnboardingLogic.isShowingSearchSuggestions {
            contextualOnboardingPixelReporter.measureCustomSearch()
        } else if contextualOnboardingLogic.isShowingSitesSuggestions {
            contextualOnboardingPixelReporter.measureCustomSite()
        }
    }

    private var brokenSitePromptViewHostingController: UIHostingController<BrokenSitePromptView>?
    lazy private var brokenSitePromptLimiter = BrokenSitePromptLimiter(privacyConfigManager: ContentBlocking.shared.privacyConfigurationManager,
                                                                       store: BrokenSitePromptLimiterStore())

    @objc func attemptToShowBrokenSitePrompt(_ notification: Notification) {
        guard brokenSitePromptLimiter.shouldShowToast(),
            let url = currentTab?.url, !url.isDuckDuckGo,
            notificationView == nil,
            !isPad,
            DefaultTutorialSettings().hasSeenOnboarding,
            !daxDialogsManager.isStillOnboarding(),
            isPortrait else { return }
        // We're using async to ensure the view dismissal happens on the first runloop after a refresh. This prevents the scenario where the view briefly appears and then immediately disappears after a refresh.
        brokenSitePromptLimiter.didShowToast()
        DispatchQueue.main.async {
            self.showBrokenSitePrompt()
        }
    }

    private func showBrokenSitePrompt() {
        let host = makeBrokenSitePromptViewHostingController()
        brokenSitePromptViewHostingController = host
        Pixel.fire(pixel: .siteNotWorkingShown)
        showNotification(with: host.view)
    }

    private func makeBrokenSitePromptViewHostingController() -> UIHostingController<BrokenSitePromptView> {
        let viewModel = BrokenSitePromptViewModel(onDidDismiss: { [weak self] in
            Task { @MainActor in
                self?.hideNotification()
                self?.brokenSitePromptLimiter.didDismissToast()
                self?.brokenSitePromptViewHostingController = nil
            }
        }, onDidSubmit: { [weak self] in
            Task { @MainActor in
                self?.segueToReportBrokenSite(entryPoint: .prompt)
                self?.hideNotification()
                self?.brokenSitePromptLimiter.didOpenReport()
                self?.brokenSitePromptViewHostingController = nil
                Pixel.fire(pixel: .siteNotWorkingWebsiteIsBroken)
            }
        })
        return UIHostingController(rootView: BrokenSitePromptView(viewModel: viewModel), ignoreSafeArea: true)
    }

    func animateBackgroundTab() {
        showBars()
        tabSwitcherButton?.animateUpdate {
            self.refreshTabIcon()
        }
        tabsBarController?.backgroundTabAdded()
    }

    func newTab(reuseExisting: Bool = false, allowingKeyboard: Bool = true) {
        if daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        daxDialogsManager.fireButtonPulseCancelled()
        hideSuggestionTray()
        hideNotificationBarIfBrokenSitePromptShown()
        currentTab?.dismiss()

        if reuseExisting, let existing = tabManager.firstHomeTab() {
            tabManager.selectTab(existing)
        } else {
            tabManager.addHomeTab()
        }
        attachHomeScreen(isNewTab: true, allowingKeyboard: allowingKeyboard)
        tabsBarController?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
        themeColorManager.updateThemeColor()
        showBars() // In case the browser chrome bars are hidden when calling this method
    }
    
    func updateFindInPage() {
        currentTab?.findInPage?.delegate = self
        findInPageView.update(with: currentTab?.findInPage, updateTextField: true)
        // hide toolbar on iPhone
        viewCoordinator.toolbar.accessibilityElementsHidden = !AppWidthObserver.shared.isLargeWidth
    }

    private func handleVoiceSearchOpenRequest(preferredTarget: VoiceSearchTarget? = nil) {
        SpeechRecognizer.requestMicAccess { [weak self] permission in
            guard let self = self else { return }
            if permission {
                if let target = preferredTarget {
                    self.showVoiceSearch(preferredTarget: target)
                } else {
                    self.showVoiceSearch()
                }
            } else {
                self.showNoMicrophonePermissionAlert()
            }
        }
    }

    private func showVoiceSearch(preferredTarget: VoiceSearchTarget? = nil) {
        // https://app.asana.com/0/0/1201408131067987
        UIMenuController.shared.hideMenu()
        viewCoordinator.omniBar.removeTextSelection()
        
        Pixel.fire(pixel: .openVoiceSearch)
        let voiceSearchController = VoiceSearchViewController(preferredTarget: preferredTarget)
        voiceSearchController.delegate = self
        voiceSearchController.modalTransitionStyle = .crossDissolve
        voiceSearchController.modalPresentationStyle = .overFullScreen
        present(voiceSearchController, animated: true, completion: nil)
    }
    
    private func showNoMicrophonePermissionAlert() {
        let alertController = NoMicPermissionAlert.buildAlert()
        present(alertController, animated: true, completion: nil)
    }
    
    private func subscribeToEmailProtectionStatusNotifications() {
        NotificationCenter.default.publisher(for: .emailDidSignIn)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onDuckDuckGoEmailSignIn(notification)
            }
            .store(in: &emailCancellables)

        NotificationCenter.default.publisher(for: .emailDidSignOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onDuckDuckGoEmailSignOut(notification)
            }
            .store(in: &emailCancellables)
    }

    private func subscribeToURLInterceptorNotifications() {
        NotificationCenter.default.publisher(for: .urlInterceptPrivacyPro)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection
                if let redirectURLComponents = notification.userInfo?[TabURLInterceptorParameter.interceptedURLComponents] as? URLComponents {
                    deepLinkTarget = .subscriptionFlow(redirectURLComponents: redirectURLComponents)
                } else {
                    deepLinkTarget = .subscriptionFlow()
                }
                self?.launchSettings(deepLinkTarget: deepLinkTarget)

            }
            .store(in: &urlInterceptorCancellables)

        NotificationCenter.default.publisher(for: .urlInterceptAIChat)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.openAIChat(payload: notification.object)

            }
            .store(in: &urlInterceptorCancellables)
    }

    private func subscribeToSettingsDeeplinkNotifications() {
        NotificationCenter.default.publisher(for: .settingsDeepLinkNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let handleSettingsDeepLink = {
                    self.handleSettingsDeepLink(notification)
                }
                if let presentedViewController {
                    if !(presentedViewController is SettingsUINavigationController) {
                        presentedViewController.dismiss(animated: true, completion: handleSettingsDeepLink)
                        return
                    }
                }
                
                handleSettingsDeepLink()
            }
            .store(in: &settingsDeepLinkcancellables)
    }
    
    private func handleSettingsDeepLink(_ notification: Notification) {
        switch notification.object as? SettingsViewModel.SettingsDeepLinkSection {
        
        case .duckPlayer:
            let deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection
                deepLinkTarget = .duckPlayer
            launchSettings(deepLinkTarget: deepLinkTarget)
        case .subscriptionFlow(let components):
            launchSettings(deepLinkTarget: .subscriptionFlow(redirectURLComponents: components))
        case .subscriptionSettings:
            launchSettings(deepLinkTarget: .subscriptionSettings)
        case .restoreFlow:
            launchSettings(deepLinkTarget: .restoreFlow)
        default:
            return
        }
    }

    private func subscribeToAIChatSettingsEvents() {
        NotificationCenter.default.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOmniBar()
                WidgetCenter.shared.reloadAllTimelines()
            }
            .store(in: &aiChatCancellables)
    }
    
    private func subscribeToRefreshButtonSettingsEvents() {
        NotificationCenter.default.publisher(for: AppUserDefaults.Notifications.refreshButtonSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOmniBar()
            }
            .store(in: &refreshButtonCancellables)
        
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }
        
        overridesHandler.flagDidChangePublisher
            .filter { $0.0 == .refreshButtonPosition }
            .sink { [weak self] _ in
                self?.refreshOmniBar()
            }
            .store(in: &refreshButtonCancellables)
    }

    private func subscribeToNetworkProtectionEvents() {
        if !featureDiscovery.wasUsedBefore(.vpn) {
            // If the VPN was used before we don't care about this notification any more
            NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
                .sink { [weak self] notification in
                    self?.onVPNStatusDidChange(notification)
                }.store(in: &vpnCancellables)
        }

        // Subscribe to app foreground events to check entitlements
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Logger.networkProtection.log("App foreground notification received, checking entitlements")
                guard let self else { return }
                self.performClientCheck(trigger: .appForegrounded)
            }
            .store(in: &vpnCancellables)

        NotificationCenter.default.publisher(for: .accountDidSignIn)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onNetworkProtectionAccountSignIn(notification)
            }
            .store(in: &vpnCancellables)

        NotificationCenter.default.publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onEntitlementsChange(notification)
            }
            .store(in: &vpnCancellables)

        NotificationCenter.default.publisher(for: .accountDidSignOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onNetworkProtectionAccountSignOut(notification)
            }
            .store(in: &vpnCancellables)

        NotificationCenter.default.publisher(for: .vpnEntitlementMessagingDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.onNetworkProtectionEntitlementMessagingChange()
            }
            .store(in: &vpnCancellables)

        let notificationCallback: CFNotificationCallback = { _, _, name, _, _ in
            if let name {
                NotificationCenter.default.post(name: Notification.Name(name.rawValue as String),
                                                object: nil)
            }
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                        notificationCallback,
                                        Notification.Name.vpnEntitlementMessagingDidChange.rawValue as CFString,
                                        nil, .deliverImmediately)
    }

    private func subscribeToUnifiedFeedbackNotifications() {
        feedbackCancellable = NotificationCenter.default.publisher(for: .unifiedFeedbackNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                DispatchQueue.main.async { [weak self] in
                    guard let navigationController = self?.presentedViewController as? UINavigationController else { return }
                    navigationController.popToRootViewController(animated: true)
                    ActionMessageView.present(message: UserText.vpnFeedbackFormSubmittedMessage,
                                              presentationLocation: .withoutBottomBar)
                }
            }
    }

    private func onVPNStatusDidChange(_ notification: Notification) {
        guard let session = (notification.object as? NETunnelProviderSession),
           session.status == .connected else {
            return
        }
        self.featureDiscovery.setWasUsedBefore(.vpn)
    }

    private func onNetworkProtectionEntitlementMessagingChange() {
        if tunnelDefaults.showEntitlementAlert {
            presentExpiredEntitlementAlert()
        }

        presentExpiredEntitlementNotification()
    }

    private func presentExpiredEntitlementAlert() {
        let alertController = CriticalAlerts.makeExpiredEntitlementAlert { [weak self] in
            self?.segueToPrivacyPro()
        }
        dismiss(animated: true) {
            self.present(alertController, animated: true, completion: nil)
            self.tunnelDefaults.showEntitlementAlert = false
        }
    }

    private func presentExpiredEntitlementNotification() {
        let presenter = VPNNotificationsPresenterTogglableDecorator(
            settings: AppDependencyProvider.shared.vpnSettings,
            defaults: .networkProtectionGroupDefaults,
            wrappee: NetworkProtectionUNNotificationPresenter()
        )
        presenter.showEntitlementNotification()
    }

    @objc
    private func onNetworkProtectionAccountSignIn(_ notification: Notification) {
        Task {
            let subscriptionManager = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge
            let isAuthV2Enabled = AppDependencyProvider.shared.isUsingAuthV2
            let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

            PixelKit.fire(
                VPNSubscriptionStatusPixel.signedIn(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: notification.object),
                frequency: .dailyAndCount)
            tunnelDefaults.resetEntitlementMessaging()
            Logger.networkProtection.info("[NetP Subscription] Reset expired entitlement messaging")
        }
    }

    var networkProtectionTunnelController: NetworkProtectionTunnelController {
        AppDependencyProvider.shared.networkProtectionTunnelController
    }

    private func performClientCheck(trigger: VPNSubscriptionClientCheckPixel.Trigger) {
        Task {
            do {
                let isAuthV2Enabled = AppDependencyProvider.shared.isUsingAuthV2
                let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive
                let hasEntitlement = try await subscriptionManager.isFeatureEnabled(.networkProtection)

                if !hadVPNEntitlements && hasEntitlement {
                    PixelKit.fire(
                        VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
                            isSubscriptionActive: isSubscriptionActive,
                            isAuthV2Enabled: isAuthV2Enabled,
                            trigger: trigger),
                        frequency: .dailyAndCount)
                    
                    hadVPNEntitlements = hasEntitlement
                } else if hadVPNEntitlements && !hasEntitlement {
                    PixelKit.fire(
                        VPNSubscriptionClientCheckPixel.vpnFeatureDisabled(
                            isSubscriptionActive: isSubscriptionActive,
                            isAuthV2Enabled: isAuthV2Enabled,
                            trigger: trigger),
                        frequency: .dailyAndCount)
                    
                    hadVPNEntitlements = hasEntitlement
                }
            } catch {
                await handleClientCheckFailure(error: error, trigger: trigger)
            }
        }
    }

    private func handleClientCheckFailure(error: Error, trigger: VPNSubscriptionClientCheckPixel.Trigger) async {
        let isAuthV2Enabled = AppDependencyProvider.shared.isUsingAuthV2
        let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive
        
        PixelKit.fire(
            VPNSubscriptionClientCheckPixel.failed(
                isSubscriptionActive: isSubscriptionActive,
                isAuthV2Enabled: isAuthV2Enabled,
                trigger: trigger,
                error: error),
            frequency: .daily)
    }

    func checkSubscriptionEntitlements() {
        performClientCheck(trigger: .appStartup)
    }

    @objc
    private func onEntitlementsChange(_ notification: Notification) {
        Task {
            guard let userInfo = notification.userInfo,
                  let payload = EntitlementsDidChangePayload(notificationUserInfo: userInfo) else {
                assertionFailure("Missing entitlements payload")
                Logger.subscription.fault("Missing entitlements payload")
                return
            }

            let userInitiatedSignOut = (userInfo[EntitlementsDidChangePayload.userInitiatedEntitlementChangeKey] as? Bool) ?? false
            let hasVPNEntitlements = payload.entitlements.contains(.networkProtection)
            let isAuthV2Enabled = AppDependencyProvider.shared.isUsingAuthV2
            let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

            if hasVPNEntitlements {
                PixelKit.fire(
                    VPNSubscriptionStatusPixel.vpnFeatureEnabled(
                        isSubscriptionActive: isSubscriptionActive,
                        isAuthV2Enabled: isAuthV2Enabled,
                        sourceObject: notification.object),
                    frequency: .dailyAndCount)
            } else {
                PixelKit.fire(
                    VPNSubscriptionStatusPixel.vpnFeatureDisabled(
                        isSubscriptionActive: isSubscriptionActive,
                        isAuthV2Enabled: isAuthV2Enabled,
                        sourceObject: notification.object),
                    frequency: .dailyAndCount)

                if await networkProtectionTunnelController.isInstalled && !userInitiatedSignOut {
                    tunnelDefaults.enableEntitlementMessaging()
                }

                await networkProtectionTunnelController.stop()

                if userInitiatedSignOut {
                    await networkProtectionTunnelController.removeVPN(reason: .signedOut)
                } else {
                    await networkProtectionTunnelController.removeVPN(reason: .entitlementCheck)
                }
            }

            hadVPNEntitlements = hasVPNEntitlements
        }
    }

    @objc
    private func onNetworkProtectionAccountSignOut(_ notification: Notification) {
        Task {
            let subscriptionManager = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge
            let isAuthV2Enabled = AppDependencyProvider.shared.isUsingAuthV2
            let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

            PixelKit.fire(
                VPNSubscriptionStatusPixel.signedOut(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: notification.object),
                frequency: .dailyAndCount)

            await networkProtectionTunnelController.stop()
            await networkProtectionTunnelController.removeVPN(reason: .signedOut)
        }
    }

    @objc
    private func onDuckDuckGoEmailSignIn(_ notification: Notification) {
        fireEmailPixel(.emailEnabled, notification: notification)
        if let object = notification.object as? EmailManager,
           let emailManager = syncDataProviders.settingsAdapter.emailManager,
           object !== emailManager {

            syncService.scheduler.notifyDataChanged()
        }
    }
    
    @objc
    private func onDuckDuckGoEmailSignOut(_ notification: Notification) {
        fireEmailPixel(.emailDisabled, notification: notification)
        presentEmailProtectionSignInAlertIfNeeded(notification)
        if let object = notification.object as? EmailManager,
           let emailManager = syncDataProviders.settingsAdapter.emailManager,
           object !== emailManager {

            syncService.scheduler.notifyDataChanged()
        }
    }

    private func presentEmailProtectionSignInAlertIfNeeded(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: String],
            userInfo[EmailManager.NotificationParameter.isForcedSignOut] != nil else {
            return
        }
        let alertController = CriticalAlerts.makeEmailProtectionSignInAlert()
        dismiss(animated: true) {
            self.present(alertController, animated: true, completion: nil)
        }
    }

    private func fireEmailPixel(_ pixel: Pixel.Event, notification: Notification) {
        var pixelParameters: [String: String] = [:]
        
        if let userInfo = notification.userInfo as? [String: String], let cohort = userInfo[EmailManager.NotificationParameter.cohort] {
            pixelParameters[PixelParameters.emailCohort] = cohort
        }
        
        Pixel.fire(pixel: pixel, withAdditionalParameters: pixelParameters, includedParameters: [.atb])
    }

    func openAIChat(_ query: String? = nil, autoSend: Bool = false, payload: Any? = nil, tools: [AIChatRAGTool]? = nil) {
        aiChatViewControllerManager.openAIChat(query, payload: payload, autoSend: autoSend, tools: tools, on: self)
    }
}

extension MainViewController: FindInPageDelegate {
    
    func updated(findInPage: FindInPage) {
        findInPageView.update(with: findInPage, updateTextField: false)
    }

}

extension MainViewController: FindInPageViewDelegate {
    
    func done(findInPageView: FindInPageView) {
        currentTab?.findInPage = nil
        viewCoordinator.toolbar.accessibilityElementsHidden = false

        viewCoordinator.showNavigationBarWithBottomPosition()
    }
}

extension MainViewController: BrowserChromeDelegate {

    struct ChromeAnimationConstants {
        static let duration = 0.1
    }

    var tabBarContainer: UIView {
        viewCoordinator.tabBarContainer
    }

    var omniBar: any OmniBar {
        viewCoordinator.omniBar
    }

    private func hideKeyboard() {
        dismissOmniBar()
        _ = findInPageView.resignFirstResponder()
    }

    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?) {
        if hidden { hideKeyboard() }

        setBarsVisibility(hidden ? 0 : 1.0, animated: animated, animationDuration: customAnimationDuration)
    }
    
    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?) {
        if percent < 1 {
            hideKeyboard()
            hideMenuHighlighter()
        } else {
            showMenuHighlighterIfNeeded()
        }
        
        let updateBlock = {
            self.updateToolbarConstant(percent)
            self.updateNavBarConstant(percent)

            self.viewCoordinator.navigationBarContainer.alpha = percent
            self.viewCoordinator.tabBarContainer.alpha = percent
            self.viewCoordinator.toolbar.alpha = percent
            
            // Post notification only when bars are fully shown or hidden
            if percent == 0 || percent == 1 {
                NotificationCenter.default.post(
                    name: .browserChromeVisibilityChanged,
                    object: nil,
                    userInfo: ["isHidden": percent == 0]
                )
            }
        }
           
        if animated {
            self.view.layoutIfNeeded()
            UIView.animate(withDuration: animationDuration ?? ChromeAnimationConstants.duration) {
                updateBlock()
                self.view.layoutIfNeeded()
            }
        } else {
            updateBlock()

            // Calling this here is important as it causes the layout to run immediately inside current run loop,
            // instead of deferring it until next update block.
            // Late layout after change here could potentially cause a scroll offset update right before the next one,
            // which may cause an infitie loop layout loop in certain scenarios.
            // See https://app.asana.com/1/137249556945/project/414709148257752/task/1208671955053442 for details.
            self.view.layoutIfNeeded()
        }
    }

    func setNavigationBarHidden(_ hidden: Bool) {
        if hidden { hideKeyboard() }
        
        updateNavBarConstant(hidden ? 0 : 1.0)
        viewCoordinator.omniBar.barView.alpha = hidden ? 0 : 1
        viewCoordinator.tabBarContainer.alpha = hidden ? 0 : 1
        viewCoordinator.statusBackground.alpha = hidden ? 0 : 1
        
    }

    func setRefreshControlEnabled(_ isEnabled: Bool) {
        currentTab?.setRefreshControlEnabled(isEnabled)
    }

    var canHideBars: Bool {
        return !daxDialogsManager.shouldShowFireButtonPulse
    }

    var isToolbarHidden: Bool {
        return viewCoordinator.toolbar.alpha < 1
    }

    var toolbarHeight: CGFloat {
        return viewCoordinator.toolbar.frame.size.height
    }
    
    var barsMaxHeight: CGFloat {
        max(toolbarHeight, viewCoordinator.omniBar.barView.expectedHeight)
    }

    // 1.0 - full size, 0.0 - hidden
    private func updateToolbarConstant(_ ratio: CGFloat) {
        var bottomHeight = toolbarHeight
        if viewCoordinator.addressBarPosition.isBottom {
            // When position is set to bottom, contentContainer is pinned to top
            // of navigationBarContainer, hence the adjustment.
            bottomHeight += viewCoordinator.navigationBarContainer.frame.height
        }
        bottomHeight += view.safeAreaInsets.bottom
        let multiplier = viewCoordinator.toolbar.isHidden ? 1.0 : 1.0 - ratio
        viewCoordinator.constraints.toolbarBottom.constant = bottomHeight * multiplier
        findInPageHeightLayoutConstraint.constant = findInPageView.container.frame.height + view.safeAreaInsets.bottom
    }

    // 1.0 - full size, 0.0 - hidden
    private func updateNavBarConstant(_ ratio: CGFloat) {
        let browserTabsOffset = (viewCoordinator.tabBarContainer.isHidden ? 0 : viewCoordinator.tabBarContainer.frame.size.height)
        let navBarTopOffset = viewCoordinator.navigationBarContainer.frame.size.height + browserTabsOffset
        if !viewCoordinator.tabBarContainer.isHidden {
            let topBarsConstant = -browserTabsOffset * (1.0 - ratio)
            viewCoordinator.constraints.tabBarContainerTop.constant = topBarsConstant
        }
        viewCoordinator.constraints.navigationBarContainerTop.constant = browserTabsOffset + -navBarTopOffset * (1.0 - ratio)
    }

    private func handleFavoriteSelected(_ favorite: BookmarkEntity) {
        guard let url = favorite.urlObject else { return }

        // Handle shortcuts for internal testing
        if let favUrl = favorite.url, let url = URL(string: favUrl), internalUserCommands.handle(url: url) {
            dismissSuggestionTray()
            return
        }

        Pixel.fire(pixel: .favoriteLaunchedWebsite)
        newTabPageViewController?.chromeDelegate = nil
        dismissOmniBar()
        Favicons.shared.loadFavicon(forDomain: url.host, intoCache: .fireproof, fromCache: .tabs)
        if url.isBookmarklet() {
            executeBookmarklet(url)
        } else {
            loadUrl(url)
        }
        showHomeRowReminder()
    }


    private func handleSuggestionSelected(_ suggestion: Suggestion) {
        newTabPageViewController?.chromeDelegate = nil
        dismissOmniBar()
        viewCoordinator.omniBar.cancel()
        switch suggestion {
        case .phrase(phrase: let phrase):
            if let url = URL.makeSearchURL(text: phrase) {
                loadUrl(url)
            } else {
                Logger.lifecycle.error("Couldn't form URL for suggestion: \(phrase, privacy: .public)")
            }

        case .website(url: let url):
            if url.isBookmarklet() {
                executeBookmarklet(url)
            } else {
                loadUrl(url)
            }

        case .bookmark(_, url: let url, _, _):
            loadUrl(url)

        case .historyEntry(_, url: let url, _):
            loadUrl(url)

        case .openTab(title: _, url: let url, tabId: let tabId, _):
            if newTabPageViewController != nil, let tab = tabManager.model.currentTab {
                self.closeTab(tab)
            }
            loadUrlInNewTab(url, reuseExisting: tabId.map(ExistingTabReusePolicy.tabWithId) ?? .any, inheritedAttribution: .noAttribution)

        case .askAIChat(let value):
            openAIChat(value, autoSend: true)

        case .unknown(value: let value), .internalPage(title: let value, url: _, _):
            assertionFailure("Unknown suggestion: \(value)")
        }

        showHomeRowReminder()
    }
}

// MARK: - OmniBarDelegate Methods
extension MainViewController: OmniBarDelegate {

    func isSuggestionTrayVisible() -> Bool {
        suggestionTrayController?.isShowing == true
    }

    func onSelectFavorite(_ favorite: BookmarkEntity) {
        handleFavoriteSelected(favorite)
    }

    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?) {
        openAIChat(query, autoSend: true, tools: tools)
    }

    func didRequestCurrentURL() -> URL? {
        return currentTab?.url
    }
    
    func onSharePressed() {
        shareCurrentURLFromAddressBar()
    }

    func selectedSuggestion() -> Suggestion? {
        return suggestionTrayController?.selectedSuggestion
    }

    func onOmniSuggestionSelected(_ suggestion: Suggestion) {
        autocomplete(selectedSuggestion: suggestion)
    }

    func onOmniQueryUpdated(_ updatedQuery: String) {
        if updatedQuery.isEmpty {
            if newTabPageViewController != nil || !omniBar.isTextFieldEditing {
                hideSuggestionTray()
            } else {
                let didShow = tryToShowSuggestionTray(.favorites)
                if !didShow {
                    hideSuggestionTray()
                }
            }
        } else {
            tryToShowSuggestionTray(.autocomplete(query: updatedQuery))
        }
        
    }

    func onOmniQuerySubmitted(_ query: String) {
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        omniBar.cancel()
        loadQuery(query)
        hideSuggestionTray()
        hideNotificationBarIfBrokenSitePromptShown()
        showHomeRowReminder()
        fireOnboardingCustomSearchPixelIfNeeded(query: query)
    }

    func onPrivacyIconPressed(isHighlighted: Bool) {
        guard !isSERPPresented else { return }

        // Measure first tap of privacy icon button
        if isHighlighted {
            contextualOnboardingPixelReporter.measurePrivacyDashboardOpenedForFirstTime()
        }
        // Dismiss privacy icon animation when showing privacy dashboard
        dismissPrivacyDashboardButtonPulse()

        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        hideSuggestionTray()
        currentTab?.showPrivacyDashboard()
    }

    @objc func onMenuPressed() {
        viewCoordinator.menuToolbarButton.isEnabled = false
        omniBar.cancel()

        // Dismiss privacy icon animation when showing menu
        if !daxDialogsManager.shouldShowPrivacyButtonPulse {
            dismissPrivacyDashboardButtonPulse()
        }

        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        performCancel()
        ActionMessageView.dismissAllMessages()
        launchBrowsingMenu()
    }

    private func launchBrowsingMenu() {
        guard let tab = currentTab ?? tabManager.current(createIfNeeded: true) else {
            return
        }

        let menuEntries: [BrowsingMenuEntry]
        let headerEntries: [BrowsingMenuEntry]

        if newTabPageViewController != nil {
            menuEntries = tab.buildShortcutsMenu()
            headerEntries = []
        } else {
            menuEntries = tab.buildBrowsingMenu(with: menuBookmarksViewModel)
            headerEntries = tab.buildBrowsingMenuHeaderContent()
        }

        let controller = BrowsingMenuViewController.instantiate(headerEntries: headerEntries,
                                                                menuEntries: menuEntries,
                                                                daxDialogsManager: daxDialogsManager)

        controller.modalPresentationStyle = .custom
        controller.onDismiss = {
            self.viewCoordinator.menuToolbarButton.isEnabled = true
        }
        self.present(controller, animated: true) {
            if self.canDisplayAddFavoriteVisualIndicator {
                controller.highlightCell(atIndex: IndexPath(row: tab.favoriteEntryIndex, section: 0))
            }
        }

        self.presentedMenuButton.setState(.closeImage, animated: true)
        tab.didLaunchBrowsingMenu()

        if newTabPageViewController != nil {
            Pixel.fire(pixel: .browsingMenuOpenedNewTabPage)
        } else {
            Pixel.fire(pixel: .browsingMenuOpened)
        }
    }
    
    @objc func onBookmarksPressed() {
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        performCancel()
        segueToBookmarks()
    }

    @objc func onToolbarBookmarksPressed() {
        Pixel.fire(pixel: .bookmarksOpenFromToolbar)
        onBookmarksPressed()
    }

    func onBookmarkEdit() {
        ViewHighlighter.hideAll()
        hideSuggestionTray()
        segueToEditCurrentBookmark()
    }
    
    func onEnterPressed() {
        fireControllerAwarePixel(ntp: .keyboardGoWhileOnNTP, serp: .keyboardGoWhileOnSERP, website: .keyboardGoWhileOnWebsite)
    }

    func fireControllerAwarePixel(ntp: Pixel.Event, serp: Pixel.Event, website: Pixel.Event) {
        if newTabPageViewController != nil {
            Pixel.fire(pixel: ntp)
        } else if let currentTab {
            if currentTab.url?.isDuckDuckGoSearch == true {
                Pixel.fire(pixel: serp)
            } else {
                Pixel.fire(pixel: website)
            }
        }
    }

    func onEditingEnd() -> OmniBarEditingEndResult {
        if isShowingAutocompleteSuggestions {
            return .suspended
        } else {
            dismissOmniBar()
            return .dismissed
        }
    }

    func onSettingsPressed() {
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        segueToSettings()
    }

    func onSettingsLongPressed() {
        if featureFlagger.isFeatureOn(.debugMenu) || isDebugBuild {
            segueToDebugSettings()
        } else {
            segueToSettings()
        }
    }

    func performCancel() {
        dismissOmniBar()
        omniBar.cancel()
        hideSuggestionTray()
        themeColorManager.updateThemeColor()
        self.showMenuHighlighterIfNeeded()
    }

    func onCancelPressed() {
        fireControllerAwarePixel(ntp: .addressBarCancelPressedOnNTP,
                                 serp: .addressBarCancelPressedOnSERP,
                                 website: .addressBarCancelPressedOnWebsite)
        performCancel()
    }

    func onAbortPressed() {
        Pixel.fire(pixel: .stopPageLoad)
        stopLoading()
    }

    func onClearPressed() {
        fireControllerAwarePixel(ntp: .addressBarClearPressedOnNTP,
                                 serp: .addressBarClearPressedOnSERP,
                                 website: .addressBarClearPressedOnWebsite)
    }

    private func newTabShortcutAction() {
        Pixel.fire(pixel: .tabSwitchLongPressNewTab)
        performCancel()
        newTab()
    }

    private var isSERPPresented: Bool {
        guard let tabURL = currentTab?.url else { return false }
        return tabURL.isDuckDuckGoSearch
    }
    
    func onTextFieldWillBeginEditing(_ omniBar: OmniBarView, tapped: Bool) {
        // We don't want any action here if we're still in autocomplete context
        guard !isShowingAutocompleteSuggestions else { return }

        if let currentTab {
            viewCoordinator.omniBar.refreshText(forUrl: currentTab.url, forceFullURL: true)
        }

        if tapped {
            fireControllerAwarePixel(ntp: .addressBarClickOnNTP, serp: .addressBarClickOnSERP, website: .addressBarClickOnWebsite)
        }

        guard newTabPageViewController == nil else { return }
        
        if !skipSERPFlow, isSERPPresented, let query = omniBar.text {
            tryToShowSuggestionTray(.autocomplete(query: query))
        } else {
            tryToShowSuggestionTray(.favorites)
        }
        themeColorManager.updateThemeColor()
    }

    func onTextFieldDidBeginEditing(_ omniBar: OmniBarView) -> Bool {

        let selectQueryText = !(isSERPPresented && !skipSERPFlow)
        skipSERPFlow = false
        
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }

        return selectQueryText
    }

    func onRefreshPressed() {
        hideSuggestionTray()
        currentTab?.refresh()
        hideNotificationBarIfBrokenSitePromptShown(afterRefresh: true)
    }

    func onAccessoryPressed(accessoryType: OmniBarAccessoryType) {
        hideSuggestionTray()

        switch accessoryType {
        case .chat:
            openAIChatFromAddressBar()
        }
    }

    private func shareCurrentURLFromAddressBar() {
        Pixel.fire(pixel: .addressBarShare)
        guard let link = currentTab?.link else { return }
        currentTab?.onShareAction(forLink: link, fromView: viewCoordinator.omniBar.barView.shareButton)
    }

    private func openAIChatFromAddressBar() {

        let isEditing = omniBar.isTextFieldEditing
        let textFieldValue = omniBar.text
        omniBar.endEditing()

        OpenAIChatFromAddressBarHandling().determineOpeningStrategy(
            isTextFieldEditing: isEditing,
            textFieldValue: textFieldValue,
            currentURL: currentTab?.url,
            openWithPromptAndSend: {
                openAIChat($0, autoSend: true)
            },
            open: {
                openAIChat()
            }
        )

        if !aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            DailyPixel.fireDailyAndCount(pixel: .aiChatLegacyOmnibarAichatButtonPressed)
        }
        fireAIChatUsagePixelAndSetFeatureUsed(.openAIChatFromAddressBar)
    }

    private func fireAIChatUsagePixelAndSetFeatureUsed(_ pixel: Pixel.Event) {
        Pixel.fire(pixel: pixel, withAdditionalParameters: featureDiscovery.addToParams([:], forFeature: .aiChat))
        featureDiscovery.setWasUsedBefore(.aiChat)
    }

    func onAccessoryLongPressed(accessoryType: OmniBarAccessoryType) {
        if featureFlagger.isFeatureOn(.debugMenu) || isDebugBuild {
            segueToDebugSettings()
        } else {
            onAccessoryPressed(accessoryType: accessoryType)
        }
    }

    func onVoiceSearchPressed() {
        handleVoiceSearchOpenRequest()
    }

    func onVoiceSearchPressed(preferredTarget: VoiceSearchTarget) {
        handleVoiceSearchOpenRequest(preferredTarget: preferredTarget)
    }

    /// We always want to show the AI Chat button if the keyboard is on focus
    func onDidBeginEditing() {
        omniBar.updateAccessoryType(.chat)
    }

    /// When the keyboard is dismissed we'll apply the previous rule to define the accessory button back to whatever it was
    func onDidEndEditing() {
        omniBar.updateAccessoryType(omnibarAccessoryHandler.omnibarAccessory(for: currentTab?.url))
    }

    // MARK: - Experimental Address Bar (pixels only)
    func onExperimentalAddressBarTapped() {
        fireControllerAwarePixel(ntp: .addressBarClickOnNTP,
                                 serp: .addressBarClickOnSERP,
                                 website: .addressBarClickOnWebsite)
    }

    func onExperimentalAddressBarClearPressed() {
        fireControllerAwarePixel(ntp: .addressBarClearPressedOnNTP,
                                 serp: .addressBarClearPressedOnSERP,
                                 website: .addressBarClearPressedOnWebsite)
    }

    func onExperimentalAddressBarCancelPressed() {
        fireControllerAwarePixel(ntp: .addressBarCancelPressedOnNTP,
                                 serp: .addressBarCancelPressedOnSERP,
                                 website: .addressBarCancelPressedOnWebsite)
    }
}

extension MainViewController: FavoritesOverlayDelegate {

    func favoritesOverlay(_ overlay: FavoritesOverlay, didSelect favorite: BookmarkEntity) {
        handleFavoriteSelected(favorite)
    }
}

// MARK: - AutocompleteViewControllerDelegate Methods
extension MainViewController: AutocompleteViewControllerDelegate {

    func autocompleteDidEndWithUserQuery() {
        if let query = omniBar.text {
            onOmniQuerySubmitted(query
            )
        }
    }

    func autocomplete(selectedSuggestion suggestion: Suggestion) {
        handleSuggestionSelected(suggestion)
    }

    func autocomplete(pressedPlusButtonForSuggestion suggestion: Suggestion) {
        switch suggestion {
        case .phrase(phrase: let phrase), .askAIChat(let phrase):
            viewCoordinator.omniBar.updateQuery(phrase)
        case .website(url: let url):
            if url.isDuckDuckGoSearch, let query = url.searchQuery {
                viewCoordinator.omniBar.updateQuery(query)
            } else if !url.isBookmarklet() {
                viewCoordinator.omniBar.updateQuery(url.absoluteString)
            }
        case .bookmark(title: let title, _, _, _):
            viewCoordinator.omniBar.updateQuery(title)
        case .historyEntry(title: let title, _, _):
            viewCoordinator.omniBar.updateQuery(title)
        case .openTab: break // no-op
        case .unknown(value: let value), .internalPage(title: let value, url: _, _):
            assertionFailure("Unknown suggestion: \(value)")
        }
    }
    
    func autocomplete(highlighted suggestion: Suggestion, for query: String) {

        switch suggestion {
        case .phrase(phrase: let phrase), .askAIChat(let phrase):
            viewCoordinator.omniBar.text = phrase
            if phrase.hasPrefix(query) {
                viewCoordinator.omniBar.selectTextToEnd(query.count)
            }
        case .website(url: let url):
            viewCoordinator.omniBar.text = url.absoluteString
        case .bookmark(title: let title, _, _, _), .openTab(title: let title, url: _, _, _):
            viewCoordinator.omniBar.text = title
            if title.hasPrefix(query) {
                viewCoordinator.omniBar.selectTextToEnd(query.count)
            }
        case .historyEntry(title: let title, let url, _):
            if url.isDuckDuckGoSearch, let query = url.searchQuery {
                viewCoordinator.omniBar.text = query
            }

            if (title ?? url.absoluteString).hasPrefix(query) {
                viewCoordinator.omniBar.selectTextToEnd(query.count)
            }

        case .unknown(value: let value), .internalPage(title: let value, url: _, _):
            assertionFailure("Unknown suggestion: \(value)")
        }
    }

    func autocompleteWasDismissed() {
        dismissOmniBar()
    }

}

extension MainViewController {
    private func handleRequestedURL(_ url: URL) {
        showKeyboardAfterFireButton?.cancel()

        if url.isBookmarklet() {
            executeBookmarklet(url)
        } else {
            loadUrl(url)
        }
    }
}

extension MainViewController: NewTabPageControllerDelegate {

    func newTabPageDidSelectFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        guard let url = favorite.urlObject else { return }
        handleRequestedURL(url)
    }

    func newTabPageDidEditFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        segueToEditBookmark(favorite)
    }

    func newTabPageDidDeleteFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        // no-op for now
    }

    func newTabPageDidRequestFaviconsFetcherOnboarding(_ controller: NewTabPageViewController) {
        faviconsFetcherOnboarding.presentOnboardingIfNeeded(from: self)
    }
}

extension MainViewController: TabDelegate {
    
    var isAIChatEnabled: Bool {
        return aiChatSettings.isAIChatEnabled
    }
    
    func tab(_ tab: TabViewController,
             didRequestNewWebViewWithConfiguration configuration: WKWebViewConfiguration,
             for navigationAction: WKNavigationAction,
             inheritingAttribution: AdClickAttributionLogic.State?) -> WKWebView? {
        hideNotificationBarIfBrokenSitePromptShown()
        showBars()
        currentTab?.dismiss()
        themeColorManager.updateThemeColor()

        // Don't use a request or else the page gets stuck on "about:blank"
        let newTab = tabManager.addURLRequest(nil,
                                              with: configuration,
                                              inheritedAttribution: inheritingAttribution)
        newTab.openedByPage = true
        newTab.openingTab = tab
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.model, scrollToSelected: true)

        newTabAnimation {
            guard self.tabManager.model.tabs.contains(newTab.tabModel) else { return }

            self.dismissOmniBar()
            self.attachTab(tab: newTab)
            self.refreshOmniBar()
        }

        return newTab.webView
    }

    func tabDidRequestClose(_ tab: TabViewController, shouldCreateEmptyTabAtSamePosition: Bool) {
        closeTab(tab.tabModel, andOpenEmptyOneAtSamePosition: shouldCreateEmptyTabAtSamePosition)
    }

    func tabLoadingStateDidChange(tab: TabViewController) {
        if currentTab == tab {
            refreshControls()
            themeColorManager.updateThemeColor()
        }
        tabManager.save()
        tabsBarController?.refresh(tabsModel: tabManager.model)
        // note: model in swipeTabsCoordinator doesn't need to be updated here
        // https://app.asana.com/0/414235014887631/1206847376910045/f
    }
    
    func tab(_ tab: TabViewController, didUpdatePreview preview: UIImage) {
        previewsSource.update(preview: preview, forTab: tab.tabModel)
    }

    func tabWillRequestNewTab(_ tab: TabViewController) -> UIKeyModifierFlags? {
        keyModifierFlags
    }

    func tabDidRequestNewTab(_ tab: TabViewController) {
        _ = findInPageView.resignFirstResponder()
        newTab()
    }

    func tab(_ tab: TabViewController,
             didRequestNewBackgroundTabForUrl url: URL,
             inheritingAttribution attribution: AdClickAttributionLogic.State?) {
        _ = tabManager.add(url: url, inBackground: true, inheritedAttribution: attribution)
        animateBackgroundTab()
    }

    func tab(_ tab: TabViewController,
             didRequestNewTabForUrl url: URL,
             openedByPage: Bool,
             inheritingAttribution attribution: AdClickAttributionLogic.State?) {
        _ = findInPageView.resignFirstResponder()
        hideNotificationBarIfBrokenSitePromptShown()
        if openedByPage {
            showBars()
            newTabAnimation {
                self.loadUrlInNewTab(url, inheritedAttribution: attribution)
                self.currentTab?.openedByPage = true
                self.currentTab?.openingTab = tab
            }
            tabSwitcherButton?.animateUpdate {
                self.tabSwitcherButton?.tabCount += 1
            }
        } else {
            loadUrlInNewTab(url, inheritedAttribution: attribution)
            self.currentTab?.adClickExternalOpenDetector.invalidateForUserInitiated()
            self.currentTab?.openingTab = tab
        }

    }

    func tab(_ tab: TabViewController, didChangePrivacyInfo privacyInfo: PrivacyInfo?) {
        if currentTab == tab {
            viewCoordinator.omniBar.updatePrivacyIcon(for: privacyInfo)
            themeColorManager.updateThemeColor()
        }
    }
    
    func tab(_ tab: TabViewController, didExtractDaxEasterEggLogoURL logoURL: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Logger.daxEasterEgg.debug("Tab received logo - Tab [\(tab.tabModel.uid)] Logo: \(logoURL ?? "nil"), IsCurrent: \(self.currentTab == tab)")
            
            tab.tabModel.daxEasterEggLogoURL = logoURL
            
            // Only update omnibar if this is the currently active tab
            if self.currentTab == tab {
                Logger.daxEasterEgg.debug("Setting omnibar logo: \(logoURL ?? "nil")")
                self.viewCoordinator.omniBar.setDaxEasterEggLogoURL(logoURL)
            }
            // If this is NOT the current tab, the logo will be restored when the tab becomes active via refreshOmniBar()
        }
    }

    func tabDidRequestReportBrokenSite(tab: TabViewController) {
        segueToReportBrokenSite()
    }

    func tab(_ tab: TabViewController, didRequestToggleReportWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        segueToReportBrokenSite(entryPoint: .toggleReport(completionHandler: completionHandler))
    }

    func tabDidRequestAIChat(tab: TabViewController) {
        fireAIChatUsagePixelAndSetFeatureUsed(tab.link == nil ? .browsingMenuAIChatNewTabPage : .browsingMenuAIChatWebPage)
        openAIChat()
    }

    func tabDidRequestBookmarks(tab: TabViewController) {
        Pixel.fire(pixel: .bookmarksButtonPressed,
                   withAdditionalParameters: [PixelParameters.originatedFromMenu: "1"])
        onBookmarksPressed()
    }
    
    func tabDidRequestEditBookmark(tab: TabViewController) {
        onBookmarkEdit()
    }
    
    func tabDidRequestDownloads(tab: TabViewController) {
        segueToDownloads()
    }
    
    func tab(_ tab: TabViewController,
             didRequestAutofillLogins account: SecureVaultModels.WebsiteAccount?,
             source: AutofillSettingsSource) {
        launchAutofillLogins(with: currentTab?.url, currentTabUid: tab.tabModel.uid, source: source, selectedAccount: account)
    }

    func tab(_ tab: TabViewController,
             didRequestDataImport source: DataImportViewModel.ImportScreen, onFinished: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        launchDataImport(source: source, onFinished: onFinished, onCancelled: onCancelled)
    }

    func tabDidRequestSettings(tab: TabViewController) {
        segueToSettings()
    }

    func tab(_ tab: TabViewController,
             didRequestSettingsToLogins account: SecureVaultModels.WebsiteAccount,
             source: AutofillSettingsSource) {
        segueToSettingsAutofillWith(account: account, card: nil, source: source)
    }

    func tab(_ tab: TabViewController, didRequestSettingsToCreditCards card: SecureVaultModels.CreditCard, source: AutofillSettingsSource) {
        segueToSettingsAutofillWith(account: nil, card: card, source: source)
    }

    func tabDidRequestSettingsToCreditCardManagement(_ tab: TabViewController, source: AutofillSettingsSource) {
        segueToSettingsAutofillWith(account: nil, card: nil, showCardManagement: true, source: source)
    }

    func tabContentProcessDidTerminate(tab: TabViewController) {
        findInPageView.done()
        tabManager.invalidateCache(forController: tab)
    }

    func showBars() {
        chromeManager.reset()
    }
    
    func tabDidRequestFindInPage(tab: TabViewController) {
        updateFindInPage()
        _ = findInPageView?.becomeFirstResponder()

        viewCoordinator.hideNavigationBarWithBottomPosition()
    }

    func closeFindInPage(tab: TabViewController) {
        if tab === currentTab {
            findInPageView.done()
        } else {
            tab.findInPage?.done()
            tab.findInPage = nil
        }
    }
    
    func tabDidRequestFireButtonPulse(tab: TabViewController) {
        showFireButtonPulse()
    }
    
    func tabDidRequestPrivacyDashboardButtonPulse(tab: TabViewController, animated: Bool) {
        if animated {
            showPrivacyDashboardButtonPulse()
        } else {
            dismissPrivacyDashboardButtonPulse()
        }
    }

    func tabDidRequestSearchBarRect(tab: TabViewController) -> CGRect {
        searchBarRect
    }

    func tab(_ tab: TabViewController,
             didRequestPresentingTrackerAnimation privacyInfo: PrivacyInfo,
             isCollapsing: Bool) {
        guard currentTab === tab else { return }
        viewCoordinator.omniBar?.startTrackersAnimation(privacyInfo, forDaxDialog: !isCollapsing)
    }
    
    func tabDidRequestShowingMenuHighlighter(tab: TabViewController) {
        showMenuHighlighterIfNeeded()
    }

    private func newTabAnimation(completion: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        let x = view.frame.midX
        let y = view.frame.midY
        
        let theme = ThemeManager.shared.currentTheme
        let view = UIView(frame: CGRect(x: x, y: y, width: 5, height: 5))
        view.layer.borderWidth = 1
        view.layer.cornerRadius = 10
        view.layer.borderColor = theme.barTintColor.cgColor
        view.backgroundColor = theme.backgroundColor
        view.center = self.view.center
        self.view.addSubview(view)
        UIView.animate(withDuration: 0.3, animations: {
            view.frame = self.view.frame
            view.alpha = 0.9
        }, completion: { _ in
            view.removeFromSuperview()
            completion()
        })
    }
    
    func tab(_ tab: TabViewController, didRequestPresentingAlert alert: UIAlertController) {
        present(alert, animated: true)
    }

    func selectTab(_ tab: Tab) {
        guard let index = tabManager.model.indexOf(tab: tab) else { return }
        select(tabAt: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.performCancel()
        }
    }

    func tabCheckIfItsBeingCurrentlyPresented(_ tab: TabViewController) -> Bool {
        return currentTab === tab
    }

    func tab(_ tab: TabViewController, didRequestLoadURL url: URL) {
        loadUrl(url, fromExternalLink: true)
    }

    func tab(_ tab: TabViewController, didRequestLoadQuery query: String) {
        loadQuery(query)
    }
    
    func tabDidRequestRefresh(tab: TabViewController) {
        hideNotificationBarIfBrokenSitePromptShown(afterRefresh: true)
    }

    func tabDidRequestNavigationToDifferentSite(tab: TabViewController) {
        hideNotificationBarIfBrokenSitePromptShown()
    }

}

extension MainViewController: TabSwitcherDelegate {

    private func animateLogoAppearance() {
        newTabPageViewController?.view.transform = CGAffineTransform().scaledBy(x: 0.5, y: 0.5)
        newTabPageViewController?.view.alpha = 0.0
        UIView.animate(withDuration: 0.2, delay: 0.1, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.newTabPageViewController?.view.transform = .identity
            self.newTabPageViewController?.view.alpha = 1.0
        }
    }

    func tabSwitcherDidRequestNewTab(tabSwitcher: TabSwitcherViewController) {
        newTab()
        if newTabPageViewController?.isShowingLogo == true, !aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            animateLogoAppearance()
        }
        themeColorManager.updateThemeColor()
    }

    func tabSwitcher(_ tabSwitcher: TabSwitcherViewController, didSelectTab tab: Tab) {
        selectTab(tab)
        if daxDialogsManager.shouldShowFireButtonPulse {
            showFireButtonPulse()
        }
        themeColorManager.updateThemeColor()
    }
    
    func tabSwitcher(_ tabSwitcher: TabSwitcherViewController, editBookmarkForUrl url: URL) {
        guard let bookmark = self.menuBookmarksViewModel.bookmark(for: url) else { return }
        tabSwitcher.dismiss(animated: true) {
            self.segueToEditBookmark(bookmark)
        }
    }
    
    func tabSwitcherDidBulkCloseTabs(tabSwitcher: TabSwitcherViewController) {
        tabsBarController?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
        updateCurrentTab()
    }

    func tabSwitcher(_ tabSwitcher: TabSwitcherViewController, didRemoveTab tab: Tab) {
        if tabManager.count == 1 {
            // Make sure UI updates finish before dimissing the view.
            // However, as a result, viewDidAppear on the home controller thinks the tab 
            //  switcher is still presented.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                tabSwitcher.dismiss(animated: true) {
                    self.newTabPageViewController?.viewDidAppear(true)
                }
            }
        }
        closeTab(tab)
        
        if daxDialogsManager.shouldShowFireButtonPulse {
            showFireButtonPulse()
        }
    }

    func closeTab(_ tab: Tab, andOpenEmptyOneAtSamePosition shouldOpen: Bool = false) {
        guard let index = tabManager.model.indexOf(tab: tab) else { return }
        hideSuggestionTray()
        hideNotificationBarIfBrokenSitePromptShown()
        themeColorManager.updateThemeColor()

        if shouldOpen {
            let newTab = Tab()
            tabManager.replaceTab(at: index, withNewTab: newTab)
            tabManager.selectTab(newTab)
            showBars() // In case the browser chrome bars are hidden when calling this method
        } else {
            tabManager.remove(at: index)
        }

        updateCurrentTab()
        tabsBarController?.refresh(tabsModel: tabManager.model)
    }

    func tabSwitcherDidRequestForgetAll(tabSwitcher: TabSwitcherViewController) {
        self.forgetAllWithAnimation {
            tabSwitcher.dismiss(animated: false, completion: nil)
        }
    }

    func tabSwitcherDidRequestCloseAll(tabSwitcher: TabSwitcherViewController) {
        self.forgetTabs()
        self.refreshUIAfterClear()
        tabSwitcher.dismiss()
    }

    func tabSwitcherDidReorderTabs(tabSwitcher: TabSwitcherViewController) {
        tabsBarController?.refresh(tabsModel: tabManager.model, scrollToSelected: true)
    }

    func tabSwitcherDidRequestAIChat(tabSwitcher: TabSwitcherViewController) {
        fireAIChatUsagePixelAndSetFeatureUsed(.openAIChatFromTabManager)
        self.aiChatViewControllerManager.openAIChat(on: tabSwitcher)
    }
}

extension MainViewController: BookmarksDelegate {
    func bookmarksDidSelect(url: URL) {

        dismissOmniBar()
        if url.isBookmarklet() {
            executeBookmarklet(url)
        } else {
            loadUrl(url)
        }
    }
}

extension MainViewController: TabSwitcherButtonDelegate {

    func launchNewTab(_ button: TabSwitcherButton) {
        newTabShortcutAction()
    }

    func showTabSwitcher(_ button: TabSwitcherButton) {
        Pixel.fire(pixel: .tabBarTabSwitcherOpened)
        DailyPixel.fireDaily(.tabSwitcherOpenedDaily, withAdditionalParameters: TabSwitcherOpenDailyPixel().parameters(with: tabManager.model.tabs))

        performCancel()
        showTabSwitcher()
    }

    func showTabSwitcher() {
        guard currentTab ?? tabManager.current(createIfNeeded: true) != nil else {
            fatalError("Unable to get current tab")
        }
        hideNotificationBarIfBrokenSitePromptShown()
        updatePreviewForCurrentTab {
            ViewHighlighter.hideAll()
            self.segueToTabSwitcher()
        }
    }
}

extension MainViewController: MenuButtonDelegate {
    
    func showMenu(_ button: MenuButton) {
        onMenuPressed()
    }
    
    func showBookmarks(_ button: MenuButton) {
        Pixel.fire(pixel: .bookmarksButtonPressed,
                   withAdditionalParameters: [PixelParameters.originatedFromMenu: "0"])
        onBookmarksPressed()
    }
}

extension MainViewController: GestureToolbarButtonDelegate {
    
    func singleTapDetected(in sender: GestureToolbarButton) {
        Pixel.fire(pixel: .bookmarksButtonPressed,
                   withAdditionalParameters: [PixelParameters.originatedFromMenu: "0"])
        onBookmarksPressed()
    }
    
    func longPressDetected(in sender: GestureToolbarButton) {
        quickSaveBookmark()
    }
    
}

extension MainViewController: AutoClearWorker {

    func clearNavigationStack() {
        dismissOmniBar()

        if let presented = presentedViewController {
            presented.dismiss(animated: false) { [weak self] in
                self?.clearNavigationStack()
            }
        }
    }

    func forgetTabs() {
        omniBar.endEditing()
        findInPageView?.done()
        tabManager.removeAll()
    }

    func refreshUIAfterClear() {
        showBars()
        attachHomeScreen()
        tabsBarController?.refresh(tabsModel: tabManager.model)

        if !autoClearInProgress {
            // We don't need to refresh tabs if autoclear is in progress as nothing has happened yet
            swipeTabsCoordinator?.refresh(tabsModel: tabManager.model)
        }

        Favicons.shared.clearCache(.tabs)
    }

    @MainActor
    func willStartClearing(_: AutoClear) {
        autoClearInProgress = true
    }

    @MainActor
    func autoClearDidFinishClearing(_: AutoClear, isLaunching: Bool) {
        autoClearInProgress = false
        if autoClearShouldRefreshUIAfterClear && isLaunching == false {
            refreshUIAfterClear()
        }

        autoClearShouldRefreshUIAfterClear = true
    }

    @MainActor
    func forgetData() async {
        await forgetData(applicationState: .unknown)
    }

    @MainActor
    func forgetData(applicationState: DataStoreWarmup.ApplicationState) async {
        guard !clearInProgress else {
            assertionFailure("Shouldn't get called multiple times")
            return
        }
        clearInProgress = true

        // This needs to happen only once per app launch
        if let dataStoreWarmup {
            await dataStoreWarmup.ensureReady(applicationState: applicationState)
            self.dataStoreWarmup = nil
        }

        URLSession.shared.configuration.urlCache?.removeAllCachedResponses()

        let pixel = TimedPixel(.forgetAllDataCleared)

        // If the user is on a version that uses containers, then we'll clear the current container, then migrate it. Otherwise
        //  this is the same as `WKWebsiteDataStore.default()`
        await websiteDataManager.clear(dataStore: DDGWebsiteDataStoreProvider.current())
        pixel.fire(withAdditionalParameters: [PixelParameters.tabCount: "\(self.tabManager.count)"])

        AutoconsentManagement.shared.clearCache()
        daxDialogsManager.clearHeldURLData()

        if self.syncService.authState == .inactive {
            self.bookmarksDatabaseCleaner?.cleanUpDatabaseNow()
        }

        self.forgetTextZoom()
        await historyManager.removeAllHistory()

        self.clearInProgress = false
        
        self.postClear?()
        self.postClear = nil
    }
    
    func stopAllOngoingDownloads() {
        AppDependencyProvider.shared.downloadManager.cancelAllDownloads()
    }
    
    func forgetAllWithAnimation(transitionCompletion: (() -> Void)? = nil, showNextDaxDialog: Bool = false) {
        let spid = Instruments.shared.startTimedEvent(.clearingData)
        Pixel.fire(pixel: .forgetAllExecuted)

        tabManager.prepareAllTabsExceptCurrentForDataClearing()
        
        fireButtonAnimator.animate {
            self.tabManager.prepareCurrentTabForDataClearing()
            self.stopAllOngoingDownloads()
            self.forgetTabs()
            await self.forgetData()
            Instruments.shared.endTimedEvent(for: spid)
            self.daxDialogsManager.resumeRegularFlow()
        } onTransitionCompleted: {
            ActionMessageView.present(message: UserText.actionForgetAllDone,
                                      presentationLocation: .withBottomBar(andAddressBarBottom: self.appSettings.currentAddressBarPosition.isBottom))
            transitionCompletion?()
            self.refreshUIAfterClear()
        } completion: {
            self.privacyProDataReporter.saveFireCount()

            // Ideally this should happen once data clearing has finished AND the animation is finished
            if showNextDaxDialog {
                self.newTabPageViewController?.showNextDaxDialog()
            } else if KeyboardSettings().onNewTab {
                let showKeyboardAfterFireButton = DispatchWorkItem {
                    if !self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
                        self.enterSearch()
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: showKeyboardAfterFireButton)
                self.showKeyboardAfterFireButton = showKeyboardAfterFireButton
            }

            self.daxDialogsManager.clearedBrowserData()

        }
    }
    
    private func showFireButtonPulse() {
        daxDialogsManager.fireButtonPulseStarted()
        guard let window = view.window else { return }
        
        let fireButtonView: UIView?
        if viewCoordinator.toolbar.isHidden {
            fireButtonView = tabsBarController?.fireButton
        } else {
            fireButtonView = viewCoordinator.toolbarFireBarButtonItem.value(forKey: "view") as? UIView
        }
        guard let view = fireButtonView else { return }
        
        if !ViewHighlighter.highlightedViews.contains(where: { $0.view == view }) {
            ViewHighlighter.hideAll()
            ViewHighlighter.showIn(window, focussedOnView: view)
        }
    }

    private func showPrivacyDashboardButtonPulse() {
        viewCoordinator.omniBar.showOrScheduleOnboardingPrivacyIconAnimation()
    }

    private func dismissPrivacyDashboardButtonPulse() {
        daxDialogsManager.setPrivacyButtonPulseSeen()
        viewCoordinator.omniBar.dismissOnboardingPrivacyIconAnimation()
    }

    private func forgetTextZoom() {
        let allowedDomains = fireproofing.allowedDomains
        textZoomCoordinator.resetTextZoomLevels(excludingDomains: allowedDomains)
    }

}

extension MainViewController {

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        updateStatusBarBackgroundColor()
        themeColorManager.updateThemeColor()
    }

    private func updateStatusBarBackgroundColor() {
        let theme = ThemeManager.shared.currentTheme

        if appSettings.currentAddressBarPosition == .bottom {
            viewCoordinator.statusBackground.backgroundColor = theme.backgroundColor
        } else {
            if AppWidthObserver.shared.isPad && traitCollection.horizontalSizeClass == .regular {
                viewCoordinator.statusBackground.backgroundColor = theme.tabsBarBackgroundColor
            } else {
                viewCoordinator.statusBackground.backgroundColor = theme.omniBarBackgroundColor
            }
        }
    }

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme

        updateStatusBarBackgroundColor()

        setNeedsStatusBarAppearanceUpdate()

        view.backgroundColor = theme.mainViewBackgroundColor

        viewCoordinator.navigationBarContainer.backgroundColor = theme.barBackgroundColor
        viewCoordinator.navigationBarContainer.tintColor = theme.barTintColor

        viewCoordinator.toolbar.barTintColor = theme.barBackgroundColor
        viewCoordinator.toolbar.tintColor = UIColor(designSystemColor: .icons)

        viewCoordinator.toolbarTabSwitcherButton.tintColor = theme.barTintColor
        
        viewCoordinator.logoText.tintColor = theme.ddgTextTintColor
    }

}

extension MainViewController: OnboardingDelegate {
        
    func onboardingCompleted(controller: UIViewController) {
        markOnboardingSeen()
        controller.modalTransitionStyle = .crossDissolve
        controller.dismiss(animated: true)
        newTabPageViewController?.onboardingCompleted()
    }
    
    func markOnboardingSeen() {
        tutorialSettings.hasSeenOnboarding = true
    }

    func needsToShowOnboardingIntro() -> Bool {
        !tutorialSettings.hasSeenOnboarding
    }

}

extension MainViewController: OnboardingNavigationDelegate {
    func navigateFromOnboarding(to url: URL) {
        self.loadUrl(url, fromExternalLink: true)
    }

    func searchFromOnboarding(for query: String) {
        self.loadQuery(query)
    }
}

extension MainViewController: UIDropInteractionDelegate {
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: URL.self) || session.canLoadObjects(ofClass: String.self)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }

    // won't drop on to a web view - only works by dropping on to the tabs bar or home screen
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        
        if session.canLoadObjects(ofClass: URL.self) {
            _ = session.loadObjects(ofClass: URL.self) { urls in
                urls.forEach { self.loadUrlInNewTab($0, inheritedAttribution: nil) }
            }
            
        } else if session.canLoadObjects(ofClass: String.self) {
            _ = session.loadObjects(ofClass: String.self) { strings in
                self.loadQuery(strings[0])
            }
            
        }
        
    }
}

// MARK: - VoiceSearchViewControllerDelegate

extension MainViewController: VoiceSearchViewControllerDelegate {

    func voiceSearchViewController(_ controller: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self, let query = query else { return }
            self.handleVoiceSearchCompletion(with: query, for: target)
        }
    }

    private func handleVoiceSearchCompletion(with query: String, for target: VoiceSearchTarget) {
        switch target {
        case .SERP:
            Pixel.fire(pixel: .voiceSearchSERPDone)
            loadQuery(query)

        case .AIChat:
            Pixel.fire(pixel: .voiceSearchAIChatDone)
            performCancel()
            openAIChat(query, autoSend: true)
        }
    }
}

// MARK: - History UIMenu Methods

extension MainViewController {

    private func refreshBackForwardMenuItems() {
        guard let currentTab = currentTab else {
            return
        }
        
        let backMenu = historyMenu(with: currentTab.webView.backForwardList.backList.reversed())
        viewCoordinator.omniBar.barView.backButton.menu = backMenu
        viewCoordinator.toolbarBackButton.setCustomItemMenu(backMenu)

        let forwardMenu = historyMenu(with: currentTab.webView.backForwardList.forwardList)
        viewCoordinator.omniBar.barView.forwardButton.menu = forwardMenu
        viewCoordinator.toolbarForwardButton.setCustomItemMenu(forwardMenu)
    }

    private func historyMenu(with backForwardList: [WKBackForwardListItem]) -> UIMenu {
        let historyItemList = backForwardList.map { BackForwardMenuHistoryItem(backForwardItem: $0) }
        let actions = historyMenuButton(with: historyItemList)
        return UIMenu(title: "", children: actions)
    }
    
    private func historyMenuButton(with menuHistoryItemList: [BackForwardMenuHistoryItem]) -> [UIAction] {
        let menuItems: [UIAction] = menuHistoryItemList.compactMap { historyItem in
            
            return UIAction(title: historyItem.title,
                            subtitle: historyItem.sanitizedURLForDisplay,
                            discoverabilityTitle: historyItem.sanitizedURLForDisplay) { [weak self] _ in
                self?.loadBackForwardItem(historyItem.backForwardItem)
            }
        }
        
        return menuItems
    }
}

// MARK: - AutofillLoginSettingsListViewControllerDelegate
extension MainViewController: AutofillLoginListViewControllerDelegate {
    func autofillLoginListViewControllerDidFinish(_ controller: AutofillLoginListViewController) {
        controller.dismiss(animated: true)
    }
}

// MARK: - AIChatViewControllerManagerDelegate
extension MainViewController: AIChatViewControllerManagerDelegate {
    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestToLoad url: URL) {
        if let tabSwitcher = tabSwitcherController {
            loadUrlInNewTab(url, inheritedAttribution: nil)
            tabSwitcher.dismiss(animated: true)
        } else {
            loadUrlInNewTab(url, inheritedAttribution: nil)
        }
    }

    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didSubmitQuery query: String) {
        self.loadQuery(query)
    }

    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestOpenDownloadWithFileName fileName: String) {
        segueToDownloads()
    }

    func aiChatViewControllerManagerDidReceiveOpenSettingsRequest(_ manager: AIChatViewControllerManager) {
        if let controller = tabSwitcherController {
            controller.dismiss(animated: true) {
                self.segueToSettingsAIChat()
            }
        } else {
            segueToSettingsAIChat()
        }
    }
}

private extension UIBarButtonItem {
    func setCustomItemAction(on target: Any?, action: Selector) {
        if let customControl = customView as? UIControl {
            customControl.addTarget(target, action: action, for: .touchUpInside)
        } else {
            self.action = action
        }
    }

    func setCustomItemMenu(_ menu: UIMenu) {
        if let customControl = customView as? UIButton {
            customControl.menu = menu
        } else {
            self.menu = menu
        }
    }
}

/// This extension allows delegating from the RMF action button when the action type is 'navigation'.  It shadows existing functions.
extension MainViewController: MessageNavigationDelegate { }

extension MainViewController: MainViewEditingStateTransitioning {

    private var isDaxLogoVisible: Bool {
        newTabPageViewController?.isShowingLogo == true
    }

    func hide(with barYOffset: CGFloat, contentYOffset: CGFloat) {
        if isDaxLogoVisible {
            omniBar.barView.layer.sublayerTransform = CATransform3DMakeTranslation(0, barYOffset, 0)
        } else {
            additionalSafeAreaInsets.top = contentYOffset
        }
        omniBar.barView.hideButtons()
    }

    func show() {
        omniBar.barView.layer.sublayerTransform = CATransform3DIdentity
        additionalSafeAreaInsets.top = 0
        omniBar.barView.revealButtons()
    }
}
