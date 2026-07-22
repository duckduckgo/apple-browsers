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

import AIChat
import Bookmarks
import BrokenSitePrompt
import BrowserServicesKit
import Combine
import Common
import FoundationExtensions
import Configuration
import Core
import DataBrokerProtection_iOS
import DDGSync
import DesignResourcesKit
import DesignResourcesKitIcons
import Kingfisher
import MetricBuilder
import NetworkExtension
import Networking
import Onboarding
import os.log
import PageRefreshMonitor
import Persistence
import PixelKit
import PrivacyConfig
import PrivacyDashboard
import RemoteMessaging
import Subscription
import Suggestions
import SwiftUI
import SystemSettingsPiPTutorial
import UIKitExtensions
import UserScript
import VPN
import WebExtensions
import WebKit
import WidgetKit

struct StartupOnboardingDecision {
    let shouldShowOnboarding: Bool

    init(onboardingStatus: LaunchOptionsHandler.OnboardingStatus,
         tutorialSettings: TutorialSettings,
         resumeStepStore: (any KeyedStoring<OnboardingStoringKeys>)? = nil) {
        let resumeStepStore: any KeyedStoring<OnboardingStoringKeys> = if let resumeStepStore { resumeStepStore } else { UserDefaults.app.keyedStoring() }
        switch resumeStepStore.resumeStep {
        case .downloadReasonSelection, .setDefaultBrowser, .aiIntro, .addToDockPromo, .appIconSelection,
             .addressBarPositionSelection, .searchExperienceSelection,
             .duckAIQuerySelection, .interludeDuckAI,
             .searchPrivacySettingsSelection, .aiSearchSettingsSelection, .aiModelSelection,
             .toggleInputModeSelection, .keepDuckAISelection, .duckPlayerSelection:
            shouldShowOnboarding = true
            return
        case .duckAIAnswerStep:
            shouldShowOnboarding = false
            return
        case .none:
            break
        }

        switch onboardingStatus {
        case .notOverridden:
            shouldShowOnboarding = !tutorialSettings.hasSeenOnboarding
        case let .overridden(.developer(completed: isOnboardingCompleted)):
            shouldShowOnboarding = !isOnboardingCompleted
        case let .overridden(.uiTests(completed: isOnboardingCompleted)):
            tutorialSettings.hasSeenOnboarding = isOnboardingCompleted
            shouldShowOnboarding = !tutorialSettings.hasSeenOnboarding
        }
    }
}

class MainViewController: UIViewController {

    /// iOS may deliver buffered accelerometer data as a spurious shake when returning from background.
    private static let shakeIgnoreIntervalAfterForeground: TimeInterval = 1.0

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.shared.currentTheme.statusBarStyle
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        return isIPad ? [.left, .right] : []
    }

    weak var findInPageView: FindInPageView?

    private var isFindInPageChromeLockActive = false
    private var didFindInPageHideChrome = false
    private var findInPageDismissalTimer: Timer?

    weak var notificationView: UIView?

    var chromeManager: BrowserChromeManager!

#if DEBUG || ALPHA
    var automationServer: AutomationServer?
#endif

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

    var isUnifiedURLPredictionEnabled: Bool {
        featureFlagger.isFeatureOn(.unifiedURLPredictor)
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
    let remoteMessagingActionHandler: RemoteMessagingActionHandling
    let remoteMessagingImageLoader: RemoteMessagingImageLoading
    let remoteMessagingPixelReporter: RemoteMessagingPixelReporting?
    let whatsNewRepository: WhatsNewMessageRepository
    let tabManager: TabManager
    let previewsSource: TabPreviewsSource
    let appSettings: AppSettings
    let toggleModeStorage: ToggleModeStoring
    var fireExecutor: FireExecuting
    private var launchTabObserver: LaunchTabNotification.Observer?
    private var isDownloadMenuAlertVisible: Bool?
    var isNewTabPageVisible: Bool {
        newTabPageViewController != nil
    }

    var autoClearInProgress = false
    var autoClearShouldRefreshUIAfterClear = true
    private var hasLoadedInitialView = false
    private weak var burningOverlayView: UIView?
    private(set) var isStartupOnboardingPending = false
    private(set) lazy var startupOnboardingCover = StartupOnboardingCover(
        parentViewController: self,
        fallbackBackgroundColor: themeManager.currentTheme.onboardingBackgroundColor
    )

    let privacyConfigurationManager: PrivacyConfigurationManaging

    let bookmarksDatabase: CoreDataDatabase
    private var favoritesViewModel: FavoritesListInteracting
    let syncService: DDGSyncing
    let aiChatSyncCleaner: AIChatSyncCleaning?
    let syncDataProviders: SyncDataProviders
    let syncPausedStateManager: any SyncPausedStateManaging

    let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
    let duckAiFireModeStorageHandler: DuckAiNativeStorageHandling?

    private let tutorialSettings: TutorialSettings
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    let contextualOnboardingPixelReporter: OnboardingPixelReporting
    var linearOnboardingContext: OnboardingIntroContext?
    private let statisticsStore: StatisticsStore
    let voiceSearchHelper: VoiceSearchHelperProtocol
    let featureFlagger: FeatureFlagger
    private let longPressBarMenuBuilder = LongPressBarMenuBuilder()
    let idleReturnEligibilityManager: IdleReturnEligibilityManaging
    let afterInactivityOptionAdapter: AfterInactivityOptionAdapter
    let lastTabShortcutAdapter: LastTabShortcutAdapter
    let ntpAfterIdleInstrumentation: NTPAfterIdleInstrumentation
    let idleReturnTabCountInstrumentation: IdleReturnTabCountInstrumentation
    let postIdleSessionInstrumentation: PostIdleSessionInstrumentation
    let duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation
    let syncAutoRestoreHandler: SyncAutoRestoreHandling
    private let lastActiveTabStore: LastActiveTabStoring
    let fireModeCapability: FireModeCapable

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
    private var aiChatChromeChipCancellables = Set<AnyCancellable>()
    private var settingsCancellables = Set<AnyCancellable>()
    private var webViewViewportRefreshCancellable: AnyCancellable?
    private lazy var floatingDomainCapsuleController = FloatingDomainCapsuleController { [weak self] in
        self?.setBarsHidden(false, animated: true, customAnimationDuration: nil)
    }
    /// Drives the floating-UI capsule morph frame-by-frame during animated bar reveal/hide so the
    /// pill physically morphs into/out of the bars, matching the scroll transition.
    private let chromeMorphAnimator = ChromeMorphAnimator()
    /// The last true chrome-visibility fraction requested (1 = fully shown, 0 = hidden). Tracked
    /// separately from container alpha because the floating capsule morph drives chrome alpha with a
    /// non-linear handoff ramp, so alpha is no longer a reliable source for the real percent.
    private var lastChromeVisibilityPercent: CGFloat = 1
    private var lastForegroundEntryDate = Date.distantPast
    private var syncRecoveryPromptService: SyncRecoveryPromptService?
    private var currentNTPEscapeHatch: EscapeHatchModel?
    private var hasCompletedInitialLoad = false

    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    let subscriptionDataReporter: SubscriptionDataReporting

    let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    private lazy var faviconLoader: FavoritesFaviconLoading = FavoritesFaviconLoader()
    private lazy var faviconsFetcherOnboarding = FaviconsFetcherOnboarding(syncService: syncService, syncBookmarksAdapter: syncDataProviders.bookmarksAdapter)

    private lazy var browsingMenuHeaderDataSource = BrowsingMenuHeaderDataSource()
    private lazy var browsingMenuHeaderStateProvider = BrowsingMenuHeaderStateProvider()

    lazy var menuBookmarksViewModel: MenuBookmarksInteracting = {
        let viewModel = MenuBookmarksViewModel(bookmarksDatabase: bookmarksDatabase, syncService: syncService)
        viewModel.favoritesDisplayMode = appSettings.favoritesDisplayMode
        return viewModel
    }()

    weak var tabSwitcherController: TabSwitcherViewController?
    var tabSwitcherButton: TabSwitcherButton?
    var omniBarTabSwitcherButton: TabSwitcherButton?

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

    // Duck.ai fire onboarding flow — see MainViewController+DuckAIFireOnboarding.swift
    var duckAIFireOnboardingFlow = DuckAIFireOnboardingFlowContext()

    // Skip SERP flow (focusing on autocomplete logic) and prepare for new navigation when selecting search bar
    private var skipSERPFlow = true

    var postClear: (() -> Void)?
    var clearInProgress = false

    required init?(coder: NSCoder) {
        fatalError("Use init?(code:")
    }

    let featureDiscovery: FeatureDiscovery
    let fireproofing: Fireproofing
    let favicons: FaviconManaging
    let websiteDataManager: WebsiteDataManaging
    let textZoomCoordinatorProvider: TextZoomCoordinatorProviding

    var historyManager: HistoryManaging
    var viewCoordinator: MainViewCoordinator!
    let aiChatSettings: AIChatSettingsProvider
    let aiChatAddressBarExperience: AIChatAddressBarExperienceProviding
    let privacyStats: PrivacyStatsProviding

    let customConfigurationURLProvider: CustomConfigurationURLProviding
    let experimentalAIChatManager: ExperimentalAIChatManager
    let daxDialogsManager: DaxDialogsManaging
    let onboardingSearchExperienceSettingsResolver: OnboardingSearchExperienceSettingsResolver
    let dbpIOSPublicInterface: DBPIOSInterface.PublicInterface?
    let freemiumPIREligibilityChecker: FreemiumPIREligibilityChecking
    let freemiumPIRDebugSettings: FreemiumPIRDebugSettings
    let freemiumDBPUserStateManager: FreemiumDBPUserStateManaging
    let profileStateManager: DBPProfileStateManaging
    let remoteMessagingDebugHandler: RemoteMessagingDebugHandling

    var appDidFinishLaunchingStartTime: CFAbsoluteTime?
    let maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging
    private lazy var themeColorManager: SiteThemeColorManager = {
        SiteThemeColorManager(viewCoordinator: viewCoordinator,
                              currentTabViewController: { [weak self] in self?.currentTab }(),
                              appSettings: appSettings,
                              themeManager: themeManager)
    }()

    private lazy var aiChatViewControllerManager: AIChatViewControllerManager = {
        let manager = AIChatViewControllerManager(privacyConfigurationManager: privacyConfigurationManager,
                                                  contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
                                                  experimentalAIChatManager: .init(featureFlagger: featureFlagger),
                                                  featureFlagger: featureFlagger,
                                                  featureDiscovery: featureDiscovery,
                                                  aiChatSettings: aiChatSettings,
                                                  productSurfaceTelemetry: productSurfaceTelemetry,
                                                  duckAiFireModeStorageHandler: duckAiFireModeStorageHandler)
        manager.delegate = self
        manager.isFireModeProvider = { [weak self] in self?.tabManager.currentBrowsingMode == .fire }
        return manager
    }()

    private lazy var browsingMenuSheetCapability = BrowsingMenuSheetCapability.create()

    let themeManager: ThemeManaging
    let keyValueStore: ThrowingKeyValueStoring
    let recentModalPromptStatusProvider: RecentModalPromptStatusProviding?
    let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging
    let onboardingResumeStepStore: any KeyedStoring<OnboardingStoringKeys>
    var adBlockingAvailability: AdBlockingAvailabilityProviding { tabManager.adBlockingAvailability }

    private var duckPlayerEntryPointVisible = false
    private var subscriptionManager = AppDependencyProvider.shared.subscriptionManager
    
    private let daxEasterEggPresenter: DaxEasterEggPresenting
    private let daxEasterEggLogoStore: DaxEasterEggLogoStoring

    private let internalUserCommands: URLBasedDebugCommands = InternalUserCommands()
    private let launchSourceManager: LaunchSourceManaging
    
    let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging
    let mobileCustomization: MobileCustomization
    let productSurfaceTelemetry: ProductSurfaceTelemetry

    private let aichatFullModeFeature: AIChatFullModeFeatureProviding
    private let aiChatContextualModeFeature: AIChatContextualModeFeatureProviding
    let voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding
    lazy var unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature()
    private lazy var floatingUIManager: FloatingUIManaging = FloatingUIManager(
        featureFlagger: featureFlagger,
        unifiedToggleInputFeature: unifiedToggleInputFeature
    )
    lazy var minimalChromeSettings: MinimalChromeSettingsProviding = MinimalChromeSettings()
    var unifiedToggleInputCoordinator: UnifiedToggleInputCoordinator?
    var unifiedInputStateStore: UnifiedInputStateStore?
    var unifiedToggleInputCancellables = Set<AnyCancellable>()
    var unifiedToggleInputFloatingReturnKeyKeyboardBottomConstraint: NSLayoutConstraint?
    var unifiedToggleInputFloatingReturnKeyInputTopConstraint: NSLayoutConstraint?
    var aiChatTabChatHeaderView: AIChatTabChatHeaderView?

    /// Tracks live Duck.ai voice sessions per tab. Created in `setUpDuckAIVoiceSessionTracker()`.
    var duckAIVoiceSessionTracker: DuckAIVoiceSessionTracker?

    private var iPadAIChatQuery = ""
    /// Owns the iPad popover's suggestion decision + Duck.ai surface lifecycle (built in `loadSuggestionTray`).
    private var popoverSuggestionsCoordinator: PopoverSuggestionsCoordinator?

    private(set) var webExtensionEventsCoordinator: WebExtensionEventsCoordinator?
    func setWebExtensionEventsCoordinator(_ coordinator: WebExtensionEventsCoordinator?) {
        self.webExtensionEventsCoordinator = coordinator
    }

    private(set) var webExtensionManager: WebExtensionManaging?
    func setWebExtensionManager(_ manager: WebExtensionManaging?) {
        self.webExtensionManager = manager
    }

    private var webExtensionLifecycleCoordinatorStorage: Any?
    @available(iOS 18.4, *)
    var webExtensionLifecycleCoordinator: WebExtensionLifecycleCoordinator? {
        get { webExtensionLifecycleCoordinatorStorage as? WebExtensionLifecycleCoordinator }
        set { webExtensionLifecycleCoordinatorStorage = newValue }
    }
    @available(iOS 18.4, *)
    func setWebExtensionLifecycleCoordinator(_ coordinator: WebExtensionLifecycleCoordinator?) {
        webExtensionLifecycleCoordinator = coordinator
    }

    private(set) var darkReaderFeatureSettings: DarkReaderFeatureSettings

    let onboardingManager: OnboardingManaging
    
    private var searchTokenExperiment: SearchTokenExperiment {
        SearchTokenExperiment(featureFlagger: featureFlagger, statisticsStore: statisticsStore)
    }

    private lazy var searchTokenFetcher: SearchTokenFetcher = {
        let settings = SearchTokenExperimentSettings(privacyConfigurationManager: privacyConfigurationManager)
        return SearchTokenFetcher(requester: SearchTokenRequest(tokenURL: .searchToken),
                                  ttlProvider: { settings.tokenTTL },
                                  windowProvider: { settings.refreshWindow })
    }()

    init(
        privacyConfigurationManager: PrivacyConfigurationManaging,
        bookmarksDatabase: CoreDataDatabase,
        historyManager: HistoryManaging,
        homePageConfiguration: HomePageConfiguration,
        syncService: DDGSyncing,
        syncDataProviders: SyncDataProviders,
        userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
        contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        duckAiFireModeStorageHandler: DuckAiNativeStorageHandling? = nil,
        appSettings: AppSettings,
        previewsSource: TabPreviewsSource,
        tabManager: TabManager,
        syncPausedStateManager: any SyncPausedStateManaging,
        subscriptionDataReporter: SubscriptionDataReporting,
        contextualOnboardingLogic: ContextualOnboardingLogic,
        contextualOnboardingPixelReporter: OnboardingPixelReporting,
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
        voiceSearchHelper: VoiceSearchHelperProtocol,
        featureFlagger: FeatureFlagger,
        idleReturnEligibilityManager: IdleReturnEligibilityManaging,
        afterInactivityOptionAdapter: AfterInactivityOptionAdapter,
        lastTabShortcutAdapter: LastTabShortcutAdapter,
        lastActiveTabStore: LastActiveTabStoring = LastActiveTabStore(),
        syncAutoRestoreHandler: SyncAutoRestoreHandling,
        contentScopeExperimentsManager: ContentScopeExperimentsManaging,
        fireproofing: Fireproofing,
        favicons: FaviconManaging,
        textZoomCoordinatorProvider: TextZoomCoordinatorProviding,
        websiteDataManager: WebsiteDataManaging,
        appDidFinishLaunchingStartTime: CFAbsoluteTime?,
        maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging,
        aiChatSettings: AIChatSettingsProvider,
        aiChatSyncCleaner: AIChatSyncCleaning? = nil,
        aiChatAddressBarExperience: AIChatAddressBarExperienceProviding,
        experimentalAIChatManager: ExperimentalAIChatManager = ExperimentalAIChatManager(),
        featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
        themeManager: ThemeManaging,
        keyValueStore: ThrowingKeyValueStoring,
        customConfigurationURLProvider: CustomConfigurationURLProviding,
        systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
        daxDialogsManager: DaxDialogsManaging,
        onboardingSearchExperienceSettingsResolver: OnboardingSearchExperienceSettingsResolver? = nil,
        daxEasterEggPresenter: DaxEasterEggPresenting? = nil,
        daxEasterEggLogoStore: DaxEasterEggLogoStoring = DaxEasterEggLogoStore(),
        dbpIOSPublicInterface: DBPIOSInterface.PublicInterface?,
        freemiumPIREligibilityChecker: FreemiumPIREligibilityChecking,
        freemiumPIRDebugSettings: FreemiumPIRDebugSettings,
        freemiumDBPUserStateManager: FreemiumDBPUserStateManaging,
        profileStateManager: DBPProfileStateManaging,
        launchSourceManager: LaunchSourceManaging,
        winBackOfferVisibilityManager: WinBackOfferVisibilityManaging,
        aichatFullModeFeature: AIChatFullModeFeatureProviding = AIChatFullModeFeature(),
        mobileCustomization: MobileCustomization,
        remoteMessagingActionHandler: RemoteMessagingActionHandling,
        remoteMessagingImageLoader: RemoteMessagingImageLoading,
        remoteMessagingPixelReporter: RemoteMessagingPixelReporting?,
        productSurfaceTelemetry: ProductSurfaceTelemetry,
        fireExecutor: FireExecuting,
        remoteMessagingDebugHandler: RemoteMessagingDebugHandling,
        privacyStats: PrivacyStatsProviding,
        aiChatContextualModeFeature: AIChatContextualModeFeatureProviding = AIChatContextualModeFeature(),
        whatsNewRepository: WhatsNewMessageRepository,
        darkReaderFeatureSettings: DarkReaderFeatureSettings,
        voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding = DuckAIVoiceShortcutFeature(),
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage(),
        onboardingResumeStepStore: (any KeyedStoring<OnboardingStoringKeys>)? = nil,
        onboardingManager: OnboardingManaging,
        recentModalPromptStatusProvider: RecentModalPromptStatusProviding? = nil
    ) {
        self.remoteMessagingActionHandler = remoteMessagingActionHandler
        self.remoteMessagingImageLoader = remoteMessagingImageLoader
        self.remoteMessagingPixelReporter = remoteMessagingPixelReporter
        self.privacyConfigurationManager = privacyConfigurationManager
        self.bookmarksDatabase = bookmarksDatabase
        self.historyManager = historyManager
        self.homePageConfiguration = homePageConfiguration
        self.syncService = syncService
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.syncDataProviders = syncDataProviders
        self.userScriptsDependencies = userScriptsDependencies
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.duckAiFireModeStorageHandler = duckAiFireModeStorageHandler
        self.favoritesViewModel = FavoritesListViewModel(bookmarksDatabase: bookmarksDatabase, favoritesDisplayMode: appSettings.favoritesDisplayMode)
        self.bookmarksCachingSearch = BookmarksCachingSearch(bookmarksStore: CoreDataBookmarksSearchStore(bookmarksStore: bookmarksDatabase))
        self.appSettings = appSettings
        self.aiChatSettings = aiChatSettings
        self.aiChatAddressBarExperience = aiChatAddressBarExperience
        self.experimentalAIChatManager = experimentalAIChatManager
        self.previewsSource = previewsSource
        self.tabManager = tabManager
        self.featureDiscovery = featureDiscovery
        self.themeManager = themeManager
        self.syncPausedStateManager = syncPausedStateManager
        self.subscriptionDataReporter = subscriptionDataReporter
        self.tutorialSettings = tutorialSettings
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.contextualOnboardingPixelReporter = contextualOnboardingPixelReporter
        self.statisticsStore = statisticsStore
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.voiceSearchHelper = voiceSearchHelper
        self.featureFlagger = featureFlagger
        self.idleReturnEligibilityManager = idleReturnEligibilityManager
        self.afterInactivityOptionAdapter = afterInactivityOptionAdapter
        self.lastTabShortcutAdapter = lastTabShortcutAdapter
        self.lastActiveTabStore = lastActiveTabStore
        self.ntpAfterIdleInstrumentation = DefaultNTPAfterIdleInstrumentation(eligibilityManager: idleReturnEligibilityManager)
        self.idleReturnTabCountInstrumentation = DefaultIdleReturnTabCountInstrumentation(eligibilityManager: idleReturnEligibilityManager)
        self.postIdleSessionInstrumentation = DefaultPostIdleSessionInstrumentation(wideEvent: AppDependencyProvider.shared.wideEvent)
        self.duckAIWideEventInstrumentation = DefaultDuckAIWideEventInstrumentation(
            wideEvent: AppDependencyProvider.shared.wideEvent,
            completeOrphanedFlowsOnInit: true
        )
        self.syncAutoRestoreHandler = syncAutoRestoreHandler
        self.fireproofing = fireproofing
        self.favicons = favicons
        self.textZoomCoordinatorProvider = textZoomCoordinatorProvider
        self.websiteDataManager = websiteDataManager
        self.appDidFinishLaunchingStartTime = appDidFinishLaunchingStartTime
        self.maliciousSiteProtectionPreferencesManager = maliciousSiteProtectionPreferencesManager
        self.contentScopeExperimentsManager = contentScopeExperimentsManager
        self.keyValueStore = keyValueStore
        self.recentModalPromptStatusProvider = recentModalPromptStatusProvider
        self.onboardingResumeStepStore = if let onboardingResumeStepStore { onboardingResumeStepStore } else { UserDefaults.app.keyedStoring() }
        self.customConfigurationURLProvider = customConfigurationURLProvider
        self.systemSettingsPiPTutorialManager = systemSettingsPiPTutorialManager
        self.daxDialogsManager = daxDialogsManager
        self.onboardingSearchExperienceSettingsResolver = onboardingSearchExperienceSettingsResolver ?? OnboardingSearchExperienceSettingsResolver(
            onboardingProvider: OnboardingSearchExperience(),
            daxDialogsStatusProvider: daxDialogsManager
        )
        self.daxEasterEggLogoStore = daxEasterEggLogoStore
        self.daxEasterEggPresenter = daxEasterEggPresenter ?? DaxEasterEggPresenter(logoStore: daxEasterEggLogoStore, featureFlagger: featureFlagger)
        self.dbpIOSPublicInterface = dbpIOSPublicInterface
        self.freemiumPIREligibilityChecker = freemiumPIREligibilityChecker
        self.freemiumPIRDebugSettings = freemiumPIRDebugSettings
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.profileStateManager = profileStateManager
        self.launchSourceManager = launchSourceManager
        self.winBackOfferVisibilityManager = winBackOfferVisibilityManager
        self.mobileCustomization = mobileCustomization
        self.aichatFullModeFeature = aichatFullModeFeature
        self.remoteMessagingDebugHandler = remoteMessagingDebugHandler
        self.productSurfaceTelemetry = productSurfaceTelemetry
        self.privacyStats = privacyStats
        self.fireExecutor = fireExecutor
        self.aiChatContextualModeFeature = aiChatContextualModeFeature
        self.whatsNewRepository = whatsNewRepository
        self.darkReaderFeatureSettings = darkReaderFeatureSettings
        self.voiceShortcutFeature = voiceShortcutFeature
        self.toggleModeStorage = toggleModeStorage
        self.fireModeCapability = FireModeCapability.create()
        self.onboardingManager = onboardingManager

        super.init(nibName: nil, bundle: nil)
        
        tabManager.delegate = self
        tabManager.aiChatContentDelegate = self
        tabManager.fireModeDelegate = self
        self.fireExecutor.delegate = self
        bindSyncService()
    }

    deinit {
        chromeMorphAnimator.cancel()
        findInPageDismissalTimer?.invalidate()
    }

    func loadFindInPage() {

        let view = FindInPageView.loadFromXib()
        self.view.addSubview(view)

        let container = view.container!

        // Avoids coercion swiftlint warnings
        let superview = self.view!

        NSLayoutConstraint.activate([

            container.bottomAnchor.constraint(equalTo: superview.keyboardLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            view.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            view.leadingAnchor.constraint(equalTo: superview.leadingAnchor),

        ])

        findInPageView = view

        findInPageView?.delegate = self

        updateFindInPage()
    }
    
    var swipeTabsCoordinator: SwipeTabsCoordinator?

    /// Overlay used to render tab-swipe transitions. Hosts per-tab full-screen snapshots so
    /// the swipe moves chrome+content as a single visual unit instead of as N separately
    /// translated layers. Hidden when not swiping; populated and made visible by
    /// `SwipeTabsCoordinator` at swipe start.
    private var tabSwipeOverlayView: TabSwipeOverlayView?

    private var expandedOmniBarDismissTapGesture: UITapGestureRecognizer?

    lazy var newTabDaxDialogFactory: NewTabDaxDialogFactory = {
        NewTabDaxDialogFactory(
            delegate: self,
            daxDialogsFlowCoordinator: daxDialogsManager,
            onboardingPixelReporter: contextualOnboardingPixelReporter
        )
    }()

    lazy var newTabPageDependencies: SuggestionTrayViewController.NewTabPageDependencies = {
        SuggestionTrayViewController.NewTabPageDependencies(
            favoritesModel: favoritesViewModel,
            homePageMessagesConfiguration: homePageConfiguration,
            subscriptionDataReporting: subscriptionDataReporter,
            newTabDialogFactory: newTabDaxDialogFactory,
            newTabDaxDialogManager: daxDialogsManager,
            onboardingFlowProvider: onboardingManager,
            faviconLoader: faviconLoader,
            faviconsCache: favicons,
            remoteMessagingActionHandler: remoteMessagingActionHandler,
            remoteMessagingImageLoader: remoteMessagingImageLoader,
            remoteMessagingPixelReporter: remoteMessagingPixelReporter,
            appSettings: appSettings,
            subscriptionManager: subscriptionManager,
            internalUserCommands: internalUserCommands)
    }()

    lazy var suggestionTrayDependencies: SuggestionTrayDependencies = {
        SuggestionTrayDependencies(
            favoritesViewModel: favoritesViewModel,
            bookmarksDatabase: bookmarksDatabase,
            historyManager: historyManager,
            tabsModelProvider: { self.tabManager.currentTabsModel },
            featureFlagger: featureFlagger,
            appSettings: appSettings,
            aiChatSettings: aiChatSettings,
            featureDiscovery: featureDiscovery,
            newTabPageDependencies: newTabPageDependencies,
            productSurfaceTelemetry: productSurfaceTelemetry)
    }()

    /// Creates the voice-session tracker on launch so it catches sessions before the switcher opens.
    /// Always created — the rich-card flag gates rendering (in the resolver), not tracking.
    private func setUpDuckAIVoiceSessionTracker() {
        duckAIVoiceSessionTracker = DuckAIVoiceSessionTracker(tabForWebView: { [weak self] webView in
            self?.tabManager.controller(forWebView: webView)?.tabModel
        })
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewCoordinator = MainViewFactory.createViewHierarchy(self,
                                                              aiChatSettings: aiChatSettings,
                                                              aiChatSyncCleaner: aiChatSyncCleaner,
                                                              aiChatAddressBarExperience: aiChatAddressBarExperience,
                                                              voiceSearchHelper: voiceSearchHelper,
                                                              featureFlagger: featureFlagger,
                                                              floatingUIManager: floatingUIManager,
                                                              suggestionTrayDependencies: suggestionTrayDependencies,
                                                              appSettings: appSettings,
                                                              mobileCustomization: mobileCustomization,
                                                              duckAiNativeStorageHandler: duckAiNativeStorageHandler)

        viewCoordinator.navigationBarContainer.allowsOverflowHitTesting = true
        viewCoordinator.navigationBarCollectionView.allowsOverflowHitTesting = true

        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
        floatingDomainCapsuleController.install(in: view, addressBarPosition: appSettings.currentAddressBarPosition)

        setUpToolbarButtonsActions()
        installSwipeTabs()
            
        loadSuggestionTray()
        loadTabsBarIfNeeded()
        attachOmniBar()

        view.addInteraction(UIDropInteraction(delegate: self))
        
        chromeManager = BrowserChromeManager()
        chromeManager.delegate = self
        chromeManager.onUserScrolled = { [weak self] in
            self?.postIdleSessionInstrumentation.pageEngaged()
        }
        initTabButton()
        initBookmarksButton()
        setUpUnifiedToggleInputIfNeeded()
        setUpDuckAIVoiceSessionTracker()
        configureStartupPresentation()
        previewsSource.prepare()
        addLaunchTabNotificationObserver()
        subscribeToEmailProtectionStatusNotifications()
        subscribeToURLInterceptorNotifications()
        subscribeToSettingsDeeplinkNotifications()
        subscribeToNetworkProtectionEvents()
        subscribeToUnifiedFeedbackNotifications()
        subscribeToAIChatSettingsEvents()
        subscribeToAIChatResponseEvents()
        subscribeToRefreshButtonSettingsEvents()
        subscribeToCustomizationSettingsEvents()
        subscribeToDaxEasterEggLogoChanges()

        checkSubscriptionEntitlements()

        registerForKeyboardNotifications()
        registerForPageRefreshPatterns()
        registerForSyncFeatureFlagsUpdates()
        registerForAppBackgroundNotification()
        registerForDownloadMenuAlertNotifications()

        decorate()
        refreshDownloadMenuAlertState(animated: false)

        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)

        _ = AppWidthObserver.shared.willResize(toWidth: view.frame.width)
        applyWidth()

        registerForApplicationEvents()
        registerForCookiesManagedNotification()
        registerForSettingsChangeNotifications()

        tabManager.cleanupTabsFaviconCache()

        // Needs to be called here to established correct view hierarchy
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
        applyCustomizationState()

        mobileCustomization.delegate = self

        installContextualSheetDismissGesture()
    }

    private func configureStartupPresentation() {
        let onboardingStatus = LaunchOptionsHandler().onboardingStatus
        let startupOnboardingDecision = StartupOnboardingDecision(
            onboardingStatus: onboardingStatus,
            tutorialSettings: tutorialSettings,
            resumeStepStore: onboardingResumeStepStore
        )

        // Automation bypass: a UI-test override can mark onboarding already-completed without ever
        // calling onboardingCompleted(controller:), so apply the rollout Duck Player defaults here too.
        if case .overridden(.uiTests(completed: true)) = onboardingStatus, ProcessInfo.isRunningUITests {
            appSettings.applyAdBlockingRolloutDuckPlayerDefaultsIfNeeded(rolloutActive: adBlockingAvailability.areAdBlockingDefaultsActive)
        }

        isStartupOnboardingPending = startupOnboardingDecision.shouldShowOnboarding

        if isStartupOnboardingPending {
            startupOnboardingCover.attach()
        }

        loadInitialViewIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        loadFindInPage()

        productSurfaceTelemetry.dailyActiveUser()
        productSurfaceTelemetry.iPadUsed(isPad: isPad)

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

        restorePendingDuckAIAnswerStepIfNeeded()
        tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)

        _ = AppWidthObserver.shared.willResize(toWidth: view.frame.width)
        applyWidth()

        if daxDialogsManager.shouldShowFireButtonPulse {
            showFireButtonPulse()
        }

        presentSyncRecoveryPromptIfNeeded()

        // Should be safe to call anyway but only really need for this specific scenario
        if #available(iOS 26, *), isPad {
            view.setNeedsUpdateConstraints()
        }
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

    private func fireIPadToggleStateOnAppOpenPixel() {
        guard aiChatAddressBarExperience.isIPadAIToggleExperienceEnabled else { return }

        let pixel: Pixel.Event = aiChatAddressBarExperience.shouldShowModeToggle ? .aiChatIPadToggleEnabledOnAppOpen : .aiChatIPadToggleDisabledOnAppOpen
        DailyPixel.fireDailyAndCount(pixel: pixel)
    }

    private func fireContextualAutoAttachPixel() {
        let isEnabled = "\(aiChatSettings.isAutomaticContextAttachmentEnabled)"
        DailyPixel.fireDaily(.aiChatContextualAutoAttachDAU,
                             withAdditionalParameters: ["is_enabled": isEnabled])
    }

    private func fireAIChatIsEnabledPixel() {
        let isEnabled = "\(aiChatSettings.isAIChatEnabled)"
        DailyPixel.fireDaily(.aiChatIsEnabledDaily,
                             withAdditionalParameters: ["is_enabled": isEnabled])
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
                                                      aiChatSyncCleaner: aiChatSyncCleaner,
                                                      aiChatAddressBarExperience: aiChatAddressBarExperience,
                                                      appSettings: appSettings,
                                                      daxEasterEggPresenter: daxEasterEggPresenter,
                                                      mobileCustomization: mobileCustomization,
                                                      duckAiNativeStorageHandler: duckAiNativeStorageHandler)

        swipeTabsCoordinator = SwipeTabsCoordinator(coordinator: viewCoordinator,
                                                    tabPreviewsSource: previewsSource,
                                                    appSettings: appSettings,
                                                    omnibarDependencies: omnibarDependencies,
                                                    floatingUIManager: floatingUIManager) { [weak self] tab in

            guard tab !== self?.tabManager.currentTabsModel.currentTab else {
                return
            }

            DailyPixel.fire(pixel: .swipeTabsUsedDaily)
            self?.currentTab?.aiChatContextualSheetCoordinator.dismissSheet()
            self?.selectTab(tab)

        } newTab: { [weak self] in
            Pixel.fire(pixel: .swipeToOpenNewTab)
            self?.currentTab?.aiChatContextualSheetCoordinator.dismissSheet()
            self?.newTab()
        } onSwipeStarted: { [weak self] in
            self?.performCancel()
            self?.hideKeyboard()
            self?.updatePreviewForCurrentTab()
        }

        installTabSwipeOverlay()
    }

    private func installTabSwipeOverlay() {
        guard unifiedToggleInputFeature.isAvailable else { return }

        let overlay = TabSwipeOverlayView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0
        view.addSubview(overlay)
        tabSwipeOverlayView = overlay
        swipeTabsCoordinator?.swipeOverlayView = overlay
    }

    func updatePreviewForCurrentTab(completion: (() -> Void)? = nil) {
        assert(Thread.isMainThread)
        
        if !viewCoordinator.logoContainer.isHidden,
           self.tabManager.current()?.link == nil,
           let tab = self.tabManager.currentTabsModel.currentTab {
            // Preview is optional; run completion even if the snapshot fails so the switcher opens on the first tap.
            if let image = viewCoordinator.logoContainer.createImageSnapshot(inBounds: viewCoordinator.contentContainer.frame) {
                previewsSource.update(preview: image, forTab: tab)
            }
            completion?()

        } else if let currentTab = self.tabManager.current(), currentTab.link != nil {
            // Web view
            currentTab.preparePreview(completion: { image in
                if let image {
                    self.previewsSource.update(preview: image,
                                               forTab: currentTab.tabModel)
                }
                completion?()
            })
        } else if let tab = self.tabManager.currentTabsModel.currentTab {
            // Favorites, etc
            if let image = viewCoordinator.contentContainer.createImageSnapshot() {
                previewsSource.update(preview: image, forTab: tab)
            }
            completion?()
        } else {
            completion?()
        }
    }

    func loadSuggestionTray() {

        let controller = SuggestionTrayViewController(favoritesViewModel: self.favoritesViewModel,
                                     bookmarksDatabase: self.bookmarksDatabase,
                                     historyManager: self.historyManager,
                                     tabsModelProvider: { self.tabManager.currentTabsModel },
                                     featureFlagger: self.featureFlagger,
                                     appSettings: self.appSettings,
                                     aiChatSettings: self.aiChatSettings,
                                     featureDiscovery: self.featureDiscovery,
                                     newTabPageDependencies: self.newTabPageDependencies,
                                     productSurfaceTelemetry: self.productSurfaceTelemetry,
                                     hideBorder: false)

        controller.view.frame = viewCoordinator.suggestionTrayContainer.bounds
        controller.newTabPageControllerDelegate = self
        viewCoordinator.suggestionTrayContainer.addSubview(controller.view)

        controller.dismissHandler = dismissSuggestionTray
        controller.autocompleteDelegate = self
        suggestionTrayController = controller

        if isPad {
            popoverSuggestionsCoordinator = PopoverSuggestionsCoordinator(
                dependencies: .init(
                    historyManager: historyManager,
                    bookmarksDatabase: bookmarksDatabase,
                    featureFlagger: featureFlagger,
                    aiChatSettings: aiChatSettings,
                    privacyConfigurationManager: privacyConfigurationManager,
                    aiChatSyncCleaner: aiChatSyncCleaner,
                    duckAiNativeStorageHandler: duckAiNativeStorageHandler,
                    tabsModelProvider: { [weak self] in self?.tabManager.currentTabsModel },
                    isFireTab: { [weak self] in self?.isCurrentTabFireTab() ?? false }),
                tray: controller,
                host: self,
                navigationDelegate: self)
        }
    }

    func loadTabsBarIfNeeded() {
        guard isPad else { return }

        let controller = TabsBarViewController.create()

        addChild(controller)
        controller.delegate = self
        controller.historyManager = historyManager
        controller.fireproofing = fireproofing
        controller.aiChatSettings = aiChatSettings
        controller.featureFlagger = featureFlagger
        controller.keyValueStore = keyValueStore
        controller.tabManager = tabManager
        controller.daxDialogsManager = daxDialogsManager
        controller.fireModeCapability = fireModeCapability
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        viewCoordinator.tabBarContainer.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: viewCoordinator.tabBarContainer.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: viewCoordinator.tabBarContainer.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: viewCoordinator.tabBarContainer.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: viewCoordinator.tabBarContainer.bottomAnchor),
        ])
        tabsBarController = controller
        controller.didMove(toParent: self)
        bindAIChatChromeChipToCurrentTab()
    }

    /// Rebinds the chip's contextual-sheet subscription to the current tab.
    /// Called whenever the active tab changes (transitionTo) or the tabs bar is created.
    func bindAIChatChromeChipToCurrentTab() {
        aiChatChromeChipCancellables.removeAll()

        guard let currentTab else {
            refreshAIChatChromeChip()
            return
        }

        currentTab.aiChatContextualSheetCoordinator.$isSheetPresented
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAIChatChromeChip() }
            .store(in: &aiChatChromeChipCancellables)

        refreshAIChatChromeChip()
    }

    private func refreshAIChatChromeChip() {
        let isSheetPresented = currentTab?.aiChatContextualSheetCoordinator.isSheetPresented ?? false
        // iPhone-only: iPad's tabs-bar chip already indicates sheet state, so avoid a duplicate.
        if UIDevice.current.userInterfaceIdiom == .phone {
            omniBar.barView.updateAIChatButtonForContextualSheet(isPresented: isSheetPresented)
        }
        guard let tabsBarController else { return }
        tabsBarController.updateAIChatChipState(isContextualSheetPresented: isSheetPresented)
    }

    func startAddFavoriteFlow() {
        contextualOnboardingLogic.enableAddFavoriteFlow()
        if tutorialSettings.hasSeenOnboarding {
            newTab()
        }
    }
    
    func startOnboardingFlowIfNotSeenBefore() {
        guard isStartupOnboardingPending else { return }
        segueToDaxOnboarding { [weak self] in
            self?.startupOnboardingCover.detach()
        }
    }

    func presentSyncRecoveryPromptIfNeeded() {
        syncRecoveryPromptService = SyncRecoveryPromptService(
            featureFlagger: featureFlagger,
            syncService: syncService,
            keyValueStore: keyValueStore,
            isOnboardingComplete: !needsToShowOnboardingIntro()
        )

        guard let syncRecoveryPromptService = syncRecoveryPromptService else { return }

        syncRecoveryPromptService.tryPresentSyncRecoveryPrompt(
            from: self,
            onSyncFlowSelected: { [weak self] source in
                self?.segueToSettingsSync(with: source)
            }
        )
    }

    func presentNetworkProtectionStatusSettingsModal(entryPoint: VPNEntryPoint, scrollToStrictRouting: Bool = false) {
        Task {
            if let canShowVPNInUI = try? await subscriptionManager.isFeatureIncludedInSubscription(.networkProtection),
               canShowVPNInUI {
                segueToVPN(source: entryPoint.screenSource, scrollToStrictRouting: scrollToStrictRouting)
            } else {
                segueToDuckDuckGoSubscription(origin: entryPoint.subscriptionFunnelOrigin.rawValue)
            }
        }
    }

    func presentDataBrokerProtectionDashboard() {
        segueToDataBrokerProtection()
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
    // Set at keyboardWillChangeFrame time (before keyboardDidShow) so the web-keyboard scroll guard
    // engages during the show animation, not just after it.
    private var isKeyboardOverlappingContent = false
    private var didSendGestureDismissPixel: Bool = false
    var latestKeyboardFrame: CGRect = .zero

    @objc
    private func keyboardDidShow() {
        keyboardShowing = true
        productSurfaceTelemetry.keyboardActive()
        dismissContextualSheetIfKeyboardIsForBackgroundContent()
        // Keyboard up. Fix minimal chrome bar spot.
        refreshMinimalChromeBottomAnchor()
    }

    private func dismissContextualSheetIfKeyboardIsForBackgroundContent() {
        guard let currentTab,
              currentTab.aiChatContextualSheetCoordinator.isSheetPresented,
              let sheetVC = currentTab.aiChatContextualSheetCoordinator.sheetViewController else {
            return
        }

        // Check if first responder is within the sheet's view hierarchy
        if let firstResponder = UIResponder.currentFirstResponder(),
           firstResponder.isInViewHierarchy(of: sheetVC.view) {
            // Keyboard is for the sheet, don't dismiss
            return
        }

        // Keyboard is for background content (web view), dismiss the sheet
        currentTab.aiChatContextualSheetCoordinator.dismissSheet()
    }

    @objc
    private func keyboardWillHide() {
        if !didSendGestureDismissPixel, newTabPageViewController?.isDragging == true, keyboardShowing {
            Pixel.fire(pixel: .addressBarGestureDismiss)
            didSendGestureDismissPixel = true
        }
        collapseExpandedUTIOnKeyboardDismiss()
    }

    private func collapseExpandedUTIOnKeyboardDismiss() {
        guard unifiedToggleInputFeature.isAvailable,
              currentTab?.isAITab == true,
              let coordinator = unifiedToggleInputCoordinator,
              coordinator.isAITabExpanded,
              currentTab?.aiChatContextualSheetCoordinator.isSheetPresented != true else { return }
        // With a hardware keyboard connected, iOS fires keyboardWillHide even though the
        // text field is still the first responder. Treat that as "still editing" and skip
        // the collapse — otherwise the expanded bar collapses on every focus, making it
        // impossible to type.
        if coordinator.viewController.isInputFirstResponder {
            return
        }
        coordinator.showCollapsed()
    }

    @objc
    private func keyboardDidHide() {
        keyboardShowing = false
        didSendGestureDismissPixel = false

        if #available(iOS 26, *) {
            latestKeyboardFrame = .zero
            adjustUI(withKeyboardFrame: .zero)
        }

        // Checked here (not `keyboardWillHide`) so the find navigator's visibility has settled: it stays visible when a
        // search is confirmed, but is gone when the user dismisses find — which also hides the keyboard.
        if #available(iOS 16.0, *) {
            hideChromeForConfirmedFindInPage()
        }
    }

    private var isAnyAITabUTIState: Bool {
        guard unifiedToggleInputFeature.isAvailable,
              currentTab?.isAITab == true else { return false }
        return unifiedToggleInputCoordinator?.isAITabState == true
    }

    var isNavigationBarEffectivelyAtBottom: Bool {
        if appSettings.currentAddressBarPosition.isBottom {
            return true
        }
        return isAnyAITabUTIState
    }

    /// Keyboard came from omnibar, not web page.
    private var isKeyboardOwnedByOmnibar: Bool {
        if omniBar.isTextFieldEditing { return true }
        if unifiedToggleInputCoordinator?.isOmnibarSession == true { return true }
        if let firstResponder = UIResponder.currentFirstResponder(),
           firstResponder.isInViewHierarchy(of: viewCoordinator.omniBar.barView) {
            return true
        }
        return false
    }

    /// Plain bottom bar. No AI, no UTI, no floating toolbar.
    private var isStandardBottomOmnibar: Bool {
        appSettings.currentAddressBarPosition.isBottom
            && !isAnyAITabUTIState
            && unifiedToggleInputCoordinator?.isOmnibarSession != true
            && !viewCoordinator.isOmnibarInToolbar
    }

    /// Bottom bar hidden behind web keyboard.
    var isBottomAddressBarHiddenForWebKeyboard: Bool {
        isStandardBottomOmnibar && (keyboardShowing || isKeyboardOverlappingContent) && !isKeyboardOwnedByOmnibar
    }

    /// Minimal chrome bar: stick to bottom behind keyboard. Lift above keyboard only when omnibar has
    /// focus. Returns true when pinned to bottom. Safe to call any time.
    @discardableResult
    func refreshMinimalChromeBottomAnchor(duration: TimeInterval = 0.2,
                                          curve: UIView.AnimationOptions = .curveEaseInOut) -> Bool {
        guard isInMinimalChromeLayout, isStandardBottomOmnibar else { return false }
        let pinToBottom = !isKeyboardOwnedByOmnibar
        // Already right? Skip work.
        guard viewCoordinator.isNavigationBarContainerBottomKeyboardBased == pinToBottom else { return pinToBottom }
        viewCoordinator.updateMinimalChromeBottomAnchor(pinnedToScreenBottom: pinToBottom)
        if pinToBottom {
            // Bar dropped to the screen bottom: clear the keyboard-driven layout left from omnibar editing.
            currentTab?.webView.scrollView.contentInset.bottom = 0
            currentTab?.borderView.bottomOffset = 0
            if appSettings.currentAddressBarPosition.isBottom,
               let ntp = newTabPageViewController,
               !ntp.isShowingLogo {
                ntp.additionalSafeAreaInsets.bottom = viewCoordinator.omniBar.barView.expectedHeight
            }
        }
        UIView.animate(withDuration: duration, delay: 0, options: curve) {
            self.viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
            self.currentTab?.borderView.layoutIfNeeded()
        }
        return pinToBottom
    }

    private func setUpToolbarButtonsActions() {

        viewCoordinator.toolbarBackButton.addTarget(self, action: #selector(onBackPressed), for: .touchUpInside)
        viewCoordinator.toolbarForwardButton.addTarget(self, action: #selector(onForwardPressed), for: .touchUpInside)
        viewCoordinator.toolbarPasswordsButton.addTarget(self, action: #selector(onPasswordsPressed), for: .touchUpInside)
        viewCoordinator.toolbarBookmarksButton.addTarget(self, action: #selector(onToolbarBookmarksPressed), for: .touchUpInside)
        viewCoordinator.menuToolbarButton.addTarget(self, action: #selector(onMenuPressed), for: .touchUpInside)

        viewCoordinator.toolbarFireButton.addTarget(self, action: #selector(performCustomizationActionForToolbar), for: .touchUpInside)

        viewCoordinator.menuToolbarButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(onMenuToolbarLongPressed)))
    }

    private func registerForDownloadMenuAlertNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(downloadMenuAlertStateDidChange),
                                               name: .downloadStarted,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(downloadMenuAlertStateDidChange),
                                               name: .downloadFinished,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(downloadMenuAlertStateDidChange),
                                               name: .downloadsSeen,
                                               object: nil)
    }

    @objc private func downloadMenuAlertStateDidChange() {
        refreshDownloadMenuAlertState(animated: true)
    }

    private func refreshDownloadMenuAlertState(animated: Bool) {
        let isVisible = AppDependencyProvider.shared.downloadManager.hasDownloadsNeedingAttention
        let shouldAnimate = animated && isDownloadMenuAlertVisible != isVisible
        isDownloadMenuAlertVisible = isVisible

        viewCoordinator.menuToolbarButton.setMenuAlertVisible(isVisible, animated: shouldAnimate)
        viewCoordinator.omniBar.barView.menuButton.setMenuAlertVisible(isVisible, animated: shouldAnimate)
        unifiedToggleInputCoordinator?.viewController.setMenuAlertVisible(isVisible, animated: shouldAnimate)
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
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onKeepAddressBarVisibleOnIPadChanged),
                                               name: AppUserDefaults.Notifications.keepAddressBarVisibleOnIPadChanged,
                                               object: nil)
    }

    @objc private func onKeepAddressBarVisibleOnIPadChanged() {
        revealChromeIfPinned()
    }

    private func registerForAppBackgroundNotification() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)

        webViewViewportRefreshCancellable = NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard AppWidthObserver.shared.isPad else { return }
                self?.refreshCurrentWebViewViewportAfterForeground()
            }
    }

    @objc private func onAppDidEnterBackground() {
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.appBackgroundedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.sessionCancelledByBackground()

        /// Resign the web view's first responder when backgrounding with the tab switcher
        /// visible. The tab switcher uses .overCurrentContext so the WKWebView stays in the
        /// hierarchy; without this, the web process restores focus on foreground and the
        /// keyboard appears on top of the tab switcher.
        /// https://app.asana.com/1/137249556945/project/414709148257752/task/1213823670012997?focus=true
        if tabSwitcherController != nil {
            currentTab?.webView.resignFirstResponder()
        }
    }

    @objc func onAddressBarPositionChanged() {
        if !isAnyAITabUTIState {
            viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
            refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)
        }
        if isInMinimalChromeLayout {
            applyMinimalChromeWidth()
        }
        updateStatusBarBackgroundColor()
        themeColorManager.updateThemeColor()
    }

    @objc private func onShowFullURLAddressChanged() {
        refreshOmniBar()
    }

    @objc func refreshViewsBasedOnDuckPlayerPresentation(notification: Notification) {
        guard let isVisible = notification.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool else { return }
        duckPlayerEntryPointVisible = isVisible
        // Pill visibility only drives the omnibar separator. A full address-bar refresh here would
        // clobber scroll-hidden chrome (the bar reappears over the floating capsule) and disrupt an
        // active UTI / the NTP.
        updateChromeForDuckPlayer()
    }

    func refreshViewsBasedOnAddressBarPosition(_ position: AddressBarPosition) {
        viewCoordinator.setFloatingUIEnabled(isFloatingUIEnabled)
        switch position {
        case .top:
            swipeTabsCoordinator?.addressBarPositionChanged(isTop: true)
            if shouldResetNavBarContainerBottomForTopPosition() {
                viewCoordinator.constraints.navigationBarContainerBottom.isActive = false
            }

        case .bottom:
            swipeTabsCoordinator?.addressBarPositionChanged(isTop: false)
        }

        viewCoordinator.updateToolbarLayoutForAddressBarPosition(position)
        reconcileAIChromeForCurrentTab()
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)

        omniBar.adjust(for: position)
        adjustNewTabPageSafeAreaInsets(for: position)
        updateChromeForDuckPlayer()
        updateFloatingDomainCapsuleVisibility(for: lastChromeVisibilityPercent)
    }

    private func currentFloatingDomainText() -> String? {
        guard let host = currentTab?.url?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    private func updateFloatingDomainCapsuleVisibility(for barsVisibilityPercent: CGFloat) {
        floatingDomainCapsuleController.update(addressBarPosition: appSettings.currentAddressBarPosition,
                                               isFloatingUIEnabled: isFloatingUIEnabled,
                                               isUnifiedToggleInputActive: unifiedToggleInputCoordinator?.isActive == true,
                                               isAITab: currentTab?.isAITab == true,
                                               isMinimalChromeLayout: isInMinimalChromeLayout,
                                               domain: currentFloatingDomainText(),
                                               barsVisibilityPercent: barsVisibilityPercent,
                                               expandedFrame: floatingBarExpandedFrame(),
                                               reduceMotion: UIAccessibility.isReduceMotionEnabled,
                                               in: view)
    }

    /// True when the floating domain capsule morph is driving the chrome transition (floating UI on,
    /// not minimal chrome / unified toggle input / AI tab).
    private var isFloatingCapsuleActive: Bool {
        FloatingUILayoutPolicy.shouldShowFloatingDomainCapsule(
            isFloatingUIEnabled: isFloatingUIEnabled,
            isUnifiedToggleInputActive: unifiedToggleInputCoordinator?.isActive == true,
            isAITab: currentTab?.isAITab == true,
            isMinimalChromeLayout: isInMinimalChromeLayout
        )
    }

    /// The bar's stable resting rect (in `view` coordinates) that the floating domain capsule morphs
    /// from/to. Computed from layout metrics rather than the live bar frame so it stays fixed while
    /// the bar slides off-screen during the transition.
    private func floatingBarExpandedFrame() -> CGRect {
        // Match the correct size for the capsule.
        if appSettings.currentAddressBarPosition.isBottom, viewCoordinator.isOmnibarInToolbar {
            let capsuleFrame = viewCoordinator.toolbar.restingCapsuleFrame(in: view)
            if !capsuleFrame.isEmpty {
                return capsuleFrame
            }
        }

        let expectedHeight = viewCoordinator.omniBar.barView.expectedHeight
        let width = viewCoordinator.omniBar.barView.frame.width
        let centerX = view.bounds.midX
        let centerY: CGFloat
        switch appSettings.currentAddressBarPosition {
        case .top:
            centerY = view.safeAreaInsets.top + expectedHeight / 2
        case .bottom:
            centerY = view.bounds.maxY - view.safeAreaInsets.bottom - expectedHeight / 2
        }
        return CGRect(x: centerX - width / 2, y: centerY - expectedHeight / 2, width: width, height: expectedHeight)
    }

    /// Alpha for the real chrome (nav bar / tabs / toolbar) during a bars transition. In the floating
    /// capsule morph the chrome stays hidden through the resize band and only fades in over
    /// `[handoffStart, 1]`, so the morph pill owns the visible transition. Everywhere else it tracks
    /// `percent` linearly (unchanged behaviour).
    private func chromeAlpha(for percent: CGFloat) -> CGFloat {
        guard isFloatingCapsuleActive, !UIAccessibility.isReduceMotionEnabled else { return percent }
        let handoffStart = FloatingDomainCapsuleController.handoffStart
        return max(0, min(1, (percent - handoffStart) / (1 - handoffStart)))
    }

    private func shouldResetNavBarContainerBottomForTopPosition() -> Bool {
        return unifiedToggleInputCoordinator?.isActive != true
    }

    private func updateChromeForDuckPlayer() {
        themeColorManager.updateThemeColor()
        let position = appSettings.currentAddressBarPosition
        switch position {
        case .top: break // no-op
        case .bottom:
            // Re-assert bottom-bar spacing so the field isn't stuck in the top-glass (clear) state.
            // A Duck Player round-trip can leave `isUsingSmallTopSpacing` stale, dropping the field's
            // opaque fill (and its contrast) until restart.
            viewCoordinator.omniBar.adjust(for: .bottom)
            viewCoordinator.omniBar.barView.restoreFloatingFieldAppearance()
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
            // In floating top mode the NTP spans behind the glass omnibar; inset its content so it
            // rests below the bar while still being able to underflow it on scroll.
            let topInset = isFloatingTopContentBehindBar ? viewCoordinator.omniBar.barView.expectedHeight * currentBarsVisibility : 0
            newTabPageViewController?.additionalSafeAreaInsets = .init(top: topInset, left: 0, bottom: 0, right: 0)
        case .bottom:
            newTabPageViewController?.additionalSafeAreaInsets = .init(top: 0, left: 0, bottom: viewCoordinator.omniBar.barView.expectedHeight, right: 0)
        }
    }

    /// Scales the floating-top NTP content inset with chrome visibility so it collapses to zero in
    /// lock-step as the bar hides, matching the web view's underflow behaviour. No-op outside
    /// floating top mode.
    private func updateFloatingTopNewTabPageInset(for barsVisibilityPercent: CGFloat) {
        guard isFloatingTopContentBehindBar else { return }
        newTabPageViewController?.additionalSafeAreaInsets.top = viewCoordinator.omniBar.barView.expectedHeight * barsVisibilityPercent
    }

    /// True when content (web/NTP) is laid out spanning behind the glass omnibar in floating top
    /// mode, matching the coordinator's content-container top anchor. The unified toggle input owns
    /// its own top layout, so the floating-top inset must not be applied while it's active.
    private var isFloatingTopContentBehindBar: Bool {
        FloatingUILayoutPolicy.shouldApplyFloatingTopContentInset(
            isFloatingUIEnabled: isFloatingUIEnabled,
            addressBarPosition: appSettings.currentAddressBarPosition,
            isUnifiedToggleInputAffectingLayout: unifiedToggleInputCoordinator?.isActive == true
        )
    }

    @objc func onShowFullSiteAddressChanged() {
        refreshOmniBar()
    }

    /// True from the start of a rotation until its eased UTI-height settle completes, so the
    /// keyboard handler defers the landscape cap to that settle instead of fighting it.
    private var isUTIRotating = false

    /// Based on https://stackoverflow.com/a/46117073/73479
    ///  Handles iPhone X devices properly.
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {

        guard let userInfo = notification.userInfo,
            let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }

        latestKeyboardFrame = keyboardFrame
        let duration: TimeInterval = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
        let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

        adjustUI(withKeyboardFrame: keyboardFrame, in: duration, animationCurve: animationCurve)
    }

    // swiftlint:disable:next cyclomatic_complexity
    func adjustUI(withKeyboardFrame keyboardFrame: CGRect, in duration: TimeInterval = 0.2, animationCurve: UIView.AnimationOptions = .curveEaseInOut) {
        var keyboardHeight = keyboardFrame.size.height

        let omniBarHeight = viewCoordinator.omniBar.barView.expectedHeight
        let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
        let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 0, dy: -additionalSafeAreaInsets.bottom)
        let intersection = safeAreaFrame.intersection(keyboardFrameInView)
        let keyboardVisible = intersection.height > 0
        isKeyboardOverlappingContent = keyboardVisible
        keyboardHeight = keyboardFrameInView.height
        updateUnifiedToggleInputKeyboardVisibility(keyboardVisible)

        let coordinator = unifiedToggleInputCoordinator
        let isAITabCollapsed = coordinator?.displayState == .aiTab(.collapsed)
        let isBottomExpandedUTIKeyboardAnchored = coordinator?.isInputEditing == true
            && coordinator?.cardPosition == .bottom
            && viewCoordinator.isNavigationBarContainerBottomKeyboardBased

        // Keep the field's cap current as the keyboard reframes; the eased recompute owns it during rotation.
        if !isUTIRotating {
            updateLandscapeEditingCap()
        }

        let baseInputHeight: CGFloat
        if let coordinator, coordinator.isInputEditing {
            baseInputHeight = coordinator.editingHeight()
        } else {
            baseInputHeight = omniBarHeight
        }

        if !isNavigationBarEffectivelyAtBottom {
            if !isAITabCollapsed, let coordinator, coordinator.isOmnibarSession {
                self.viewCoordinator.constraints.navigationBarContainerHeight.constant = baseInputHeight
            }
            return
        }

        // Minimal chrome: bar sticks to bottom. Pinned = done. Editing = fall through.
        if isInMinimalChromeLayout, isStandardBottomOmnibar {
            if refreshMinimalChromeBottomAnchor(duration: duration, curve: animationCurve) {
                return
            }
        }

        if isStandardBottomOmnibar, keyboardVisible, !isKeyboardOwnedByOmnibar {
            // Web keyboard. Leave bar at rest so keyboard hides it.
            viewCoordinator.constraints.navigationBarContainerHeight.constant = omniBarHeight
            if let currentTab {
                currentTab.webView.scrollView.contentInset.bottom = 0
                currentTab.borderView.bottomOffset = 0
            }
            UIView.animate(withDuration: duration, delay: 0, options: animationCurve) {
                self.viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()
                self.currentTab?.borderView.layoutIfNeeded()
            }
            return
        }

        let containerHeight = keyboardHeight > 0 ? intersection.height - toolbarHeight + baseInputHeight : 0
        if !isAITabCollapsed {
            let newHeight = isBottomExpandedUTIKeyboardAnchored ? baseInputHeight : max(baseInputHeight, containerHeight)
            self.viewCoordinator.constraints.navigationBarContainerHeight.constant = newHeight
        }

        if isAnyAITabUTIState, let currentTab {
            // The web view is anchored to the input bar's top (.unifiedToggleInput mode),
            // so it never extends behind the input — no bottom inset is needed.
            if currentTab.webView.scrollView.contentInset.bottom != 0 {
                currentTab.webView.scrollView.contentInset = .init(top: 0, left: 0, bottom: 0, right: 0)
            }
        } else if appSettings.currentAddressBarPosition.isBottom, let currentTab {
            let inset = intersection.height > 0 ? omniBarHeight : 0
            currentTab.webView.scrollView.contentInset = .init(top: 0, left: 0, bottom: inset, right: 0)

            let bottomOffset = intersection.height > 0 ? containerHeight - omniBarHeight : 0
            currentTab.borderView.bottomOffset = -bottomOffset
        }

        if appSettings.currentAddressBarPosition.isBottom,
           let ntp = self.newTabPageViewController,
           !ntp.isShowingLogo {
            self.newTabPageViewController?.additionalSafeAreaInsets.bottom = max(omniBarHeight, containerHeight)
        }

        UIView.animate(withDuration: duration, delay: 0, options: animationCurve) {
            self.viewCoordinator.navigationBarContainer.superview?.layoutIfNeeded()

            if self.appSettings.currentAddressBarPosition.isBottom,
               !self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
               let ntp = self.newTabPageViewController,
               ntp.isShowingLogo {
                self.newTabPageViewController?.additionalSafeAreaInsets.bottom = max(omniBarHeight, containerHeight)
            } else {
                self.newTabPageViewController?.viewSafeAreaInsetsDidChange()
            }
            self.currentTab?.borderView.layoutIfNeeded()
        }
    }

    private func initTabButton() {
        assert(tabSwitcherButton == nil)

        tabSwitcherButton = TabSwitcherStaticButton(showMenuOnLongPress: fireModeCapability.isFireModeEnabled)

        tabSwitcherButton?.delegate = self
        viewCoordinator.toolbarHandler.setTabSwitcherView(tabSwitcherButton!)

        assert(tabSwitcherButton != nil)

        viewCoordinator.toolbarTabSwitcherView.isAccessibilityElement = true
        viewCoordinator.toolbarTabSwitcherView.accessibilityTraits = .button

        // Omnibar tab switcher button (for iPhone landscape combined bar)
        let omniBarTabSwitcher = TabSwitcherStaticButton(showMenuOnLongPress: fireModeCapability.isFireModeEnabled)
        omniBarTabSwitcher.delegate = self
        omniBarTabSwitcher.translatesAutoresizingMaskIntoConstraints = false
        let container = viewCoordinator.omniBar.barView.tabSwitcherContainerView
        container.addSubview(omniBarTabSwitcher)
        NSLayoutConstraint.activate([
            omniBarTabSwitcher.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            omniBarTabSwitcher.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            omniBarTabSwitcher.widthAnchor.constraint(equalToConstant: 34),
            omniBarTabSwitcher.heightAnchor.constraint(equalToConstant: 44),
        ])
        omniBarTabSwitcherButton = omniBarTabSwitcher

        // Omnibar fire button (for iPhone landscape combined bar)
        viewCoordinator.omniBar.barView.onFirePressed = { [weak self] in
            self?.performCustomizationActionForToolbar()
        }
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
        return needsToShowOnboardingIntro() ? [.portrait] : [.allButUpsideDown]
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
            if let url = URL(trimmedAddressBarString: urlString, useUnifiedLogic: isUnifiedURLPredictionEnabled), url.isValid(usingUnifiedLogic: isUnifiedURLPredictionEnabled) {
                self.loadUrlInNewTab(url, inheritedAttribution: nil)
            } else {
                self.loadQuery(urlString)
            }
        })
    }

    private func loadInitialView() {
        if tabManager.currentTabsModel.tabs.isEmpty && tabManager.currentTabsModel.allowsEmpty {
            showTabSwitcher()
            return
        }

        if tabManager.currentTabsModel.currentTab?.link != nil {
            guard let tab = tabManager.current(createIfNeeded: true) else {
                fatalError("Unable to create tab")
            }
            attachTab(tab: tab)
        } else {
            attachHomeScreen()
        }
    }

    private func loadInitialViewIfNeeded() {
        guard !hasLoadedInitialView else { return }
        hasLoadedInitialView = true
        loadInitialView()
        hasCompletedInitialLoad = true
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
    }
    
    private lazy var escapeHatchModelBuilder = EscapeHatchModelBuilder(
        tabManager: tabManager,
        lastActiveTabStore: lastActiveTabStore,
        idleReturnEligibilityManager: idleReturnEligibilityManager,
        afterInactivityOptionAdapter: afterInactivityOptionAdapter,
        lastTabShortcutAdapter: lastTabShortcutAdapter,
        instrumentation: ntpAfterIdleInstrumentation
    )

    /// Re-presents the tab switcher after a burn. No-op when the NTP isn't showing.
    private func restoreTabSwitcherOnlyHatchAfterBurn() {
        guard let controller = newTabPageViewController,
              let currentTab = tabManager.currentTabsModel.currentTab,
              currentTab.fireTab == false else {
            return
        }
        let model = escapeHatchModelBuilder.makeTabSwitcherOnly(targetTab: currentTab, router: self)
        controller.setEscapeHatch(model)
        currentNTPEscapeHatch = model
        configureUnifiedInputEscapeHatch(model)
    }

    /// True when an escape hatch action runs in focus mode (reads the persistent omnibar-session state, which
    /// survives the card tap that dismisses the keyboard).
    private var isEscapeHatchInFocusMode: Bool {
        omniBar.isTextFieldEditing || unifiedToggleInputCoordinator?.isOmnibarSession == true
    }

    /// Restores the keyboard after an escape-hatch burn that started in focus mode, using the unified-input
    /// session when active (symmetric with `dismissOmniBar`) and the legacy omnibar otherwise.
    private func restoreFocusModeAfterBurnIfNeeded(wasInFocusMode: Bool) {
        guard wasInFocusMode else { return }
        if let coordinator = unifiedToggleInputCoordinator, coordinator.isOmnibarSession {
            coordinator.activateInput()
        } else {
            enterSearch()
        }
    }

    /// True for escape-hatch burns — these handle focus themselves in `restoreFocusModeAfterBurnIfNeeded`,
    /// so the generic post-fire keyboard fallback is skipped for them.
    private func isEscapeHatchBurn(_ request: FireRequest) -> Bool {
        request.source == .escapeHatch
    }

    private func buildEscapeHatch(openedAfterIdle: Bool) -> EscapeHatchModel? {
        guard openedAfterIdle else { return nil }
        return escapeHatchModelBuilder.makeAfterIdleHatch(router: self)
    }

    fileprivate func attachHomeScreen(isNewTab: Bool = false, allowingKeyboard: Bool = false, previousTab: TabViewController? = nil, openedAfterIdle: Bool = false) {
        guard !autoClearInProgress else { return }

        if tabManager.currentTabsModel.tabs.isEmpty && tabManager.currentTabsModel.allowsEmpty {
            showTabSwitcher()
            return
        }

        // Reset chrome state on every NTP attach — the previous tab may have been a Duck.ai tab
        // with the AI header shown and the standard toolbar hidden. Some attach paths
        // (e.g. tab switcher long-press → newTab) don't go through `refreshControls`, so
        // without this the user lands on NTP with no visible bars.
        viewCoordinator.hideAITabChrome()
        reconcileToolbarVisibilityForCurrentTab()

        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)
        refreshViewsBasedOnAddressBarPosition(appSettings.currentAddressBarPosition)

        viewCoordinator.logoContainer.isHidden = false
        findInPageView?.isHidden = true
        chromeManager.detach()

        currentTab?.dismiss()
        removeHomeScreen()

        let hatch = buildEscapeHatch(openedAfterIdle: openedAfterIdle)
        homePageConfiguration.refresh(openedAfterIdle: hatch != nil)

        // Access the tab model directly as we don't want to create a new tab controller here
        guard let tabModel = tabManager.currentTabsModel.currentTab else {
            fatalError("No tab model")
        }
        
        let shouldSaveTabs = tabModel.viewed == false || tabModel.openedAfterIdle != openedAfterIdle

        // Attaching HomeScreen means it's going to be displayed immediately.
        // This value gets updated on didAppear so after we leave this function so **after** `refreshControls` is done already, which leads to dot being visible on tab switcher icon on newly opened tab page.
        tabModel.viewed = true
        tabModel.openedAfterIdle = openedAfterIdle
        if shouldSaveTabs {
            tabManager.save()
        }

        let newTabDaxDialogFactory = NewTabDaxDialogFactory(delegate: self, daxDialogsFlowCoordinator: daxDialogsManager, onboardingPixelReporter: contextualOnboardingPixelReporter)
        let narrowLayoutInLandscape = aiChatSettings.isAIChatSearchInputUserSettingsEnabled

        let controller = NewTabPageViewController(isFocussedState: false,
                                                  openedAfterIdle: hatch != nil,
                                                  dismissKeyboardOnScroll: true,
                                                  tab: tabModel,
                                                  interactionModel: favoritesViewModel,
                                                  homePageMessagesConfiguration: homePageConfiguration,
                                                  subscriptionDataReporting: subscriptionDataReporter,
                                                  newTabDialogFactory: newTabDaxDialogFactory,
                                                  daxDialogsManager: daxDialogsManager,
                                                  onboardingFlowProvider: onboardingManager,
                                                  faviconLoader: faviconLoader,
                                                  remoteMessagingActionHandler: remoteMessagingActionHandler,
                                                  remoteMessagingImageLoader: remoteMessagingImageLoader,
                                                  remoteMessagingPixelReporter: remoteMessagingPixelReporter,
                                                  appSettings: appSettings,
                                                  faviconsCache: favicons,
                                                  subscriptionManager: subscriptionManager,
                                                  internalUserCommands: internalUserCommands,
                                                  narrowLayoutInLandscape: narrowLayoutInLandscape,
                                                  floatingUIManager: floatingUIManager
        )

        controller.delegate = self
        controller.chromeDelegate = self

        newTabPageViewController = controller

        controller.setEscapeHatch(hatch)
        controller.setChromeLayoutContext(isBorderSuppressed: isInMinimalChromeLayout)
        currentNTPEscapeHatch = hatch

        if hasCompletedInitialLoad {
            lastActiveTabStore.recordActiveTab(uid: tabModel.uid)
        }

        configureUnifiedInputEscapeHatch(hatch)

        // Suppress the NTP before it enters the view hierarchy so the Dax logo can't flash
        // on the one frame between addToContentContainer and the async alpha-0 set inside
        // presentChatPathOnboardingCompletionIfNeeded. Restored by NewTabPageViewController
        // on every dismissal path.
        if daxDialogsManager.chatPathPhase == .trackerToEOJ && aiChatSettings.isAIChatEnabled {
            controller.view.alpha = 0
        }

        addToContentContainer(controller: controller)
        viewCoordinator.logoContainer.isHidden = true
        adjustNewTabPageSafeAreaInsets(for: appSettings.currentAddressBarPosition)

        // This has to happen after the new tab controller is created so that it knows to set the buttons correctly
        // ie remove back/forward and show bookmarks/passwords
        // but also before any other UI updates so that data from the old tab doesn't find its way into the new one
        refreshControls()
        updateScrollInteractionIfNeeded()
        presentContextualOnboardingDialogIfNeeded()

        // It's possible for this to be called when in the background of the
        //  switcher, and we only want to show the pixel when it's actually
        // about to shown to the user.
        if presentedViewController == nil || presentedViewController?.isBeingDismissed == true {
            fireNewTabPixels()
            fireNTPShownInstrumentation(openedAfterIdle: openedAfterIdle, hatch: hatch)
        }

        // Suppress keyboard-on-new-tab when an NTP onboarding dialog is about to appear:
        // viewDidAppear fires after this function and shows the dialog, but the editing state
        // created here would immediately cover it.
        // Also suppress when the chat-path completion dialog (presentChatPathOnboardingCompletionIfNeeded)
        // is scheduled to fire: it drives its own beginEditing, and a premature activation here
        // causes the Dax logo to blink (disappear–reappear) before the completion dialog shows.
        let chatPathCompletionPending = daxDialogsManager.chatPathPhase == .trackerToEOJ && aiChatSettings.isAIChatEnabled
        if isNewTab && allowingKeyboard && KeyboardSettings().onNewTab
            && !daxDialogsManager.subscriptionPromotionPending
            && !chatPathCompletionPending {
            omniBar.beginEditing(animated: true)
        }

        syncService.scheduler.requestSyncImmediately()
    }

    private func configureUnifiedInputEscapeHatch(_ hatch: EscapeHatchModel?) {
        guard let hatch else {
            clearEscapeHatch()
            return
        }
        unifiedToggleInputCoordinator?.setEscapeHatch(hatch)
    }

    private func fireNTPShownInstrumentation(openedAfterIdle: Bool, hatch: EscapeHatchModel?) {
        ntpAfterIdleInstrumentation.ntpShown(afterIdle: openedAfterIdle)
        // Fire the card impression once per presentation here (not from the card's onAppear): the same hatch
        // model is mounted in several hosts — NTP, suggestions, AI-chat history — so a view-level hook counts
        // once per mount.
        if hatch?.isReturnToTabCardVisible == true {
            ntpAfterIdleInstrumentation.escapeHatchShown()
        }
        if openedAfterIdle {
            postIdleSessionInstrumentation.sessionStarted(surface: .ntp)
        }
    }

    func fireNewTabPixels() {
        Pixel.fire(.homeScreenShown, withAdditionalParameters: [:])
        productSurfaceTelemetry.newTabPageUsed()
        let favoritesCount = favoritesViewModel.favorites.count
        let bucket = HomePageDisplayDailyPixelBucket(favoritesCount: favoritesCount)
        DailyPixel.fire(pixel: .newTabPageDisplayedDaily, withAdditionalParameters: [
            "FavoriteCount": bucket.value,
            PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue
        ])
    }

    fileprivate func removeHomeScreen() {
        newTabPageViewController?.willMove(toParent: nil)
        newTabPageViewController?.dismiss()
        newTabPageViewController = nil
        clearEscapeHatch()
    }

    @IBAction func onFirePressed() {
        let wasContextualFireOnboardingDialogVisible = daxDialogsManager.isShowingFireDialog

        func showFireConfirmation() {
            let presenter = FireConfirmationPresenter()
            let source: UIView = findFireButton() ?? viewCoordinator.toolbar
            presenter.presentFireConfirmation(
                on: self,
                attachPopoverTo: source,
                tabViewModel: tabManager.viewModelForCurrentTab(),
                pixelSource: .browsing,
                fireContext: .default(daxDialogsManager: daxDialogsManager),
                isSingleTab: tabManager.currentTabsModel.count == 1,
                browsingMode: tabManager.currentBrowsingMode,
                onConfirm: { [weak self] fireRequest in
                    guard let self else { return }
                    if wasContextualFireOnboardingDialogVisible {
                        contextualOnboardingPixelReporter.measureFireButtonOnboardingDeleteConfirmed()
                    }
                    forgetAllWithAnimation(request: fireRequest) {}
                },
                onCancel: { [weak self] in
                    guard let self else { return }
                    if wasContextualFireOnboardingDialogVisible {
                        contextualOnboardingPixelReporter.measureFireButtonOnboardingDismissButtonTapped()
                    }
                }
            )
        }

        let browsingModeParam = [PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue]
        Pixel.fire(pixel: .forgetAllPressedBrowsing, withAdditionalParameters: browsingModeParam)
        DailyPixel.fire(pixel: .forgetAllPressedBrowsingDaily, withAdditionalParameters: browsingModeParam)

        performActionIfAITab { DailyPixel.fireDailyAndCount(pixel: .aiChatFireButtonTapped) }

        hideNotificationBarIfBrokenSitePromptShown()
        wakeLazyFireButtonAnimator()

        let isDuckAIFireOnboardingFlow = duckAIFireOnboardingFlow.state == .awaitingFirstResponse ||
            duckAIFireOnboardingFlow.state == .active
        // Keep the fire onboarding dialog visible until the burn action is confirmed.
        if !isDuckAIFireOnboardingFlow {
            currentTab?.dismissContextualDaxFireDialog()
        }
        ViewHighlighter.hideAll()

        if isDuckAIFireOnboardingFlow {
            // During the Duck.ai fire onboarding: single "Delete This Chat" action only,
            // whether the contextual dialog has already appeared or is still pending.
            contextualOnboardingPixelReporter.measureDuckAIFireButtonCTAAction()
            presentDuckAIFireConfirmation()
            performCancel()
            return
        }

        showFireConfirmation()

        performCancel()
    }

    @objc func onPasswordsPressed() {
        launchAutofillLogins(source: .newTabPageToolbar)
    }

    func onQuickFirePressed() {
        wakeLazyFireButtonAnimator()
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .quickFire)
        forgetAllWithAnimation(request: request) {}
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
        lastForegroundEntryDate = Date()

        fireExperimentalAddressBarPixel()
        fireIPadToggleStateOnAppOpenPixel()
        fireContextualAutoAttachPixel()
        fireAIChatIsEnabledPixel()
        fireKeyboardSettingsPixels()
        fireTemporaryTelemetryPixels()
        idleReturnTabCountInstrumentation.recordAppForeground(
            tabs: tabManager.allTabsModel.tabs,
            browsingMode: tabManager.currentBrowsingMode.pixelParamValue)
        skipSERPFlow = true

        /// Dismiss any keyboard restored by WKWebView when returning to foreground
        /// with the tab switcher visible. The tab switcher uses .overCurrentContext so
        /// the WKWebView remains in the hierarchy and its web process can restore focus
        /// on a text input, causing the keyboard to appear on top of the tab switcher.
        /// https://app.asana.com/1/137249556945/project/414709148257752/task/1213823670012997?focus=true
        if tabSwitcherController != nil {
            currentTab?.webView.resignFirstResponder()
        }

        // Show Fire Pulse only if Privacy button pulse should not be shown. In control group onboarding `shouldShowPrivacyButtonPulse` is always false.
        if daxDialogsManager.shouldShowFireButtonPulse && !daxDialogsManager.shouldShowPrivacyButtonPulse {
            showFireButtonPulse()
        }
    }

    /// Forces a viewport-size IPC to the WebContent process after foreground. Works around a
    /// WKWebView bug where iOS's iPad multitasking snapshot cycle can leave the page stuck on a
    /// stale `window.outerWidth` / `innerHeight`, breaking `vh`/`vw`-based layouts.
    /// https://app.asana.com/1/137249556945/project/1201011656765697/task/1214469654462812?focus=true
    private func refreshCurrentWebViewViewportAfterForeground() {
        guard let webView = currentTab?.webView else { return }
        let originalFrame = webView.frame
        guard originalFrame.width > 0, originalFrame.height > 1 else { return }

        var nudged = originalFrame
        nudged.size.height -= 1
        webView.frame = nudged

        DispatchQueue.main.async { [weak webView] in
            webView?.frame = originalFrame
        }
    }

    private func fireTemporaryTelemetryPixels() {
        // Sent as individual pixels to avoid creating parameter combinations that can identify users
        let fireButtonAnim = appSettings.currentFireButtonAnimation.rawValue
        DailyPixel.fireDaily(.temporaryTelemetrySettingsClearDataAnimation(animation: fireButtonAnim))

        let customizationState = mobileCustomization.state
        let addressBarButton = customizationState.currentAddressBarButton.rawValue
        DailyPixel.fireDaily(.temporaryTelemetrySettingsCustomizedAddressBarButton(button: addressBarButton))

        let toolbarButton = customizationState.currentToolbarButton.rawValue
        DailyPixel.fireDaily(.temporaryTelemetrySettingsCustomizedToolbarButton(button: toolbarButton))
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
    func loadQueryInNewTab(_ query: String, reuseExisting: ExistingTabReusePolicy? = .none, fromExternalLink: Bool = false) {
        dismissOmniBar()
        guard let url = URL.makeSearchURL(query: query, useUnifiedLogic: isUnifiedURLPredictionEnabled) else {
            Logger.lifecycle.error("Couldn't form URL for query: \(query, privacy: .public)")
            return
        }

        loadUrlInNewTab(url, reuseExisting: reuseExisting, inheritedAttribution: nil, fromExternalLink: fromExternalLink)
    }

    /// Load URL in a new tab, with option to reuse an existing tab.
    ///
    /// - Note: New user-initiated entry paths should route through `loadUrlRespectingAIBoundary` first so the Duck.ai ↔ web boundary rule is honored. Direct callers must justify the bypass.
    ///
    /// - Parameters:
    ///   - url: The URL to be loaded.
    ///   - reuseExisting: The policy for reusing an existing tab. Defaults to `none`, meaning no reuse.
    ///   - inheritedAttribution: The attribution state to be inherited from a parent tab, if any.
    ///   - fromExternalLink: A flag indicating if the URL is from an external link. Defaults to `false`.
    ///   - voiceMode: When true, marks the new tab as opened from voice search.
    ///   - completion: Optional closure run once the new/selected tab is in place. When `clearInProgress`
    ///     is true at call time, this fires only after the data clear completes (via `postClear`).
    ///     Timing relative to UI refresh differs by exit path: the URL-reuse branch fires this before
    ///     `refreshOmniBar`/tab-bar refresh; all other branches fire it after. Callers should not rely
    ///     on chrome state being settled inside the closure.
    func loadUrlInNewTab(_ url: URL, reuseExisting: ExistingTabReusePolicy? = .none, inheritedAttribution: AdClickAttributionLogic.State?, fromExternalLink: Bool = false, voiceMode: Bool = false, completion: (() -> Void)? = nil) {

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
                completion?()
                return
            }
            // Check if a tab presenting a New Tab page should be reused.
            else if reuseExisting != .none, let existing = tabManager.firstHomeTab() {
                if autoClearInProgress {
                    autoClearShouldRefreshUIAfterClear = false
                }
                tabManager.select(existing, dismissCurrent: false)
                loadUrl(url, fromExternalLink: fromExternalLink)
            }
            // Add a new tab if no existing tab is reused.
            else {
                addTab(url: url, inheritedAttribution: inheritedAttribution, fromExternalLink: fromExternalLink, voiceMode: voiceMode)
            }

            refreshOmniBar()
            refreshTabIcon()
            refreshControls()
            tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
            swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
            // Rebind the chip to the newly-current tab — this path (e.g. the Duck.ai chip
            // opening a chat in a new tab) doesn't go through transitionTo.
            bindAIChatChromeChipToCurrentTab()
            completion?()
        }

        if clearInProgress {
            // Compose with any already-deferred worker — back-to-back `loadUrlInNewTab` during the same clear must not drop the first's completion.
            let previous = postClear
            postClear = {
                previous?()
                worker()
            }
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

    func loadQuery(_ query: String) {
        guard let url = URL.makeSearchURL(query: query, useUnifiedLogic: isUnifiedURLPredictionEnabled, queryContext: currentTab?.url) else {
            Logger.general.error("Couldn't form URL for query \"\(query, privacy: .public)\" with context \"\(self.currentTab?.url?.shortDescription ?? "<nil>", privacy: .public)\"")
            return
        }
        // Make sure that once query is submitted, we don't trigger the non-SERP flow
        skipSERPFlow = false
        loadUrlRespectingAIBoundary(url)
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
    
    /// Loads content into the current AI Chat tab with optional query, auto-send, payload, onboarding flow, and tools.
    ///
    /// - Parameters:
    ///   - query: Optional query string to load in AI Chat
    ///   - autoSend: Whether to automatically send the query. Defaults to `false`.
    ///   - payload: Optional payload data for AI Chat. Defaults to `nil`.
    ///   - flowType: Optional onboarding flow type to hand off to Duck.ai.
    ///   - tools: Optional RAG tools available in AI Chat. Defaults to `nil`.
    private func load(_ query: String? = nil,
                      autoSend: Bool = false,
                      payload: Any? = nil,
                      flowType: AIChatOnboardingFlowType = .default,
                      tools: [AIChatRAGTool]? = nil,
                      modelId: String? = nil,
                      reasoningEffort: AIChatReasoningEffort? = nil,
                      images: [AIChatNativePrompt.NativePromptImage]? = nil,
                      files: [AIChatNativePrompt.NativePromptFile]? = nil) {
        guard let currentTab else {
            assertionFailure("load called with no current tab")
            return
        }
        if currentTab.tabModel.link == nil {
            ntpAfterIdleInstrumentation.barUsedFromNTP(afterIdle: currentTab.tabModel.openedAfterIdle)
        }
        postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
        prepareTabForRequest {
            currentTab.load(
                query,
                autoSend: autoSend,
                payload: payload,
                flowType: flowType,
                tools: tools,
                modelId: modelId,
                reasoningEffort: reasoningEffort,
                images: images,
                files: files
            )
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

        guard let tab = tabManager.current(createIfNeeded: true) else {
            assertionFailure("prepareTabForRequest: no current tab available")
            return
        }

        tab.tabModel.openedAfterIdle = false
        request()
        lastActiveTabStore.recordActiveTab(uid: tab.tabModel.uid)
        dismissOmniBar()
        transitionTo(tab: tab, from: nil)
    }

    private func addTab(url: URL?, inheritedAttribution: AdClickAttributionLogic.State?, fromExternalLink: Bool = false, voiceMode: Bool = false) {
        let tab = tabManager.add(url: url, inheritedAttribution: inheritedAttribution)
        tab.inferredOpenerContext = .external
        tab.isVoiceModeRequested = voiceMode

        // Mark tab as external launch if opened from external URL or shortcut
        if fromExternalLink {
            tabManager.markTabAsExternalLaunch(tab.tabModel)
            // For external launches, only the new tab should suppress tracker animations
            tabManager.setSuppressTrackerAnimationOnFirstLoad(for: tab.tabModel, shouldSuppress: true)
        }

        currentTab?.aiChatContextualSheetCoordinator.dismissSheet()
        dismissOmniBar()
        resetUnifiedToggleInputForTabTransition(to: tab)
        attachTab(tab: tab)
    }

    private func resetUnifiedToggleInputForTabTransition(to tab: TabViewController) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        coordinator.setContentOverlaySuppressed(false)
        coordinator.deactivateToOmnibar()
        if !tab.isAITab {
            coordinator.hide()
            coordinator.unbind()
        }
    }

    private func transitionTo(tab: TabViewController?, from previousTab: TabViewController?) {
        guard let tab else { return }
        previousTab?.aiChatContextualSheetCoordinator.dismissSheet()
        previousTab?.tabModel.openedAfterIdle = false
        dismissSystemFindNavigator(for: previousTab)
        previousTab?.dismiss()
        hideNotificationBarIfBrokenSitePromptShown()

        resetUnifiedToggleInputForTabTransition(to: tab)

        let shouldSaveTabs = tab.tabModel.viewed == false
        tab.tabModel.viewed = true
        if shouldSaveTabs {
            tabManager.save()
        }

        if tab.link == nil {
            attachHomeScreen(previousTab: previousTab)
        } else {
            attachTab(tab: tab)
        }
        themeColorManager.updateThemeColor()
        tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        bindAIChatChromeChipToCurrentTab()
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        if daxDialogsManager.shouldShowFireButtonPulse {
            showFireButtonPulse()
        }

        if #available(iOS 18.4, *) {
            if let previousTab {
                webExtensionEventsCoordinator?.didDeselectTabs([previousTab])
            }
            webExtensionEventsCoordinator?.didSelectTabs([tab])
            webExtensionEventsCoordinator?.didActivateTab(tab, previousActiveTab: previousTab)
        }
    }

    private func attachTab(tab: TabViewController) {
        if hasCompletedInitialLoad {
            lastActiveTabStore.recordActiveTab(uid: tab.tabModel.uid)
        }
        // Switching tabs invalidates the per-tab iPad suggestion surfaces; drop them so the next
        // focus rebuilds fresh (avoids a stale/empty popover carried over from the previous tab).
        teardownPopoverSuggestions()
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
        tab.updateWebViewBottomAnchor(for: currentBarsVisibility)

        if isInMinimalChromeLayout {
            tab.borderView.isBottomVisible = appSettings.currentAddressBarPosition.isBottom
        }

        refreshControls()
        updateScrollInteractionIfNeeded()
    }

    /// iOS 26 scroll-edge chrome interactions, tracked together so they can be torn down and
    /// reattached as a unit whenever the visible page changes (see `updateScrollInteractionIfNeeded`).
    private var scrollEdgeInteractions: [UIInteraction] = []

    private func addToContentContainer(controller: UIViewController) {
        viewCoordinator.contentContainer.isHidden = false
        addChild(controller)
        viewCoordinator.contentContainer.subviews.forEach { $0.removeFromSuperview() }
        viewCoordinator.contentContainer.addSubview(controller.view)

        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.frame = viewCoordinator.contentContainer.bounds
        controller.didMove(toParent: self)
    }

    func updateCurrentTab() {
        // prepopulate VC for current tab if needed
        if let currentTab = tabManager.current(createIfNeeded: true) {
            transitionTo(tab: currentTab, from: nil)
            viewCoordinator.omniBar.endEditing()
        } else if !tabManager.currentTabsModel.allowsEmpty {
            attachHomeScreen()
        } else {
            showTabSwitcher()
        }
        bindAIChatChromeChipToCurrentTab()
    }

    fileprivate func refreshControls() {
        refreshTabIcon()
        refreshMenuButtonState()
        refreshOmniBar()
        refreshBackForwardButtons()
        refreshBackForwardMenuItems()
        updateChromeForDuckPlayer()
        refreshMiddleButton()
        // Belt-and-braces reconciliation. Most explicit transitions also call this directly
        // (NTP attach, AI-tab refresh, etc.); doing it here too means any future state-change
        // hook that fires `refreshControls` self-corrects the toolbar's hidden state without
        // the caller having to remember.
        reconcileToolbarVisibilityForCurrentTab()
    }

    private func presentContextualOnboardingDialogIfNeeded() {
        // In Duck.ai tailored the completion dialog is presented explicitly from `MainViewController.onboardingCompleted`.
        // Without this gate, the flow would attempt to present the completion dialog
        // twice — once from the post-fire tab switch and again on `onboardingCompleted`.
        guard onboardingManager.currentOnboardingFlow == .default else { return }

        DispatchQueue.main.async { [weak self] in
            self?.presentChatPathOnboardingCompletionIfNeeded()
        }
    }

    private func refreshMiddleButton() {
        applyCustomizationForToolbar(mobileCustomization.state)
    }

    private func refreshTabIcon() {
        viewCoordinator.toolbarTabSwitcherView.accessibilityHint = UserText.numberOfTabs(tabManager.currentTabsModel.count)
        assert(tabSwitcherButton != nil)
        let count = tabManager.currentTabsModel.count
        let hasUnread = tabManager.currentTabsModel.hasUnread
        let isFireMode = tabManager.currentBrowsingMode == .fire
        tabSwitcherButton?.tabCount = count
        tabSwitcherButton?.hasUnread = hasUnread
        tabSwitcherButton?.isFireMode = isFireMode
        aiChatTabChatHeaderView?.setTabIconState(count: count, hasUnread: hasUnread, isFireMode: isFireMode)
        omniBarTabSwitcherButton?.tabCount = count
        omniBarTabSwitcherButton?.hasUnread = hasUnread
        omniBarTabSwitcherButton?.isFireMode = isFireMode
    }

    private func refreshTabBar() {
        tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel)
    }

    /// Home tabs consult the setting + app-wide last-used; existing tabs derive from URL.
    func initialOmnibarToggleMode(for tab: Tab) -> TextEntryMode {
        let resolved: TextEntryMode
        if tab.isHomeTab {
            resolved = aiChatSettings.defaultOmnibarMode
                .resolvedTextEntryMode { self.toggleModeStorage.restore() }
        } else {
            // iPad never auto-selects Duck.ai for an AI tab — the toggle starts in search.
            resolved = (tab.isAITab && !isPad) ? .aiChat : .search
        }
        return resolved.displayed(isAIChatSearchInputEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
    }

    func refreshOmniBar() {
        updateOmniBarLoadingState()
        viewCoordinator.omniBar.refreshFireMode(fireMode: isCurrentTabFireTab())
        // A fresh NTP has no `TabViewController` yet; drive UTI from the tab model so fire-mode still applies.
        unifiedToggleInputCoordinator?.updateIsFireTab(isCurrentTabFireTab())

        guard let tab = currentTab, tab.link != nil else {
            viewCoordinator.omniBar.stopBrowsing()
            // Clear Dax Easter Egg logo when no tab is active
            viewCoordinator.omniBar.setDaxEasterEggLogoURL(nil)
            if let tabModel = tabManager.currentTabsModel.currentTab {
                viewCoordinator.omniBar.setSelectedTextEntryMode(initialOmnibarToggleMode(for: tabModel))
                // Only activate from the model when there's no TabViewController to drive
                // refreshUnifiedToggleInput(for:) below — otherwise it would fire activateForTab
                // a second time for the same uid, causing redundant attachment teardown.
                if currentTab == nil {
                    unifiedToggleInputCoordinator?.activateForTab(tabModel.uid)
                }
            }
            updateBrowsingMenuHeaderDataSource()
            if let tab = currentTab {
                refreshUnifiedToggleInput(for: tab)
            } else if let coordinator = unifiedToggleInputCoordinator, coordinator.isActive {
                // An active omnibar session means the address bar was just activated (e.g. by
                // launchNewSearch after a subscription promo dismissal on a tab with no VC yet).
                // Hiding the coordinator here would tear it down before the keyboard can appear.
                // refreshUnifiedToggleInput carries its own preserveOmnibarSession guard; mirror
                // that protection for this nil-tab path.
                guard !coordinator.isOmnibarSession else { return }
                coordinator.hide()
                coordinator.unbind()
                viewCoordinator.hideAITabChrome()
                applyUnifiedInputChromeBackground(.standardChrome)
            }
            updateFloatingDomainCapsuleVisibility(for: lastChromeVisibilityPercent)
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

        let logoURL = logoURLForCurrentPage(tab: tab)
        viewCoordinator.omniBar.setDaxEasterEggLogoURL(logoURL)

        if tab.isAITab && (aichatFullModeFeature.isAvailable || DevicePlatform.isIpad) {
            // AI tabs use branding UI rather than the standard toggle setup.
            viewCoordinator.omniBar.enterAIChatMode()
        } else {
            viewCoordinator.omniBar.startBrowsing()
            viewCoordinator.omniBar.setSelectedTextEntryMode(initialOmnibarToggleMode(for: tab.tabModel))
        }

        restorePostFireAddressBarPickerIfNeeded()

        refreshUnifiedToggleInput(for: tab)

        if isInMinimalChromeLayout != isMinimalChromeMode() {
            applyWidth()
        }

        updateBrowsingMenuHeaderDataSource()
        updateFloatingDomainCapsuleVisibility(for: lastChromeVisibilityPercent)
    }

    private func updateBrowsingMenuHeaderDataSource() {
        guard browsingMenuSheetCapability.isEnabled else { return }

        var easterEggLogoURL: String?
        if let tab = currentTab {
            easterEggLogoURL = logoURLForCurrentPage(tab: tab)
        }

        browsingMenuHeaderStateProvider.update(
            dataSource: browsingMenuHeaderDataSource,
            isNewTabPage: newTabPageViewController != nil,
            isAITab: currentTab?.isAITab ?? false,
            usesDuckAILogo: unifiedToggleInputFeature.isAvailable,
            isError: currentTab?.isError ?? false,
            hasLink: currentTab?.link != nil,
            url: currentTab?.url,
            title: currentTab?.title,
            easterEggLogoURL: easterEggLogoURL
        )
    }

    private func updateOmniBarLoadingState() {
        if currentTab?.isLoading == true {
            omniBar.startLoading()
        } else {
            omniBar.stopLoading()
        }
    }

    /// - Parameter animated: animate the UTI collapse; pass `false` when a full-screen surface (tab switcher / new tab) immediately follows.
    func dismissOmniBar(animated: Bool = true) {
        hideSuggestionTray()
        teardownPopoverSuggestions()
        viewCoordinator.omniBar.endEditing()
        deactivateUnifiedToggleInputOmnibarSession(animated: animated)
        refreshOmniBar()
    }

    private var isModeToggleInAIChatMode: Bool {
        guard aiChatAddressBarExperience.shouldShowModeToggle,
              let omniBarVC = viewCoordinator.omniBar as? OmniBarViewController else {
            return false
        }
        return omniBarVC.selectedTextEntryMode == .aiChat
    }

    private func hideNotificationBarIfBrokenSitePromptShown(afterRefresh: Bool = false) {
        guard brokenSitePromptViewHostingController != nil else { return }
        brokenSitePromptViewHostingController = nil
        hideNotification()
    }

    func refreshBackForwardButtons() {
        viewCoordinator.omniBar.isBackButtonEnabled = viewCoordinator.toolbarBackButton.isEnabled
        viewCoordinator.omniBar.isForwardButtonEnabled = viewCoordinator.toolbarForwardButton.isEnabled
    }
  
    var orientationPixelWorker: DispatchWorkItem?

    /// A chrome hide/show morph left in flight by a fling just before rotating would keep scrubbing
    /// the omnibar/capsule layout each frame against mid-rotation geometry, causing a flicker.
    /// Settle it to its committed state now; the completion block resets the bars as usual.
    func cancelMorphAnimatorIfNeedded() {
        if chromeMorphAnimator.isAnimating {
            chromeMorphAnimator.cancel()
            applyBarsVisibilityState(lastChromeVisibilityPercent, postChromeVisibilityNotification: false)
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        isUTIRotating = true

        cancelMorphAnimatorIfNeedded()

        let isKeyboardShowing = omniBar.isTextFieldEditing
        if isKeyboardShowing && !AppWidthObserver.shared.isPad {
            omniBar.barView.textField.suppressResignFirstResponder = true
        }

        let wasMinimalChrome = isInMinimalChromeLayout
        // Capture a snapshot of the toolbar before applyWidth hides it, so we can animate it out.
        // We can't keep toolbar.isHidden = false because the async showBars() call in applyWidth
        // would reset toolbarBottom.constant via updateToolbarConstant.
        let toolbarSnapshot: UIView? = {
            guard !wasMinimalChrome, isMinimalChromeMode(for: size) else { return nil }
            guard let snapshot = viewCoordinator.toolbar.snapshotView(afterScreenUpdates: false) else { return nil }
            snapshot.frame = viewCoordinator.toolbar.frame
            view.addSubview(snapshot)
            return snapshot
        }()

        let needsWidthUpdate = AppWidthObserver.shared.willResize(toWidth: size.width)
        if needsWidthUpdate {
            applyWidth(for: size)
        }

        let isShowingToolbar = wasMinimalChrome && !isInMinimalChromeLayout
        if isShowingToolbar {
            viewCoordinator.toolbar.alpha = 0
        }

        self.showMenuHighlighterIfNeeded()
        updateChromeForDuckPlayer()

        coordinator.animate { _ in
            toolbarSnapshot?.alpha = 0
            if isShowingToolbar {
                self.viewCoordinator.toolbar.alpha = 1
            }
            // Re-sync within the rotation animation (applyWidth above resets the anchor) so the
            // UTI rides the rotation to its keyboard position instead of snapping afterwards.
            if let utiCoordinator = self.unifiedToggleInputCoordinator {
                self.syncBottomOmnibarAnchorIfNeeded(for: utiCoordinator)
            }
            self.swipeTabsCoordinator?.invalidateLayout()
            self.deferredFireOrientationPixel()
        } completion: { [weak self] _ in
            guard let self else {
                assertionFailure()
                return
            }
            self.viewWillTransitionAnimationComplete(
                toolbarSnapshot: toolbarSnapshot,
                isKeyboardShowing: isKeyboardShowing,
                isShowingToolbar: isShowingToolbar)
        }

        hideNotificationBarIfBrokenSitePromptShown()
    }

    private func viewWillTransitionAnimationComplete(toolbarSnapshot: UIView?,
                                                     isKeyboardShowing: Bool,
                                                     isShowingToolbar: Bool) {
        toolbarSnapshot?.removeFromSuperview()

        resetBarsAfterTransitionAnimationIfNeeded(wasKeyboardShowing: isKeyboardShowing)

        omniBar.barView.textField.suppressResignFirstResponder = false
        if isKeyboardShowing {
            omniBar.beginEditing(animated: false)
        }

        if isInMinimalChromeLayout {
            viewCoordinator.constraints.toolbarBottom.constant = minimalChromeBottomHeight
            if viewCoordinator.addressBarPosition.isBottom {
                currentTab?.updateWebViewBottomAnchor(for: currentBarsVisibility)
            }
        }

        // Re-assert the bottom floating layout now rotation has settled (the mid-transition rebuild used stale geometry).
        if isShowingToolbar, isFloatingUIEnabled, viewCoordinator.addressBarPosition.isBottom {
            viewCoordinator.updateToolbarLayoutForAddressBarPosition(.bottom)
            currentTab?.updateWebViewBottomAnchor(for: currentBarsVisibility)
            view.layoutIfNeeded()
        }

        ViewHighlighter.updatePositions()
        // iOS reframes the keyboard post-rotation with no animation, so the UTI height can only
        // be corrected now; ease it so it settles into place instead of hard-snapping.
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.recomputeNavigationBarContainerHeightIfNeeded()
        } completion: { _ in
            self.isUTIRotating = false
        }
        updateFloatingReturnKeyVisibility()
    }

    private func resetBarsAfterTransitionAnimationIfNeeded(wasKeyboardShowing: Bool) {
        if shouldKeepChromeHiddenForFindInPage {
            setBarsHidden(true, animated: false, customAnimationDuration: nil)
            return
        }

        // Rotation changes the bar geometry, so the scroll-hide state can't carry across it.
        // Reset to revealed (editing and AI chrome manage their own layout).
        if !self.isCurrentTabUsingUnifiedInputAIChrome, !wasKeyboardShowing {
            self.resetBars(animated: false)
        }
    }

    private func deferredFireOrientationPixel() {
        orientationPixelWorker?.cancel()
        orientationPixelWorker = nil
        guard UIDevice.current.orientation.isLandscape else { return }

        let worker = DispatchWorkItem { [weak self] in
            Pixel.fire(pixel: .deviceOrientationLandscape)
            self?.productSurfaceTelemetry.landscapeModeUsed()
        }
        DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + 3, execute: worker)
        orientationPixelWorker = worker
    }

    private func isMinimalChromeMode(for size: CGSize? = nil) -> Bool {
        let size = size ?? view.bounds.size
        return MinimalChromeModeDecision.isActive(
            minimalChromeEnabled: minimalChromeSettings.shouldApplyMinimalChrome(isCurrentTabAITab: currentTab?.isAITab ?? false),
            isPad: AppWidthObserver.shared.isPad,
            isLandscape: size.width > size.height
        )
    }

    private var isApplyingWidth = false

    private func applyWidth(for size: CGSize? = nil) {
        // Re-entrancy guard: a refreshOmniBar side-effect calls applyWidth() with no size
        // mid-rotation, which reads stale view.bounds and re-applies the wrong chrome mode.
        guard !isApplyingWidth else { return }
        isApplyingWidth = true
        defer { isApplyingWidth = false }

        if AppWidthObserver.shared.isLargeWidth {
            applyLargeWidth()
        } else if isMinimalChromeMode(for: size) {
            applyMinimalChromeWidth()
        } else {
            applySmallWidth()
        }

        updateNewTabPageLayoutForCurrentChromeMode()

        DispatchQueue.main.async {
            // Do this async otherwise the toolbar buttons skew to the right
            if self.viewCoordinator.constraints.navigationBarContainerTop.constant >= 0,
               !self.isInMinimalChromeLayout,
               !self.isCurrentTabUsingUnifiedInputAIChrome,
               !self.shouldKeepChromeHiddenForFindInPage {
                self.showBars()
            }
            // If tabs have been udpated, do this async to make sure size calcs are current
            self.tabsBarController?.refresh(tabsModel: self.tabManager.currentTabsModel)
            // Keep the current tab in view after a resize/rotation reflows the strip.
            self.tabsBarController?.scrollCurrentTabIntoView()
            self.swipeTabsCoordinator?.refresh(tabsModel: self.tabManager.currentTabsModel)
            
            // Do this on the next UI thread pass so we definitely have the right width
            self.applyWidthToTrayController()
        }
    }

    func refreshMenuButtonState() {
        if newTabPageViewController != nil {
            viewCoordinator.omniBar.barView.menuButton.accessibilityLabel = UserText.bookmarksButtonHint
            viewCoordinator.updateToolbarWithState(.newTab)
        } else {
            viewCoordinator.omniBar.barView.menuButton.accessibilityLabel = UserText.menuButtonHint
            if let currentTab = currentTab {
                viewCoordinator.updateToolbarWithState(.pageLoaded(currentTab: currentTab))
            }
        }
    }

    private func applyWidthToTrayController() {
        if AppWidthObserver.shared.isLargeWidth {
            self.suggestionTrayController?.float(withWidth: self.viewCoordinator.omniBar.barView.searchContainerWidth)
        } else {
            self.suggestionTrayController?.coversFullScreen = isInMinimalChromeLayout
            let bottomOmniBarHeight = appSettings.currentAddressBarPosition.isBottom ? omniBar.barView.expectedHeight : 0
            self.suggestionTrayController?.fill(bottomOffset: bottomOmniBarHeight)
            // In floating top mode the tray container spans behind the glass omnibar; inset its top so
            // suggestions start below the bar instead of underneath it.
            let topOmniBarHeight = isFloatingTopContentBehindBar ? omniBar.barView.expectedHeight : 0
            self.suggestionTrayController?.additionalTopInset = topOmniBarHeight
        }
    }

    private func updateNewTabPageLayoutForCurrentChromeMode() {
        newTabPageViewController?.setChromeLayoutContext(isBorderSuppressed: isInMinimalChromeLayout)
        newTabPageViewController?.widthChanged()
    }
    
    /// Single source of truth lives on the coordinator; mutated via `setMinimalChromeMode(_:)`.
    var isInMinimalChromeLayout: Bool {
        viewCoordinator.isInMinimalChromeLayout
    }

    var isUsingSingleBar: Bool {
        AppWidthObserver.shared.isLargeWidth || isInMinimalChromeLayout
    }

    private func setMinimalChromeMode(_ enabled: Bool) {
        viewCoordinator.setMinimalChromeLayout(enabled)
        viewCoordinator.omniBar.isExpandedPhone = enabled
        // Minimal chrome hides the toolbar capsule, so the single bar renders its own glass.
        viewCoordinator.omniBar.barView.setFloatingMinimalChromeBar(enabled && isFloatingUIEnabled)
    }

    private func applyLargeWidth() {
        if isInMinimalChromeLayout { tearDownMinimalChrome() }
        viewCoordinator.tabBarContainer.isHidden = false
        reconcileToolbarVisibilityForCurrentTab()
        viewCoordinator.omniBar.enterPadState()

        swipeTabsCoordinator?.isEnabled = false
    }

    private func applySmallWidth() {
        if isInMinimalChromeLayout { tearDownMinimalChrome() }
        viewCoordinator.tabBarContainer.isHidden = true
        reconcileToolbarVisibilityForCurrentTab()
        viewCoordinator.constraints.toolbarBottom.constant = 0
        viewCoordinator.omniBar.enterPhoneState()

        swipeTabsCoordinator?.isEnabled = true
    }

    private func tearDownMinimalChrome() {
        setMinimalChromeMode(false)
        viewCoordinator.navigationBarContainer.transform = .identity
        viewCoordinator.omniBar.barView.setLayoutMode(.compact, animated: false)
        viewCoordinator.resetMinimalChromeLayout()
        // Minimal chrome detached the bottom omnibar from the toolbar; fully rebuild the bottom layout
        // so it returns to the toolbar capsule correctly hosted (top is never toolbar-hosted).
        if isFloatingUIEnabled, appSettings.currentAddressBarPosition.isBottom {
            viewCoordinator.updateToolbarLayoutForAddressBarPosition(.bottom)
        }
        currentTab?.borderView.isBottomVisible = true
    }

    private func applyMinimalChromeWidth() {
        viewCoordinator.tabBarContainer.isHidden = true
        viewCoordinator.toolbar.isHidden = true
        viewCoordinator.constraints.toolbarBottom.constant = minimalChromeBottomHeight
        setMinimalChromeMode(true)
        // The toolbar is now hidden, so move a toolbar-hosted bottom omnibar back to the nav container.
        let didDetachOmnibarFromToolbar = viewCoordinator.isOmnibarInToolbar
        viewCoordinator.returnOmnibarToNavigationContainerIfNeeded()
        viewCoordinator.omniBar.enterPhoneState()
        viewCoordinator.moveAddressBarToPosition(appSettings.currentAddressBarPosition)

        if appSettings.currentAddressBarPosition.isBottom {
            // Bar sits at bottom. Lift it only when omnibar has focus.
            viewCoordinator.applyMinimalChromeBottomLayout(pinnedToScreenBottom: !isKeyboardOwnedByOmnibar)
        } else {
            viewCoordinator.resetMinimalChromeLayout()
        }
        currentTab?.borderView.isBottomVisible = appSettings.currentAddressBarPosition.isBottom

        swipeTabsCoordinator?.isEnabled = true

        // Detaching the shared bar view from the toolbar leaves it orphaned; the navigation `OmniBarCell`
        // only re-adds it via its `omniBar` didSet, so reload the swipe tabs now to re-host it rather
        // than relying on the deferred refresh (which can leave the address bar missing after rotation).
        if didDetachOmnibarFromToolbar {
            swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel)
        }

        // Refresh the obscured inset so moving the bar top/bottom in landscape updates it immediately.
        currentTab?.updateWebViewBottomAnchor(for: currentBarsVisibility)
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
        if !isUsingSingleBar {
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
        suggestionTrayController?.didHide(animated: false)
    }
    
    func launchAutofillLogins(with currentTabUrl: URL? = nil, currentTabUid: String? = nil, openSearch: Bool = false, source: AutofillSettingsSource, selectedAccount: SecureVaultModels.WebsiteAccount? = nil, extensionPromotionManager: AutofillExtensionPromotionManaging? = nil) {
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
            keyValueStore: self.keyValueStore,
            extensionPromotionManager: extensionPromotionManager,
            productSurfaceTelemetry: productSurfaceTelemetry
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

    private func makeDataImportViewController(
          source: DataImportViewModel.ImportScreen,
          onFinished: (() -> Void)? = nil,
          onCancelled: (() -> Void)? = nil
      ) -> DataImportViewController {
          let dataImportManager = DataImportManager(
            reporter: SecureVaultReporter(),
            bookmarksDatabase: self.bookmarksDatabase,
            favoritesDisplayMode: self.appSettings.favoritesDisplayMode,
            tld: AppDependencyProvider.shared.storageCache.tld
          )

          return DataImportViewController(
            importManager: dataImportManager,
            importScreen: source,
            syncService: syncService,
            keyValueStore: keyValueStore,
            onFinished: onFinished,
            onCancelled: onCancelled
          )
      }

    func launchDataImport(source: DataImportViewModel.ImportScreen, onFinished: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        let rootViewController: UIViewController
        switch DataImportEntryPointHandler().destination(for: source) {
        case .legacy(let importScreen):
            rootViewController = makeDataImportViewController(source: importScreen, onFinished: onFinished, onCancelled: onCancelled)
        case .hub:
            rootViewController = DataImportHubViewController(syncService: syncService,
                                                             keyValueStore: keyValueStore,
                                                             bookmarksDatabase: bookmarksDatabase,
                                                             favoritesDisplayMode: appSettings.favoritesDisplayMode,
                                                             entryPoint: source,
                                                             onFinished: onFinished,
                                                             onCancelled: onCancelled)
            Pixel.fire(pixel: .importHubEntryTapped, withAdditionalParameters: source.importHubEntryPointParameters)
        }

        let navigationController = UINavigationController(rootViewController: rootViewController)
        rootViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: UserText.autofillNavigationButtonItemTitleClose,
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
        omniBar.refreshCustomizableButton()
        reanchorAITabCollapsedFooterIfNeeded()
    }

    /// The AI-tab collapsed footer is a bottom chat input that must sit above the keyboard/home
    /// indicator. `showUnifiedToggleInput()` defaults the nav-bar bottom to the toolbar, and the
    /// show/hide churn around opening Duck.ai (some of it outside intent handling) can leave it
    /// toolbar-anchored; in landscape the bottom toolbar is off-screen, dragging the footer off the
    /// bottom edge. Re-assert the keyboard anchor (floored at the safe area). Guarded so it's a
    /// no-op once correct — no loop, no per-frame work beyond the bool check.
    private func reanchorAITabCollapsedFooterIfNeeded() {
        guard let coordinator = unifiedToggleInputCoordinator,
              coordinator.displayState == .aiTab(.collapsed),
              coordinator.cardPosition == .bottom,
              !viewCoordinator.isNavigationBarContainerBottomKeyboardBased else { return }
        viewCoordinator.setNavBarContainerBottomToKeyboard()
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
        guard !onboardingManager.userHasSeenAddToDockPromoDuringOnboarding else { return }
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
    lazy private var brokenSitePromptLimiter = BrokenSitePromptLimiter(privacyConfigManager: privacyConfigurationManager,
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

    func newTab(reuseExisting: Bool = false, allowingKeyboard: Bool = true, openedAfterIdle: Bool = false) {
        if daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        daxDialogsManager.fireButtonPulseCancelled()
        // Tear down active editing before building the new tab; non-animated so its collapse doesn't race the new tab's focus animation.
        dismissOmniBar(animated: false)
        hideNotificationBarIfBrokenSitePromptShown()
        currentTab?.aiChatContextualSheetCoordinator.dismissSheet()

        let previousTab = tabManager.current()
        dismissSystemFindNavigator(for: previousTab)
        currentTab?.dismiss()

        if reuseExisting, let existing = tabManager.firstHomeTab() {
            tabManager.select(existing, dismissCurrent: false)
        } else {
            tabManager.addHomeTab()
        }
        attachHomeScreen(isNewTab: true, allowingKeyboard: allowingKeyboard, previousTab: previousTab, openedAfterIdle: openedAfterIdle)
        tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        bindAIChatChromeChipToCurrentTab()
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        themeColorManager.updateThemeColor()
        showBars() // In case the browser chrome bars are hidden when calling this method
    }

    // MARK: - Idle return NTP (dismiss overlays so NTP is visible)
    /// Dismisses tab switcher and any presented view controller (e.g. Settings) so the caller can then show the NTP.
    func prepareForIdleReturnNTP(completion: @escaping () -> Void) {
        guard let presented = presentedViewController, !presented.isBeingDismissed else {
            completion()
            return
        }
        // Don't dismiss the omni bar's editing state (keyboard/switch), we're reusing NTP and want to preserve focus
        if presented is OmniBarEditingStateViewController {
            completion()
            return
        }
        presented.dismiss(animated: true, completion: completion)
    }
    
    func updateFindInPage() {
        currentTab?.findInPage?.delegate = self
        findInPageView?.update(with: currentTab?.findInPage, updateTextField: true)
        findInPageView?.updateConstraints()
    }

    func dismissSystemFindNavigator(for tab: TabViewController?) {
        guard #available(iOS 16.0, *), featureFlagger.isFeatureOn(.systemFindInPage) else { return }
        rememberFindInPageQuery(for: tab)
        tab?.webView.findInteraction?.dismissFindNavigator()
        restoreChromeIfHiddenByFindInPage()
    }

    @available(iOS 16.0, *)
    private func hideChromeForConfirmedFindInPage() {
        guard featureFlagger.isFeatureOn(.systemFindInPage),
              currentTab?.webView.findInteraction?.isFindNavigatorVisible == true,
              !AppWidthObserver.shared.isPad || !AppWidthObserver.shared.isLargeWidth,
              !isFindInPageChromeLockActive else { return }

        isFindInPageChromeLockActive = true
        didFindInPageHideChrome = lastChromeVisibilityPercent > 0
        if didFindInPageHideChrome {
            setBarsHidden(true, animated: true, customAnimationDuration: nil)
        }

        findInPageDismissalTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard self.currentTab?.webView.findInteraction?.isFindNavigatorVisible != true else { return }
            self.restoreChromeIfHiddenByFindInPage()
        }
    }

    private func restoreChromeIfHiddenByFindInPage() {
        findInPageDismissalTimer?.invalidate()
        findInPageDismissalTimer = nil

        isFindInPageChromeLockActive = false
        let shouldRestoreChrome = didFindInPageHideChrome
        didFindInPageHideChrome = false
        guard shouldRestoreChrome else { return }
        setBarsHidden(false, animated: true, customAnimationDuration: nil)
    }

    private var shouldKeepChromeHiddenForFindInPage: Bool {
        guard isFindInPageChromeLockActive,
              !AppWidthObserver.shared.isPad || !AppWidthObserver.shared.isLargeWidth else { return false }
        if #available(iOS 16.0, *) {
            return currentTab?.webView.findInteraction?.isFindNavigatorVisible == true
        }
        return false
    }

    // Persist the current query so the find navigator can be prepopulated when reopened on this tab.
    @available(iOS 16.0, *)
    private func rememberFindInPageQuery(for tab: TabViewController?) {
        // Store the current query as-is (including when cleared) so a deliberate clear isn't overwritten by a stale term.
        (tab?.webView as? WebView)?.lastFindInPageQuery = tab?.webView.findInteraction?.searchText
    }

    func handleVoiceSearchOpenRequest(preferredTarget: VoiceSearchTarget? = nil) {
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
        dismissOmniBar()
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
        NotificationCenter.default.publisher(for: .urlInterceptSubscription)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection
                if let redirectURLComponents = notification.userInfo?[TabURLInterceptorParameter.interceptedURLComponents] as? URLComponents {
                    if SubscriptionPurchaseFlowPath.isPlansPath(redirectURLComponents.path) {
                        deepLinkTarget = .subscriptionPlanChangeFlow(redirectURLComponents: redirectURLComponents)
                    } else {
                        deepLinkTarget = .subscriptionFlow(redirectURLComponents: redirectURLComponents)
                    }
                } else {
                    deepLinkTarget = .subscriptionFlow()
                }
                self?.launchSettingsForSubscriptionInterception(deepLinkTarget)

            }
            .store(in: &urlInterceptorCancellables)

        NotificationCenter.default.publisher(for: .dataBrokerProtectionOpenSubscriptionFlow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let redirectURLComponents = notification.userInfo?[
                    DataBrokerProtectionSubscriptionFlowParameter.redirectURLComponents
                ] as? URLComponents
                self?.presentDataBrokerProtectionSubscriptionFlow(redirectURLComponents: redirectURLComponents)
            }
            .store(in: &urlInterceptorCancellables)

        NotificationCenter.default.publisher(for: .urlInterceptAIChat)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let interceptedURL = notification.userInfo?[TabURLInterceptorParameter.interceptedURL] as? URL
                let payload = notification.object as? AIChatPayload
                var query: String?
                var shouldAutoSend = false
                if let url = interceptedURL,
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems {
                    query = queryItems.first(where: { $0.name == AIChatURLParameters.promptQueryName })?.value
                    shouldAutoSend = queryItems.first(where: { $0.name == AIChatURLParameters.autoSubmitPromptQueryName })?.value == AIChatURLParameters.autoSubmitPromptQueryValue
                }
                
                if let query = query {
                    self?.openAIChat(query, autoSend: shouldAutoSend, payload: payload)
                } else {
                    self?.openAIChat(payload: payload)
                }
            }
            .store(in: &urlInterceptorCancellables)
    }

    private func launchSettingsForSubscriptionInterception(_ deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection) {
        // If Settings is already presented, launchSettings reuses its view model; trigger the deep link explicitly.
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: deepLinkTarget)
        }, deepLinkTarget: deepLinkTarget)
    }

    private func presentDataBrokerProtectionSubscriptionFlow(redirectURLComponents: URLComponents?) {
        let subscriptionFlowViewController = makeDataBrokerProtectionSubscriptionFlowViewController(
            redirectURLComponents: redirectURLComponents
        )

        if let settingsNavigationController = presentedViewController as? SettingsUINavigationController {
            settingsNavigationController.pushViewController(subscriptionFlowViewController, animated: true)
            return
        }

        let navigationController = DataBrokerProtectionSubscriptionFlowNavigationController(
            rootViewController: subscriptionFlowViewController
        )
        var presenter: UIViewController = self
        while let presentedViewController = presenter.presentedViewController {
            presenter = presentedViewController
        }
        presenter.present(navigationController, animated: true)
    }

    private func makeDataBrokerProtectionSubscriptionFlowViewController(redirectURLComponents: URLComponents?) -> UIViewController {
        let subscriptionNavigationCoordinator = SubscriptionNavigationCoordinator()
        let viewController = UIHostingController(rootView: SubscriptionContainerViewFactory.makePurchaseFlowV2(
            redirectURLComponents: redirectURLComponents,
            navigationCoordinator: subscriptionNavigationCoordinator,
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
            subscriptionFeatureAvailability: subscriptionFeatureAvailability,
            subscriptionDataReporter: subscriptionDataReporter,
            userScriptsDependencies: userScriptsDependencies,
            tld: AppDependencyProvider.shared.storageCache.tld,
            internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
            dataBrokerProtectionViewControllerProvider: dbpIOSPublicInterface,
            wideEvent: AppDependencyProvider.shared.wideEvent,
            featureFlagger: featureFlagger
        ))
        viewController.view.backgroundColor = UIColor(designSystemColor: .surface)
        return viewController
    }

    private func subscribeToSettingsDeeplinkNotifications() {
        NotificationCenter.default.publisher(for: .settingsDeepLinkNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let rawCallback = notification.userInfo?[SettingsDeepLinkUserInfoKey.onPresented]
                assert(rawCallback == nil || rawCallback is SettingsDeepLinkCallback, "onPresented must be a SettingsDeepLinkCallback")
                let onPresented = (rawCallback as? SettingsDeepLinkCallback)?.onPresented
                let handleSettingsDeepLink = {
                    self.handleSettingsDeepLink(notification, onPresented: onPresented)
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
    
    private func handleSettingsDeepLink(_ notification: Notification, onPresented: (() -> Void)? = nil) {
        switch notification.object as? SettingsViewModel.SettingsDeepLinkSection {
        
        case .duckPlayer:
            let deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection
                deepLinkTarget = .duckPlayer
            launchSettings(deepLinkTarget: deepLinkTarget)
        case .subscriptionFlow(let components):
            launchSettings(completion: { _ in onPresented?() },
                           deepLinkTarget: .subscriptionFlow(redirectURLComponents: components))
        case .subscriptionPlanChangeFlow(let components):
            launchSettings(deepLinkTarget: .subscriptionPlanChangeFlow(redirectURLComponents: components))
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

    private func subscribeToAIChatResponseEvents() {
        NotificationCenter.default.publisher(for: .aiChatResponseReceived)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showFireDialogAfterAIChatResponseIfReady()
            }
            .store(in: &aiChatCancellables)
    }

    private func subscribeToRefreshButtonSettingsEvents() {
        NotificationCenter.default.publisher(for: AppUserDefaults.Notifications.refreshButtonSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOmniBar()
            }
            .store(in: &settingsCancellables)
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
            Pixel.fire(pixel: .vpnAccessRevokedAlertSubscribeButtonClicked)
            self?.segueToDuckDuckGoSubscription(origin: SubscriptionFunnelOrigin.vpnAccessRevokedAlert.rawValue)
        }
        dismiss(animated: true) {
            Pixel.fire(pixel: .vpnAccessRevokedAlertShown)
            self.present(alertController, animated: true) {
                self.tunnelDefaults.showEntitlementAlert = false
            }
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
            let subscriptionManager = AppDependencyProvider.shared.subscriptionManager
            let isSubscriptionActive = (try? await subscriptionManager.getSubscription())?.isActive

            PixelKit.fire(
                VPNSubscriptionStatusPixel.signedIn(
                    isSubscriptionActive: isSubscriptionActive,
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
                let isSubscriptionActive = (try? await subscriptionManager.getSubscription())?.isActive
                let hasEntitlement = try await subscriptionManager.isFeatureEnabled(.networkProtection)

                if !hadVPNEntitlements && hasEntitlement {
                    PixelKit.fire(
                        VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
                            isSubscriptionActive: isSubscriptionActive,
                            trigger: trigger),
                        frequency: .dailyAndCount)
                    
                    hadVPNEntitlements = hasEntitlement
                } else if hadVPNEntitlements && !hasEntitlement {
                    PixelKit.fire(
                        VPNSubscriptionClientCheckPixel.vpnFeatureDisabled(
                            isSubscriptionActive: isSubscriptionActive,
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
        let isSubscriptionActive = (try? await subscriptionManager.getSubscription())?.isActive
        
        PixelKit.fire(
            VPNSubscriptionClientCheckPixel.failed(
                isSubscriptionActive: isSubscriptionActive,
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
            let isSubscriptionActive = (try? await subscriptionManager.getSubscription())?.isActive

            if hasVPNEntitlements {
                PixelKit.fire(
                    VPNSubscriptionStatusPixel.vpnFeatureEnabled(
                        isSubscriptionActive: isSubscriptionActive,
                        sourceObject: notification.object),
                    frequency: .dailyAndCount)
            } else {
                PixelKit.fire(
                    VPNSubscriptionStatusPixel.vpnFeatureDisabled(
                        isSubscriptionActive: isSubscriptionActive,
                        sourceObject: notification.object),
                    frequency: .dailyAndCount)

                // Suppress entitlement messaging before stopping the VPN during user-initiated sign-out.
                // This prevents the extension from showing the "subscription expired" alert when it
                // detects the missing token. The suppress flag is checked in enableEntitlementMessaging().
                if userInitiatedSignOut {
                    tunnelDefaults.suppressEntitlementMessaging = true
                } else if await networkProtectionTunnelController.isInstalled {
                    tunnelDefaults.enableEntitlementMessaging()
                }

                await networkProtectionTunnelController.stop()

                if userInitiatedSignOut {
                    await networkProtectionTunnelController.removeVPN(reason: .signedOut)
                    tunnelDefaults.suppressEntitlementMessaging = false
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
            let subscriptionManager = AppDependencyProvider.shared.subscriptionManager
            let isSubscriptionActive = (try? await subscriptionManager.getSubscription())?.isActive

            PixelKit.fire(
                VPNSubscriptionStatusPixel.signedOut(
                    isSubscriptionActive: isSubscriptionActive,
                    sourceObject: notification.object),
                frequency: .dailyAndCount)

            // Suppress entitlement messaging to prevent the "subscription expired" alert
            // from appearing during user-initiated sign-out.
            tunnelDefaults.suppressEntitlementMessaging = true

            await networkProtectionTunnelController.stop()
            await networkProtectionTunnelController.removeVPN(reason: .signedOut)

            tunnelDefaults.suppressEntitlementMessaging = false
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
        
        Pixel.fire(pixel: pixel, withAdditionalParameters: pixelParameters)
    }

    func openAIChat(_ query: String? = nil,
                    autoSend: Bool = false,
                    payload: Any? = nil,
                    flowType: AIChatOnboardingFlowType = .default,
                    tools: [AIChatRAGTool]? = nil,
                    modelId: String? = nil,
                    reasoningEffort: AIChatReasoningEffort? = nil,
                    images: [AIChatNativePrompt.NativePromptImage]? = nil,
                    files: [AIChatNativePrompt.NativePromptFile]? = nil,
                    fromDeepLink: Bool = false) {

        if aichatFullModeFeature.isAvailable || DevicePlatform.isIpad {
            openAIChatInTab(
                query,
                autoSend: autoSend,
                payload: payload,
                flowType: flowType,
                tools: tools,
                modelId: modelId,
                reasoningEffort: reasoningEffort,
                images: images,
                files: files,
                fromDeepLink: fromDeepLink
            )
        } else {
            aiChatViewControllerManager.openAIChat(
                query,
                payload: payload,
                autoSend: autoSend,
                flowType: flowType,
                tools: tools,
                modelId: modelId,
                reasoningEffort: reasoningEffort,
                images: images,
                files: files,
                on: self
            )
        }
    }

    func onDuckAIVoiceModeRequested() {
        Pixel.fire(pixel: .voiceEntryPointTapped, withAdditionalParameters: [PixelParameters.source: VoiceEntryPointSource.ntp.rawValue])
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.barUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
        openAIChatInVoiceMode()
    }

    func openAIVoiceChatFromDeepLink() {
        openAIChatInVoiceMode(fromDeepLink: true)
    }

    private func openAIChatInVoiceMode(fromDeepLink: Bool = false) {
        if aichatFullModeFeature.isAvailable || DevicePlatform.isIpad {
            openAIChatVoiceModeInTab(fromDeepLink: fromDeepLink)
        } else {
            aiChatViewControllerManager.openAIChatVoiceMode(on: self)
        }
    }

    private func openAIChatVoiceModeInTab(fromDeepLink: Bool = false) {
        guard tabManager.current(createIfNeeded: true) != nil else {
            assertionFailure("openAIChatVoiceModeInTab: no current tab available")
            return
        }

        guard let currentTab else { return }

        // Voice mode has no on-screen input; dismiss the keyboard before either branch loads.
        unifiedToggleInputCoordinator?.dismissOmnibarKeyboard()

        // Voice always opens a new tab over existing content (chat included) — voice over a chat would replace the prior conversation. NTP stays in-place via `link != nil`.
        let hasContent = currentTab.tabModel.link != nil
        let openInNewTab = hasContent && (unifiedToggleInputFeature.isAvailable || fromDeepLink)

        if openInNewTab {
            let voiceURL = currentTab.aiChatContentHandler.buildVoiceModeURL()
            loadUrlInNewTab(voiceURL, inheritedAttribution: nil, voiceMode: true)
            if fromDeepLink {
                // Collapse the input that was auto-expanded for the restored tab.
                // This cancels any pending async activateInput because showCollapsed
                // sets displayState to .collapsed, failing the guard in showExpanded's
                // async block.
                unifiedToggleInputCoordinator?.showCollapsed()
            }
            return
        }

        prepareTabForRequest {
            currentTab.loadVoiceMode()
        }
    }
    
    /// Loads AI Chat into the current tab, creating one if needed. Selects the tab when done.
    ///
    /// - Parameters:
    ///   - query: Optional initial query to send to AI Chat
    ///   - autoSend: Whether to automatically send the query
    ///   - payload: Optional payload data for AI Chat
    ///   - flowType: Optional onboarding flow type to hand off to Duck.ai.
    ///   - tools: Optional RAG tools available in AI Chat
    ///   - modelId: Optional model ID to use for AI Chat
    ///   - images: Optional images to send to AI Chat
    private func openAIChatInTab(_ query: String? = nil,
                                 autoSend: Bool = false,
                                 payload: Any? = nil,
                                 flowType: AIChatOnboardingFlowType = .default,
                                 tools: [AIChatRAGTool]? = nil,
                                 modelId: String? = nil,
                                 reasoningEffort: AIChatReasoningEffort? = nil,
                                 images: [AIChatNativePrompt.NativePromptImage]? = nil,
                                 files: [AIChatNativePrompt.NativePromptFile]? = nil,
                                 fromDeepLink: Bool = false) {
        guard tabManager.current(createIfNeeded: true) != nil else {
            assertionFailure("openAIChatInTab: no current tab available")
            return
        }

        // Deep links cross unconditionally; everything else defers to `AIBoundaryNavigationDecision` so the chat→chat-stays-in-place matrix lives in one place. NTP/empty stays in-place via `link != nil`.
        let shouldOpenInNewTab: Bool = {
            guard let currentTab, currentTab.tabModel.link != nil else { return false }
            if fromDeepLink { return true }
            return AIBoundaryNavigationDecision.forProgrammaticNavigation(
                currentIsAI: currentTab.isAITab,
                currentHasContent: true,
                targetIsAI: true,
                unifiedToggleInputAvailable: unifiedToggleInputFeature.isAvailable
            ) == .openInNewTab
        }()
        if shouldOpenInNewTab, let currentTab {
            // Dismiss contextual onboarding before opening duck.ai via UTI.
            currentTab.contextualOnboardingPresenter.dismissContextualOnboardingIfNeeded(from: currentTab)
            let chatURL = currentTab.aiChatContentHandler.buildQueryURL(query: query, autoSend: autoSend, flowType: flowType, tools: tools)
            // Mirror the in-place `.barUsed` so the new-tab branch keeps idle-session parity.
            // Gated on `!fromDeepLink` so external entries aren't reclassified as address-bar submissions.
            if !fromDeepLink {
                postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
            }
            // Stage prompt singleton before `loadUrlInNewTab` — matches legacy `setData → load` order.
            // Per-tab payload runs in completion since it targets the newly-selected chat tab.
            if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let prompt = AIChatNativePrompt.queryPrompt(
                    query,
                    autoSubmit: autoSend,
                    toolChoice: tools?.map(\.rawValue),
                    images: images,
                    files: files,
                    modelId: modelId,
                    reasoningEffort: reasoningEffort
                )
                AIChatPromptHandler.shared.setData(prompt)
            }
            loadUrlInNewTab(chatURL, inheritedAttribution: nil) { [weak self] in
                if let payload {
                    self?.currentTab?.aiChatContentHandler.setPayload(payload: payload)
                }
            }
            return
        }

        load(query, autoSend: autoSend, payload: payload, flowType: flowType, tools: tools, modelId: modelId, reasoningEffort: reasoningEffort, images: images, files: files)
    }

    /// Executes the closure if the current tab is an AI tab
    private func performActionIfAITab(_ action: () -> Void) {
        guard currentTab?.isAITab == true else { return }
        action()
    }
    
}

extension MainViewController: FindInPageDelegate {
    
    func updated(findInPage: FindInPage) {
        findInPageView?.update(with: findInPage, updateTextField: false)
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
        /// Longer than `duration` so the floating capsule morph is legible; the pill grows/moves into
        /// the bars (and back) rather than snapping across the short legacy cross-fade.
        static let morphDuration = 0.33
    }

    var tabBarContainer: UIView {
        viewCoordinator.tabBarContainer
    }

    var omniBar: any OmniBar {
        viewCoordinator.omniBar
    }

    func setUnifiedInputContentOverlaySuppressed(_ suppressed: Bool) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        coordinator.setContentOverlaySuppressed(suppressed)
        updateUnifiedInputContentVisibility(for: coordinator)
    }

    private func hideKeyboard() {
        dismissOmniBar()
        _ = findInPageView?.resignFirstResponder()
    }

    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?) {
        if hidden { hideKeyboard() }

        setBarsVisibility(hidden ? 0 : 1.0, animated: animated, animationDuration: customAnimationDuration)
    }

    func resetBars(animated: Bool) {
        chromeManager.reset(animated: animated)
    }
    
    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?) {
        // Start any morph scrub from where the chrome visually is (a scrub already in flight, or the
        // last committed fraction) so an interruption resumes smoothly rather than snapping.
        let fromPercent = chromeMorphAnimator.isAnimating ? chromeMorphAnimator.currentValue : lastChromeVisibilityPercent
        lastChromeVisibilityPercent = percent
        // Any prior scrub is superseded by this command; the new state is applied below.
        chromeMorphAnimator.cancel()

        if percent < 1 {
            if omniBar.isTextFieldEditing || unifiedToggleInputCoordinator?.isOmnibarSession == true {
                dismissOmniBar()
            }
            _ = findInPageView?.resignFirstResponder()
            hideMenuHighlighter()
        } else {
            showMenuHighlighterIfNeeded()
        }

        let postNotification = percent == 0 || percent == 1

        // The floating capsule morph geometry and its chrome-alpha handoff are non-linear in
        // `percent`, so a single `UIView.animate` (which only interpolates the endpoints) skips the
        // morph and the bars pop/slide in. Replay the exact per-frame state the scroll path applies
        // by scrubbing `percent` with a display link instead.
        let useMorphScrub = animated
            && isFloatingCapsuleActive
            && !UIAccessibility.isReduceMotionEnabled
            && abs(fromPercent - percent) > 0.001

        if useMorphScrub {
            chromeMorphAnimator.animate(
                from: fromPercent,
                to: percent,
                duration: animationDuration ?? ChromeAnimationConstants.morphDuration,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    self.applyBarsVisibilityState(progress, postChromeVisibilityNotification: false)
                    self.view.layoutIfNeeded()
                },
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.applyBarsVisibilityState(percent, postChromeVisibilityNotification: postNotification)
                    self.view.layoutIfNeeded()
                })
        } else if animated {
            self.view.layoutIfNeeded()
            UIView.animate(withDuration: animationDuration ?? ChromeAnimationConstants.duration) {
                self.applyBarsVisibilityState(percent, postChromeVisibilityNotification: postNotification)
                self.view.layoutIfNeeded()
            }
        } else {
            applyBarsVisibilityState(percent, postChromeVisibilityNotification: postNotification)

            // Calling this here is important as it causes the layout to run immediately inside current run loop,
            // instead of deferring it until next update block.
            // Late layout after change here could potentially cause a scroll offset update right before the next one,
            // which may cause an infitie loop layout loop in certain scenarios.
            // See https://app.asana.com/1/137249556945/project/414709148257752/task/1208671955053442 for details.
            self.view.layoutIfNeeded()
        }
    }

    /// Applies the chrome layout/alpha/capsule state for a given visibility `percent`. Extracted so
    /// it can be applied as a single step (legacy `UIView.animate` / non-animated) or per frame by
    /// the floating capsule morph scrub. `.browserChromeVisibilityChanged` is posted only when
    /// requested (the settled 0/1 endpoints), so intermediate scrub frames don't emit it.
    private func applyBarsVisibilityState(_ percent: CGFloat, postChromeVisibilityNotification: Bool) {
        if isFloatingUIEnabled {
            viewCoordinator.ensureBottomOmnibarAttachedToToolbarIfNeeded()
        }
        updateToolbarConstant(percent)
        updateNavBarConstant(percent)
        currentTab?.updateWebViewBottomAnchor(for: percent)
        updateFloatingTopNewTabPageInset(for: percent)

        let chromeAlpha = chromeAlpha(for: percent)
        viewCoordinator.navigationBarContainer.alpha = chromeAlpha
        viewCoordinator.tabBarContainer.alpha = chromeAlpha
        viewCoordinator.toolbar.alpha = chromeAlpha
        updateFloatingDomainCapsuleVisibility(for: percent)

        if postChromeVisibilityNotification {
            NotificationCenter.default.post(
                name: .browserChromeVisibilityChanged,
                object: nil,
                userInfo: ["isHidden": percent == 0]
            )
        }
    }

    func setNavigationBarHidden(_ hidden: Bool) {
        lastChromeVisibilityPercent = hidden ? 0 : 1
        chromeMorphAnimator.cancel()
        if hidden { hideKeyboard() }
        if isFloatingUIEnabled {
            viewCoordinator.ensureBottomOmnibarAttachedToToolbarIfNeeded()
        }

        if viewCoordinator.addressBarPosition.isBottom {
            if hidden {
                viewCoordinator.hideNavigationBarWithBottomPosition()
            } else {
                viewCoordinator.showNavigationBarWithBottomPosition()
            }
        }

        updateNavBarConstant(hidden ? 0 : 1.0)
        // When the omnibar is locked (e.g. dimmed to 0.5 alpha during Duck.ai fire onboarding),
        // skip the chrome-hide alpha reset so we don't overwrite the dim.
        let isOmniBarLocked = !viewCoordinator.omniBar.barView.isUserInteractionEnabled
        let isBottomOmnibarHostedInToolbar = isFloatingUIEnabled && viewCoordinator.addressBarPosition.isBottom && viewCoordinator.isOmnibarInToolbar
        if !isOmniBarLocked && !isBottomOmnibarHostedInToolbar {
            viewCoordinator.omniBar.barView.alpha = hidden ? 0 : 1
        } else if isBottomOmnibarHostedInToolbar {
            // In bottom mode the omnibar is physically hosted inside the toolbar; keep it visible and
            // let toolbar offset/alpha animations own chrome visibility to avoid blank "missing" bars.
            viewCoordinator.omniBar.barView.alpha = 1
        }
        viewCoordinator.tabBarContainer.alpha = hidden ? 0 : 1
        viewCoordinator.statusBackground.alpha = hidden ? 0 : 1
        updateFloatingDomainCapsuleVisibility(for: hidden ? 0 : 1)
    }

    func setRefreshControlEnabled(_ isEnabled: Bool) {
        currentTab?.setRefreshControlEnabled(isEnabled)
    }

    var canHideBars: Bool {
        if currentTab?.isLoading == true { return false }
        // Keep bars shown on the error page: the webView is hidden, so scroll can't self-heal a stuck-hidden bar.
        if currentTab?.isError == true { return false }
        return !shouldPinChrome && !daxDialogsManager.shouldShowFireButtonPulse
    }

    /// No hide/show bars on scroll. On when bar hides behind web keyboard (else page jerks), and while the system
    /// find-in-page navigator is visible so swipes can't reveal the chrome — the user must dismiss find first.
    var isChromeScrollInteractionDisabled: Bool {
        if isBottomAddressBarHiddenForWebKeyboard { return true }
        if #available(iOS 16.0, *), featureFlagger.isFeatureOn(.systemFindInPage),
           currentTab?.webView.findInteraction?.isFindNavigatorVisible == true {
            return true
        }
        return false
    }

    /// When `true`, the omni bar and toolbar are never hidden on scroll.
    /// iPad-only (the setting is hidden on iPhone); applies in all widths, including narrow Split View / Slide Over.
    private var shouldPinChrome: Bool {
        isPad && appSettings.keepAddressBarVisibleOnIPad
    }

    /// Reveals the chrome immediately if it should now be pinned but is currently hidden.
    private func revealChromeIfPinned() {
        guard shouldPinChrome else { return }
        chromeManager?.reset(animated: true)
    }

    var isToolbarHidden: Bool {
        if isInMinimalChromeLayout {
            return viewCoordinator.navigationBarContainer.alpha < 1
        }
        return viewCoordinator.toolbar.isHidden || viewCoordinator.toolbar.alpha < 1
    }

    var toolbarHeight: CGFloat {
        viewCoordinator.constraints.toolbarHeight.constant
    }
    
    var barsMaxHeight: CGFloat {
        let height = max(toolbarHeight, viewCoordinator.omniBar.barView.expectedHeight)
        if isInMinimalChromeLayout && viewCoordinator.addressBarPosition.isBottom {
            return height + view.safeAreaInsets.bottom
        }
        return height
    }

    /// Full toolbar slot height at the bottom, measured from the screen bottom: the toolbar height (its
    /// bottom is pinned to the safe area) plus the safe area itself. In floating bottom-address-bar mode
    /// the omnibar is hosted inside the toolbar (so `toolbarHeight` already includes it) and the nav bar
    /// container is hidden, so it must not be added here. A footer resized against this lands exactly on
    /// the toolbar's top edge.
    private var floatingToolbarSlotHeight: CGFloat {
        toolbarHeight + view.safeAreaInsets.bottom
    }

    /// Height obscured by the resting floating domain capsule, measured from the screen bottom, with a
    /// little extra clearance so a page-fixed footer doesn't sit flush against the pill. The capsule
    /// only rests at the bottom in bottom-address-bar mode, and only when it is eligible to show for a
    /// non-empty domain; otherwise a hidden footer should pin straight to the safe area.
    private var floatingBottomCapsuleObscuredHeight: CGFloat {
        guard appSettings.currentAddressBarPosition.isBottom,
              isFloatingCapsuleActive,
              let domain = currentFloatingDomainText(),
              !domain.isEmpty else {
            return 0
        }
        return view.safeAreaInsets.bottom
            + floatingDomainCapsuleController.restObscuredHeightAboveSafeArea
            + FloatingDomainCapsuleController.fixedElementClearance
    }

    func floatingWebViewBottomObscuredHeight(for barsVisibilityPercent: CGFloat) -> CGFloat {
        // Minimal chrome hides the toolbar: reserve the single bar's height only for a bottom address
        // bar (reclaimed as it scrolls away); a top address bar leaves just the safe area.
        if isInMinimalChromeLayout {
            guard viewCoordinator.addressBarPosition.isBottom else {
                return view.safeAreaInsets.bottom
            }
            let clampedPercent = max(0, min(1, barsVisibilityPercent))
            return max(barsMaxHeight * clampedPercent, view.safeAreaInsets.bottom)
        }
        return FloatingUILayoutPolicy.webViewBottomObscuredHeight(
            barsVisibilityPercent: barsVisibilityPercent,
            toolbarSlotHeight: floatingToolbarSlotHeight,
            bottomCapsuleObscuredHeight: floatingBottomCapsuleObscuredHeight,
            safeAreaBottom: view.safeAreaInsets.bottom
        )
    }

    func floatingWebViewObscuredInsets(for barsVisibilityPercent: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(top: floatingWebViewTopObscuredHeight(for: barsVisibilityPercent),
                     left: 0,
                     bottom: floatingWebViewBottomObscuredHeight(for: barsVisibilityPercent),
                     right: 0)
    }

    /// Top region obscured by chrome: safe area, plus the omnibar for a top address bar. In minimal
    /// chrome the top bar scrolls off, so its portion is reclaimed as it hides.
    private func floatingWebViewTopObscuredHeight(for barsVisibilityPercent: CGFloat) -> CGFloat {
        let safeAreaTop = view.safeAreaInsets.top
        guard appSettings.currentAddressBarPosition == .top else { return safeAreaTop }
        if isInMinimalChromeLayout {
            let clampedPercent = max(0, min(1, barsVisibilityPercent))
            return safeAreaTop + omniBar.barView.expectedHeight * clampedPercent
        }
        return safeAreaTop + omniBar.barView.expectedHeight
    }

    var minimalChromeBottomHeight: CGFloat {
        toolbarHeight + view.safeAreaInsets.bottom
    }

    /// Current visibility fraction of the chrome bars (1.0 = fully visible, 0.0 = hidden).
    /// We track the driven fraction directly rather than reading a container's alpha: with the
    /// floating capsule morph, `chromeAlpha(for:)` keeps the chrome alpha at 0 through the resize
    /// band and only fades it in over `[handoffStart, 1]`, so container alpha no longer reflects the
    /// real fraction mid-transition. Call sites that reapply visibility need the true fraction.
    var currentBarsVisibility: CGFloat {
        lastChromeVisibilityPercent
    }

    func restoreCurrentBarsVisibilityAfterLayoutRefresh() {
        applyBarsVisibilityState(lastChromeVisibilityPercent, postChromeVisibilityNotification: false)
        view.layoutIfNeeded()
    }

    // 1.0 - full size, 0.0 - hidden
    func updateToolbarConstant(_ ratio: CGFloat) {
        var bottomHeight = toolbarHeight
        if viewCoordinator.addressBarPosition.isBottom && !isInMinimalChromeLayout {
            // When position is set to bottom, contentContainer is pinned to top
            // of navigationBarContainer, hence the adjustment.
            // Skip in minimal chrome — nav bar is positioned independently via keyboard constraint.
            bottomHeight += viewCoordinator.navigationBarContainer.frame.height
        }
        bottomHeight += view.safeAreaInsets.bottom
        // Minimal chrome owns the toolbar slot as a permanent offscreen spacer for the bottom
        // address bar, and on iPad the toolbar is permanently hidden (its layout slot would
        // otherwise leave a 49pt gap below the webview). Everywhere else the slot tracks
        // `ratio` (chrome-animator visibility).
        let multiplier = (viewCoordinator.toolbar.isHidden || isInMinimalChromeLayout) ? 1.0 : 1.0 - ratio
        viewCoordinator.constraints.toolbarBottom.constant = bottomHeight * multiplier

        if isInMinimalChromeLayout, viewCoordinator.addressBarPosition.isBottom {
            let navBarHeight = viewCoordinator.navigationBarContainer.frame.height
            viewCoordinator.navigationBarContainer.transform = CGAffineTransform(translationX: 0, y: navBarHeight * (1.0 - ratio))
        }
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

    func handleFavoriteSelected(_ favorite: BookmarkEntity) {
        guard let url = favorite.urlObject else { return }

        // Handle shortcuts for internal testing
        if let favUrl = favorite.url, let url = URL(string: favUrl), internalUserCommands.handle(url: url) {
            dismissSuggestionTray()
            return
        }

        postIdleSessionInstrumentation.sessionEnded(reason: .favoriteSelected)
        newTabPageViewController?.chromeDelegate = nil
        dismissOmniBar()
        favicons.loadFavicon(forDomain: url.host, intoCache: .fireproof, fromCache: .tabs)
        if url.isBookmarklet() {
            executeBookmarklet(url)
        } else {
            loadUrlRespectingAIBoundary(url)
        }
        showHomeRowReminder()
    }

    func loadUrlRespectingAIBoundary(_ url: URL, fromExternalLink: Bool = false) {
        let decision = AIBoundaryNavigationDecision.forProgrammaticNavigation(
            currentIsAI: currentTab?.isAITab == true,
            currentHasContent: currentTab?.tabModel.link != nil,
            targetIsAI: url.isDuckAIURL,
            unifiedToggleInputAvailable: unifiedToggleInputFeature.isAvailable
        )
        switch decision {
        case .openInNewTab:
            // Dismiss contextual onboarding before duck.ai opens via UTI.
            if let tab = currentTab {
                tab.contextualOnboardingPresenter.dismissContextualOnboardingIfNeeded(from: tab)
            }
            loadUrlInNewTab(url, inheritedAttribution: nil, fromExternalLink: fromExternalLink)
        case .loadInPlace:
            loadUrl(url, fromExternalLink: fromExternalLink)
        }
    }


    func handleSuggestionSelected(_ suggestion: Suggestion) {
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.barUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
        newTabPageViewController?.chromeDelegate = nil
        dismissOmniBar()
        viewCoordinator.omniBar.cancel()
        switch suggestion {
        case .phrase(phrase: let phrase):
            if let url = URL.makeSearchURL(query: phrase, useUnifiedLogic: isUnifiedURLPredictionEnabled, forceSearchQuery: true) {
                loadUrlRespectingAIBoundary(url)
            } else {
                Logger.lifecycle.error("Couldn't form URL for suggestion: \(phrase, privacy: .public)")
            }

        case .website(url: let url):
            if url.isBookmarklet() {
                executeBookmarklet(url)
            } else {
                loadUrlRespectingAIBoundary(url)
            }

        case .bookmark(_, url: let url, _, _):
            loadUrlRespectingAIBoundary(url)

        case .historyEntry(_, url: let url, _):
            loadUrlRespectingAIBoundary(url)

        case .openTab(title: _, url: let url, tabId: let tabId, _):
            if newTabPageViewController != nil, let tab = tabManager.currentTabsModel.currentTab {
                self.closeTab(tab)
            }
            loadUrlInNewTab(url, reuseExisting: tabId.map(ExistingTabReusePolicy.tabWithId) ?? .any, inheritedAttribution: .noAttribution)

        case .askAIChat(let value):
            // We intentionally don't forward the resolved model config: the suggestion is offered
            // from Search mode where the model chip is hidden and the user hasn't chosen a model.
            _ = unifiedToggleInputCoordinator?.prepareExternalPromptSubmission()
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

    func onEditFavorite(_ favorite: BookmarkEntity) {
        segueToEditBookmark(favorite)
    }

    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?) {
        // A Duck.ai submission IS Duck.ai mode — commit that directly rather than re-reading the live
        // toggle, which a refresh-on-submit can reset to the stored last-used before we read it.
        commitToggleMode(.aiChat)
        
        let controlValues = viewCoordinator.omniBar.iPadDuckAIControlValues
        openAIChat(query, autoSend: true, tools: tools ?? controlValues.selectedTools,
                   modelId: controlValues.selectedModelId,
                   reasoningEffort: controlValues.selectedReasoningEffort,
                   images: controlValues.selectedImages,
                   files: controlValues.selectedFiles)
    }

    func onChatHistorySelected(url: URL) {
        postIdleSessionInstrumentation.sessionEnded(reason: .chatSelected)
        // Route through boundary helper so NTP transforms in-place; web→chat spawns a new tab; chat→chat stays. Matches `onPromptSubmitted`.
        loadUrlRespectingAIBoundary(url)
    }

    func onViewAllChatsSelected() {
        openAIChatHistory(source: .addressBar)
    }

    func onAIChatQueryUpdated(_ query: String) {
        iPadAIChatQuery = query
        refreshPopoverSuggestions()
    }

    // Arrow keys in Duck.ai mode drive the unified Duck.ai popover (recents + URL hits + Search row).
    func isAIChatSuggestionsNavigationAvailable() -> Bool {
        guard isModeToggleInAIChatMode, !viewCoordinator.suggestionTrayContainer.isHidden else { return false }
        return suggestionTrayController?.popoverMode == .duckAI
            && suggestionTrayController?.popoverDuckAIHasContent == true
    }

    func hasAIChatSuggestionsHighlight() -> Bool {
        suggestionTrayController?.hasDuckAIHighlight ?? false
    }

    func onAIChatSuggestionsMoveSelectionDown() {
        suggestionTrayController?.duckAIKeyboardMoveSelectionDown()
    }

    func onAIChatSuggestionsMoveSelectionUp() {
        suggestionTrayController?.duckAIKeyboardMoveSelectionUp()
    }

    func onAIChatSuggestionsActivateHighlight() -> Bool {
        suggestionTrayController?.activateHighlightedDuckAISuggestion() ?? false
    }

    func onAIChatSuggestionsClearHighlight() {
        guard isModeToggleInAIChatMode else { return }
        suggestionTrayController?.clearDuckAIKeyboardSelection()
    }

    func didRequestCurrentURL() -> URL? {
        return currentTab?.url
    }
    
    func onCustomizableButtonPressed() {
        guard mobileCustomization.state.isEnabled else {
            shareCurrentURLFromAddressBar()
            return
        }

        handleCustomizableAddressBarButtonPressed()
    }

    func selectedSuggestion() -> Suggestion? {
        return suggestionTrayController?.selectedSuggestion
    }

    func onOmniSuggestionSelected(_ suggestion: Suggestion) {
        autocomplete(selectedSuggestion: suggestion)
    }

    func onOmniQueryUpdated(_ updatedQuery: String) {
        // Duck.ai text changes arrive via onAIChatQueryUpdated; don't show search here.
        if isModeToggleInAIChatMode {
            return
        }

        if isPad {
            // iPad: the single authority decides search content for the typed text.
            refreshPopoverSuggestions()
            return
        }

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
        // A search submission IS search mode — commit directly (see onPromptSubmitted).
        commitToggleMode(.search)
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        // Hide suggestion tray before kicking off navigation. refreshOmniBar()
        // queues an async swipe-tabs collection reload via applyWidth(); that
        // reload re-parents the OmniBar cell and fires textFieldDidEndEditing
        // on a later runloop tick, before dismissOmniBar reaches hideSuggestionTray.
        // Hiding the tray up front ensures onEditingEnd sees autocomplete=false
        // and resolves to .dismissed, not .suspended.
        hideSuggestionTray()
        omniBar.cancel()
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.barUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
        loadQuery(query)
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

        // Determine context for menu building
        let context: BrowsingMenuContext
        if newTabPageViewController != nil {
            context = .newTabPage
        } else if aichatFullModeFeature.isAvailable && tab.isAITab {
            context = .aiChatTab
        } else {
            context = .website
        }
        
        if browsingMenuSheetCapability.isEnabled {
            launchSheetBrowsingMenu(in: context, tabController: tab)
        } else {
            launchDefaultBrowsingMenu(in: context, tabController: tab)
        }

        // Remove view highlighter in this run loop. Menu items will be highlighted after presentation
        ViewHighlighter.hideAll()

        tab.didLaunchBrowsingMenu()

        let modeParam = [PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue]
        switch context {
        case .newTabPage:
            Pixel.fire(pixel: .browsingMenuOpenedNewTabPage, withAdditionalParameters: modeParam)
        case .aiChatTab:
            Pixel.fire(pixel: .browsingMenuOpened, withAdditionalParameters: modeParam)
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsMenuOpened)
        case .website:
            Pixel.fire(pixel: .browsingMenuOpened, withAdditionalParameters: modeParam)

            if tab.isError {
                Pixel.fire(pixel: .browsingMenuOpenedError)
            }
        }
        productSurfaceTelemetry.menuUsed()
    }

    private func launchDefaultBrowsingMenu(in context: BrowsingMenuContext, tabController tab: TabViewController) {
        let menuEntries: [BrowsingMenuEntry]
        let headerEntries: [BrowsingMenuEntry]

        switch context {
        case .newTabPage:
            menuEntries = tab.buildShortcutsMenu()
            headerEntries = []

        case .aiChatTab:
            menuEntries = tab.buildAITabMenu()
            headerEntries = tab.buildAITabMenuHeaderContent()

        case .website:
            menuEntries = tab.buildBrowsingMenu(with: menuBookmarksViewModel,
                                                mobileCustomization: mobileCustomization,
                                                clearTabsAndData: onFirePressed)
            headerEntries = tab.buildBrowsingMenuHeaderContent()
        }

        let browsingMenu: BrowsingMenuViewController =
        BrowsingMenuViewController.instantiate(headerEntries: headerEntries,
                                               menuEntries: menuEntries,
                                               daxDialogsManager: daxDialogsManager)
        browsingMenu.isUsingSingleBar = isUsingSingleBar
        browsingMenu.onDismiss = { wasActionSelected in
            self.showMenuHighlighterIfNeeded()
            self.viewCoordinator.menuToolbarButton.isEnabled = true
            if !wasActionSelected {
                Pixel.fire(pixel: .browsingMenuDismissed)
            }
        }

        let highlightTag = menuHighlightingTag

        let controller = browsingMenu
        let presentationCompletion = {
            guard let highlightTag else { return }
            switch highlightTag {
            case .favorite:
                browsingMenu.highlightAddFavorite()

            case .fire:
                browsingMenu.highlightFireButton()
            }
        }

        controller.modalPresentationStyle = .custom

        present(controller, animated: true, completion: presentationCompletion)
    }

    private func launchSheetBrowsingMenu(in context: BrowsingMenuContext, tabController tab: TabViewController) {
        guard let model = tab.buildSheetBrowsingMenu(
            context: context,
            with: menuBookmarksViewModel,
            mobileCustomization: mobileCustomization,
            browsingMenuSheetCapability: browsingMenuSheetCapability,
            clearTabsAndData: onFirePressed
        ) else {
            viewCoordinator.menuToolbarButton.isEnabled = true
            return
        }

        let view = BrowsingMenuSheetView(model: model,
                                         headerDataSource: browsingMenuHeaderDataSource,
                                         highlightRowWithTag: menuHighlightingTag,
                                         onDismiss: { wasActionSelected in
                                             self.showMenuHighlighterIfNeeded()
                                             self.viewCoordinator.menuToolbarButton.isEnabled = true
                                             if !wasActionSelected {
                                                 Pixel.fire(pixel: .browsingMenuDismissed)
                                             }
                                         })

        let controller = BrowsingMenuSheetViewController(rootView: view)
        let contentHeight = model.estimatedContentHeight(
            headerDataSource: browsingMenuHeaderDataSource,
            verticalSizeClass: traitCollection.verticalSizeClass
        )

        let initialDetentHeight = model.estimatedInitialDetentHeight(
            headerDataSource: browsingMenuHeaderDataSource,
            verticalSizeClass: traitCollection.verticalSizeClass
        )

        func configureSheetPresentationController(_ sheet: UISheetPresentationController) {
            if context == .newTabPage {
                if #available(iOS 16.0, *) {
                    sheet.detents = [.custom { _ in contentHeight }]
                } else {
                    sheet.detents = [.medium()]
                }
            } else if let initialDetentHeight, #available(iOS 16.0, *) {
                sheet.detents = [.custom { _ in initialDetentHeight }, .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            if #unavailable(iOS 26) {
                sheet.preferredCornerRadius = 24
            }
        }

        let isiPad = UIDevice.current.userInterfaceIdiom == .pad
        controller.modalPresentationStyle = isiPad ? .popover : .pageSheet

        if let popoverController = controller.popoverPresentationController {
            popoverController.sourceView = omniBar.barView.menuButton
            controller.preferredContentSize = CGSize(width: 391, height: contentHeight)

            configureSheetPresentationController(popoverController.adaptiveSheetPresentationController)
        }

        if let sheet = controller.sheetPresentationController {
           configureSheetPresentationController(sheet)
        }

        self.present(controller, animated: true)
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
        fireControllerAwarePixel(ntp: .keyboardGoWhileOnNTP,
                                 serp: .keyboardGoWhileOnSERP,
                                 website: .keyboardGoWhileOnWebsite,
                                 aiChat: .keyboardGoWhileOnAIChat)
    }

    func fireControllerAwarePixel(ntp: Pixel.Event,
                                  serp: Pixel.Event,
                                  website: Pixel.Event,
                                  aiChat: Pixel.Event,
                                  additionalParameters: [String: String] = [:]) {
        if newTabPageViewController != nil {
            Pixel.fire(pixel: ntp, withAdditionalParameters: additionalParameters)
        } else if let currentTab {
            if currentTab.isAITab == true {
                Pixel.fire(pixel: aiChat, withAdditionalParameters: additionalParameters)
            } else if currentTab.url?.isDuckDuckGoSearch == true {
                Pixel.fire(pixel: serp, withAdditionalParameters: additionalParameters)
            } else {
                Pixel.fire(pixel: website, withAdditionalParameters: additionalParameters)
            }
        }
    }

    /// Whether suggestions are actually on screen. The iPad popover's controllers persist across a focus
    /// session even while hidden, so existence (`isShowingAutocompleteSuggestions`) isn't enough — gauge
    /// by the popover container's visibility too.
    private var areSuggestionsVisible: Bool {
        isShowingAutocompleteSuggestions && !viewCoordinator.suggestionTrayContainer.isHidden
    }

    func onEditingEnd() -> OmniBarEditingEndResult {
        if areSuggestionsVisible {
            return .suspended
        } else {
            newTabPageViewController?.dismissDuckAICompletionDialogIfNeededOnEditingEnd()
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

    @objc func onMenuToolbarLongPressed(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        onMenuLongPressed()
    }

    func onMenuLongPressed() {
        if featureFlagger.internalUserDecider.isInternalUser || isDebugBuild {
            segueToDebugSettings()
        } else {
            segueToSettings()
        }
    }

    func menuForOmniBarLongPress(in state: OmniBarState) -> UIMenu? {
        let isPrivacyProtectionEnabled: Bool
        if let url = currentTab?.url {
            isPrivacyProtectionEnabled = privacyConfigurationManager.privacyConfig.isProtected(domain: url.host)
        } else {
            isPrivacyProtectionEnabled = false
        }

        return longPressBarMenuBuilder.makeOmniBarMenu(context: .init(
            state: state,
            isFeatureEnabled: featureFlagger.isFeatureOn(.omniBarLongPressMenu),
            currentURL: currentTab?.url,
            isAITab: currentTab?.isAITab == true,
            isPad: isPad,
            addressBarPosition: appSettings.currentAddressBarPosition,
            isPrivacyProtectionEnabled: isPrivacyProtectionEnabled,
            onShare: { [weak self] in
                self?.shareCurrentURLFromAddressBar()
            },
            onCopy: { [weak self] url in
                self?.currentTab?.onCopyAction(forUrl: url)
            },
            onMoveAddressBar: { [weak self] in
                // iOS 26 has broken something so we have to use an animation
                //  to get symmetry in the movement (rather than disabling animations
                //  which doesn't appear to work properly on iOS 26.4,
                if #available(iOS 18.0, *) {

                    self?.viewCoordinator.navigationBarContainer.backgroundColor = .clear
                    self?.omniBar.prepareForMoveTransition()
                    UIView.animate(.smooth) {
                        self?.toggleAddressBarLocation()
                    } completion: {
                        self?.omniBar.moveTransitionCompleted()
                        self?.decorate()
                    }

                } else {
                    self?.toggleAddressBarLocation()
                }

            },
            onCloseTab: { [weak self] in
                guard let tab = self?.currentTab else { return }
                self?.tabDidRequestClose(tab.tabModel, behavior: .onlyClose, clearTabHistory: true)
            }
        ))
    }

    func onOmniBarLongPressMenuDisplayed() {
        longPressBarMenuBuilder.fireOmniBarMenuOpenPixel()
    }

    private func toggleAddressBarLocation() {
        let current = appSettings.currentAddressBarPosition
        appSettings.currentAddressBarPosition = current == .top ? .bottom : .top
        updateScrollInteractionIfNeeded()
        self.view.layoutIfNeeded()
    }

    // Refreshes the iOS 26 scroll-edge chrome interactions so they track the currently visible
    // page. Must be called on every content change (tab switch, address bar move, NTP attach),
    // otherwise the interactions keep pointing at a dismissed tab's scroll view.
    private func updateScrollInteractionIfNeeded() {
        guard #available(iOS 26, *) else { return }
        guard floatingUIManager.isFloatingUIEnabled else { return }

        // Detach any existing interactions from whatever views they're currently installed in.
        scrollEdgeInteractions.forEach { $0.view?.removeInteraction($0) }
        scrollEdgeInteractions.removeAll()

        // The scroll-edge chrome must track the currently visible scroll view. On the NTP (or any
        // tab without a web view) there's no scroll view to track, so we leave the interactions
        // detached rather than pointing them at a dismissed tab's scroll view.
        guard let scrollView = currentTab?.webView?.scrollView else { return }

        func attach(to view: UIView, onEdge edge: UIRectEdge) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.scrollView = scrollView
            interaction.edge = edge
            view.addInteraction(interaction)
            scrollEdgeInteractions.append(interaction)
        }

        if appSettings.currentAddressBarPosition == .top {
            attach(to: omniBar.barView, onEdge: .top)
            attach(to: floatingDomainCapsuleController.button, onEdge: .top)
        } else {
            attach(to: floatingDomainCapsuleController.button, onEdge: .bottom)
        }
        attach(to: viewCoordinator.toolbar, onEdge: .bottom)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        defer { super.motionEnded(motion, with: event) }

        guard motion == .motionShake, featureFlagger.internalUserDecider.isInternalUser || isDebugBuild else { return }
        guard AppUserDefaults().shakeToOpenDebugMenuEnabled else { return }
        guard Date().timeIntervalSince(lastForegroundEntryDate) > Self.shakeIgnoreIntervalAfterForeground else { return }

        var topVC: UIViewController = self
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        if !(topVC is DebugScreensViewController),
           !((topVC as? UINavigationController)?.viewControllers.first is DebugScreensViewController) {
            segueToDebugSettings()
        }
    }

    func performCancel(animated: Bool = true) {
        dismissOmniBar(animated: animated)
        omniBar.cancel()
        hideSuggestionTray()
        themeColorManager.updateThemeColor()
        self.showMenuHighlighterIfNeeded()
    }

    func onCancelPressed() {
        fireControllerAwarePixel(ntp: .addressBarCancelPressedOnNTP,
                                 serp: .addressBarCancelPressedOnSERP,
                                 website: .addressBarCancelPressedOnWebsite,
                                 aiChat: .addressBarCancelPressedOnAIChat)
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.backButtonUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.backPressed()
        performCancel()
    }

    func onAbortPressed() {
        Pixel.fire(pixel: .stopPageLoad)
        stopLoading()
    }

    func onClearTextPressed() {
        fireControllerAwarePixel(ntp: .addressBarClearPressedOnNTP,
                                 serp: .addressBarClearPressedOnSERP,
                                 website: .addressBarClearPressedOnWebsite,
                                 aiChat: .addressBarClearPressedOnAIChat)

        // The input is cleared programmatically, so its change delegate never fires; refresh so the
        // popover drops to recents-only / favorites (or collapses) for the now-empty query.
        if isPad {
            iPadAIChatQuery = ""
            refreshPopoverSuggestions()
        }
    }

    private func newTabShortcutAction() {
        Pixel.fire(pixel: .tabSwitchLongPressNewTab, withAdditionalParameters: [
            PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue
        ])
        guard !duckAIFireOnboardingFlow.controlsLocked else { return }
        postIdleSessionInstrumentation.sessionEnded(reason: .tabSwitcherSelected)
        newTab()
    }

    private func newFireTabLongPressMenuAction() {
        postIdleSessionInstrumentation.sessionEnded(reason: .tabSwitcherSelected)
        tabManager.setBrowsingMode(.fire, source: .longPressTabsIcon)
        newTab()
    }

    private func newNormalTabLongPressMenuAction() {
        postIdleSessionInstrumentation.sessionEnded(reason: .tabSwitcherSelected)
        tabManager.setBrowsingMode(.normal, source: .longPressTabsIcon)
        newTab()
    }

    private var isSERPPresented: Bool {
        guard let tabURL = currentTab?.url else { return false }
        return tabURL.isDuckDuckGoSearch
    }

    func onTextFieldWillBeginEditing(_ omniBar: OmniBarView, tapped: Bool) {
        // We don't want any action here if suggestions are still visible (existence alone isn't enough
        // on iPad, where the controllers persist hidden across the focus session).
        guard !areSuggestionsVisible else { return }

        // Dismiss contextual AI chat sheet when omni bar becomes active
        if let currentTab, tapped {
            currentTab.aiChatContextualSheetCoordinator.dismissSheet()
        }

        if let currentTab {
            viewCoordinator.omniBar.refreshText(forUrl: currentTab.url, forceFullURL: true)
        }

        if tapped {
            let modeParam = [PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue]
            fireControllerAwarePixel(ntp: .addressBarClickOnNTP,
                                     serp: .addressBarClickOnSERP,
                                     website: .addressBarClickOnWebsite,
                                     aiChat: .addressBarClickOnAIChat,
                                     additionalParameters: modeParam)
        }

        guard newTabPageViewController == nil else { return }

        if isPad {
            // iPad routes all suggestion show/hide through the focus model (favorites vs autocomplete
            // vs recents is decided there from the live state).
            refreshPopoverSuggestions()
        } else {
            guard !isModeToggleInAIChatMode else { return }
            if !skipSERPFlow, isSERPPresented, let query = omniBar.text {
                tryToShowSuggestionTray(.autocomplete(query: query))
            } else {
                tryToShowSuggestionTray(.favorites)
            }
        }
        themeColorManager.updateThemeColor()
    }

    private func installContextualSheetDismissGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissContextualSheetOnBackgroundTap))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        viewCoordinator.navigationBarContainer.addGestureRecognizer(tap)
    }

    @objc private func dismissContextualSheetOnBackgroundTap() {
        currentTab?.aiChatContextualSheetCoordinator.dismissSheet()
    }

    func dismissContextualSheetIfNeeded(completion: @escaping () -> Void) {
        guard let currentTab,
              currentTab.aiChatContextualSheetCoordinator.isSheetPresented,
              let sheetVC = currentTab.aiChatContextualSheetCoordinator.sheetViewController else {
            completion()
            return
        }

        sheetVC.dismiss(animated: true) {
            completion()
        }
    }

    func onTextFieldDidBeginEditing(_ omniBar: OmniBarView) -> Bool {

        let selectQueryText = !(isSERPPresented && !skipSERPFlow)
        skipSERPFlow = false
        
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }

        return selectQueryText
    }

    func shouldAutoSelectTextForSERPQuery() -> Bool {
        let shouldSelect = isSERPPresented && skipSERPFlow
        skipSERPFlow = false
        return shouldSelect
    }

    func onRefreshPressed() {
        hideSuggestionTray()
        currentTab?.refresh()
        hideNotificationBarIfBrokenSitePromptShown(afterRefresh: true)
    }

    func onAIChatPressed() {
        onAIChatPressed(prefilledText: nil)
    }

    func onAIChatPressed(prefilledText: String?) {
        ViewHighlighter.hideAll()
        hideSuggestionTray()

        let shouldPresentContextualSheet = currentTab?.tabModel.isHomeTab == false
            && aiChatContextualModeFeature.isAvailable
            && prefilledText == nil

        if let currentTab, shouldPresentContextualSheet {
            omniBar.endEditing()
            currentTab.presentContextualAIChatSheet(from: self)
        } else {
            openAIChatFromAddressBar(prefilledText: prefilledText)
        }
    }

    private func shareCurrentURLFromAddressBar() {
        Pixel.fire(pixel: .addressBarShare)
        guard let link = currentTab?.link else { return }
        currentTab?.onShareAction(forLink: link, fromView: viewCoordinator.omniBar.barView.customizableButton)
    }

    private func shareCurrentURLFromToolbar() {
        let targetView = viewCoordinator.toolbarFireButton
        // Pixels coming later.
        guard let link = currentTab?.link else { return }
        currentTab?.onShareAction(forLink: link, fromView: targetView)
    }

    private func openAIChatFromAddressBar(prefilledText: String?) {

        let isEditing: Bool
        let textFieldValue: String?
        if let prefilledText {
            isEditing = true
            textFieldValue = prefilledText
        } else {
            isEditing = omniBar.isTextFieldEditing
            textFieldValue = omniBar.text
        }
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

    func onVoiceSearchPressed() {
        handleVoiceSearchOpenRequest()
    }

    func onVoiceSearchPressed(preferredTarget: VoiceSearchTarget) {
        handleVoiceSearchOpenRequest(preferredTarget: preferredTarget)
    }

    func onDidBeginEditing() {
        // Omnibar got focus. Lift minimal chrome bar above keyboard.
        refreshMinimalChromeBottomAnchor()
        warmSearchTokenIfEligible()
    }

    /// Proactively warms the search token for enrolled treatment users when the search input begins editing.
    /// Called from every "editing began" entry point. Safe to over-call:
    /// the fetcher's refresh-ahead window coalesces redundant triggers.
    func warmSearchTokenIfEligible() {
        guard searchTokenExperiment.cohort == .treatment else { return }
        // Match the SERP navigation's UA exactly (the token is UA-bound): the tab's desktop state + a
        // duckduckgo.com URL, resolved through the same `agent(forUrl:isDesktop:)` the WebView uses.
        let isDesktop = currentTab?.tabModel.isDesktop ?? false
        let userAgent = DefaultUserAgentManager.shared.userAgent(isDesktop: isDesktop, url: .ddg)
        Task { await searchTokenFetcher.fetchIfNeeded(userAgent: userAgent) }
    }

    func onDidEndEditing() {
        // Restore the tab's committed mode — the user may have toggled without submitting.
        // Safe on iPhone: the experimental editing state prevents textFieldDidEndEditing from
        // firing (text field never becomes first responder during that flow).
        if let tab = tabManager.currentTabsModel.currentTab {
            viewCoordinator.omniBar.setSelectedTextEntryMode(initialOmnibarToggleMode(for: tab))
        }
        // Omnibar lost focus. Drop minimal chrome bar back to bottom.
        refreshMinimalChromeBottomAnchor()
    }

    // MARK: - iPad Expanded Omnibar

    func onOmniBarExpandedStateChanged(isExpanded: Bool) {
        if isExpanded {
            // Entering the expanded Duck.ai input — show its suggestions. Toggling back to search is
            // handled by `onToggleModeSwitched` and dismissing by the dismiss path.
            refreshPopoverSuggestions()
            guard expandedOmniBarDismissTapGesture == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissExpandedOmniBar))
            tap.cancelsTouchesInView = false
            viewCoordinator.contentContainer.addGestureRecognizer(tap)
            expandedOmniBarDismissTapGesture = tap
        } else {
            // The input collapsed while still in Duck.ai mode (e.g. a reload stole focus) — hide the
            // now-orphaned popover. A toggle to search flips the mode first, so this skips it there.
            if isModeToggleInAIChatMode {
                popoverSuggestionsCoordinator?.present(.none)
            }
            if let tap = expandedOmniBarDismissTapGesture {
                viewCoordinator.contentContainer.removeGestureRecognizer(tap)
                expandedOmniBarDismissTapGesture = nil
            }
        }
    }

    /// Re-evaluates the iPad popover from the live omnibar state via the pure `IPadOmnibarFocusModel`
    /// and applies its decision. All "what should show" rules live in the model; this only snapshots
    /// state and hands the result to the coordinator.
    private func refreshPopoverSuggestions() {
        guard isPad else { return }
        let surface = IPadOmnibarFocusModel.surface(for: currentOmnibarFocusContext())
        popoverSuggestionsCoordinator?.present(surface)
    }

    /// Snapshots the omnibar/page state the focus model decides from.
    private func currentOmnibarFocusContext() -> IPadOmnibarFocusModel.Context {
        let mode: IPadOmnibarFocusModel.Mode = isModeToggleInAIChatMode ? .duckAI : .search
        let fieldText = mode == .duckAI ? currentIPadAIQuery() : (viewCoordinator.omniBar.text ?? "")
        return IPadOmnibarFocusModel.Context(
            mode: mode,
            pageKind: currentOmnibarPageKind(),
            hasFavorites: suggestionTrayController?.canShow(for: .favorites) ?? false,
            fieldText: fieldText,
            pageURL: currentTab?.url?.absoluteString,
            userHasEditedText: omnibarHasUserEdit)
    }

    private func currentOmnibarPageKind() -> IPadOmnibarFocusModel.PageKind {
        if newTabPageViewController != nil { return .newTabPage }
        if isSERPPresented { return .serp }
        return .website
    }

    /// Whether the user has typed in the omnibar since the page URL was last displayed (a tap doesn't
    /// count). False means the field shows the unedited page URL.
    private var omnibarHasUserEdit: Bool {
        (viewCoordinator.omniBar as? OmniBarViewController)?.userDidEditText ?? false
    }

    private func teardownPopoverSuggestions() {
        guard isPad else { return }
        popoverSuggestionsCoordinator?.teardown()
    }

    @objc private func dismissExpandedOmniBar() {
        performCancel()
    }

    func onOmniBarExpandedContentSizeChanged() {
        // The expanded input grew or shrank (an attachment was added/removed) while a Duck.ai popover
        // is anchored beneath it — re-apply the inset so it follows instead of leaving a gap.
        guard isPad, isPopoverVisible, isModeToggleInAIChatMode else { return }
        suggestionTrayController?.setAdditionalTopInset(duckAIPopoverTopInset(), animated: true)
    }

    private func duckAIPopoverTopInset() -> CGFloat {
        guard let searchContainer = viewCoordinator.omniBar.barView.searchContainer else {
            return 0
        }
        let spacing: CGFloat = 12
        let containerFrame = searchContainer.convert(searchContainer.bounds, to: viewCoordinator.contentContainer)
        return max(0, containerFrame.maxY) + spacing
    }

    private func currentIPadAIQuery() -> String {
        guard let omniBarVC = viewCoordinator.omniBar as? OmniBarViewController else {
            return iPadAIChatQuery
        }
        if let expandable = omniBarVC.expandableBarView, expandable.isSearchAreaExpanded {
            return expandable.aiChatTextView.text ?? ""
        }
        return omniBarVC.text ?? iPadAIChatQuery
    }

    // MARK: - Experimental Address Bar (pixels only)
    func onExperimentalAddressBarTapped() {
        let modeParam = [PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue]
        ViewHighlighter.hideAll()
        fireControllerAwarePixel(ntp: .addressBarClickOnNTP,
                                 serp: .addressBarClickOnSERP,
                                 website: .addressBarClickOnWebsite,
                                 aiChat: .addressBarClickOnAIChat,
                                 additionalParameters: modeParam)
    }

    func onExperimentalAddressBarClearPressed() {
        fireControllerAwarePixel(ntp: .addressBarClearPressedOnNTP,
                                 serp: .addressBarClearPressedOnSERP,
                                 website: .addressBarClearPressedOnWebsite,
                                 aiChat: .addressBarClearPressedOnAIChat)
    }

    func onExperimentalAddressBarCancelPressed() {
        fireControllerAwarePixel(ntp: .addressBarCancelPressedOnNTP,
                                 serp: .addressBarCancelPressedOnSERP,
                                 website: .addressBarCancelPressedOnWebsite,
                                 aiChat: .addressBarCancelPressedOnAIChat)
        newTabPageViewController?.dismissDuckAICompletionDialogIfNeededOnEditingEnd()
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.backButtonUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.backPressed()
    }

    /// Delegate method called when the AI Chat left button is tapped
    func onAIChatLeftButtonPressed() {
        DailyPixel.fireDailyAndCount(pixel: .aiChatOmnibarSidebarButtonTapped)
        currentTab?.submitToggleSidebarAction()
    }

    /// Delegate method called when the omnibar branding area is tapped while in AI Chat mode.
    func onAIChatBrandingPressed() {
        ViewHighlighter.hideAll()
        Pixel.fire(pixel: .addressBarClickOnAIChat, withAdditionalParameters: [
            PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue
        ])
        viewCoordinator.omniBar.beginEditing(animated: true, forTextEntryMode: .aiChat)
    }

    func escapeHatchForEditingState() -> EscapeHatchModel? {
        guard idleReturnEligibilityManager.isEligibleForNTPAfterIdle(),
              tabManager.currentTabsModel.currentTab?.link == nil,
              let model = currentNTPEscapeHatch else {
            return nil
        }
        return model
    }

    private func clearEscapeHatch() {
        newTabPageViewController?.setEscapeHatch(nil)
        currentNTPEscapeHatch = nil
        unifiedToggleInputCoordinator?.clearEscapeHatch()
    }

    func useNewOmnibarTransitionBehaviour() -> Bool {
        escapeHatchForEditingState() != nil
    }

    func onSwitchToTab(_ tab: Tab) {
        let targetTabsModel = tabManager.tabsModel(for: tab.mode)
        guard targetTabsModel.tabExists(tab: tab) else {
            clearEscapeHatch()
            viewCoordinator.omniBar.endEditing()
            return
        }
        let currentTab = tabManager.currentTabsModel.currentTab
        guard tab !== currentTab else {
            viewCoordinator.omniBar.endEditing()
            return
        }
        let wasAfterIdle = currentTab?.openedAfterIdle ?? false
        ntpAfterIdleInstrumentation.returnToPageTapped(afterIdle: wasAfterIdle)
        postIdleSessionInstrumentation.sessionEnded(reason: .returnToPageTapped)
        viewCoordinator.omniBar.endEditing()
        if let currentTab {
            closeTab(currentTab)
        }
        selectTab(tab)
    }

    func onTabSwitcherRequested() {
        requestTabSwitcher()
    }

    func onToggleModeSwitched() {
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.toggleUsedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.toggleUsed()
        iPadAIChatQuery = currentIPadAIQuery()
        refreshPopoverSuggestions()
    }

    func onTextEntryModeDidChange(_ mode: TextEntryMode) {
        onToggleModeSwitched()
    }

    func preferredTextEntryModeForCurrentTab() -> TextEntryMode? {
        tabManager.currentTabsModel.currentTab.map { initialOmnibarToggleMode(for: $0) }
    }

    /// Shared commit logic for all toggle paths (iPad, iPhone editing state, unified toggle input).
    func commitToggleMode(_ mode: TextEntryMode) {
        toggleModeStorage.save(mode)
    }

    func isCurrentTabFireTab() -> Bool {
        tabManager.currentTabsModel.currentTab?.fireTab ?? false
    }
}

// MARK: - AutocompleteViewControllerDelegate Methods
extension MainViewController: PopoverSuggestionsHosting {

    func showPopoverSearchList(query: String) {
        // Animate the anchor only when the popover is already on screen (a mode toggle); a fresh show
        // must snap to the inset, else it slides in from the previous session's Duck.ai position.
        suggestionTrayController?.setAdditionalTopInset(0, animated: isPopoverVisible)
        tryToShowSuggestionTray(.autocomplete(query: query))
    }

    func showPopoverDuckAIList(query: String) {
        let isDuckAIInputExpanded = (viewCoordinator.omniBar as? OmniBarViewController)?
            .expandableBarView?.isSearchAreaExpanded ?? false
        guard isDuckAIInputExpanded else {
            hidePopover()
            return
        }
        suggestionTrayController?.setAdditionalTopInset(duckAIPopoverTopInset(), animated: isPopoverVisible)
        tryToShowSuggestionTray(.duckAISuggestions(query: query))
    }

    private var isPopoverVisible: Bool {
        !viewCoordinator.suggestionTrayContainer.isHidden
    }

    @discardableResult
    func showPopoverFavorites() -> Bool {
        // Favorites anchor under the collapsed search bar — reset the Duck.ai inset or a gap remains.
        suggestionTrayController?.setAdditionalTopInset(0, animated: isPopoverVisible)
        return tryToShowSuggestionTray(.favorites)
    }

    /// Hides the container but keeps the list surfaces alive, avoiding remove/reinstall flicker on toggle.
    func hidePopover() {
        suggestionTrayController?.clearKeyboardSelections()
        viewCoordinator.omniBar.showSeparator()
        viewCoordinator.suggestionTrayContainer.isHidden = true
        currentTab?.webView.accessibilityElementsHidden = false
    }
}

extension MainViewController: SuggestionTrayDuckAINavigationDelegate {

    func suggestionTrayDidSelectDuckAI(_ selection: DuckAISuggestionsSelection) {
        switch selection {
        case .chat(let chat):
            DailyPixel.fireDailyAndCount(pixel: chat.isPinned ? .aiChatRecentChatSelectedPinned : .aiChatRecentChatSelected)
            if isPad {
                DailyPixel.fireDailyAndCount(pixel: chat.isPinned ? .aiChatIPadToggleRecentChatSelectedPinned : .aiChatIPadToggleRecentChatSelected)
            }
            Pixel.fire(pixel: .autocompleteDuckAIClickChatHistory)
            onChatHistorySelected(url: aiChatSettings.aiChatURL.withChatID(chat.chatId))
        case .url(let suggestion):
            handleSuggestionSelected(suggestion)
        case .searchDuckDuckGo(let query):
            Pixel.fire(pixel: .autocompleteDuckAIClickSearchDuckDuckGo)
            viewCoordinator.omniBar.setSelectedTextEntryMode(.search)
            loadQuery(query)
        case .viewAllChats:
            onViewAllChatsSelected()
        }
    }

    func suggestionTrayDidDeleteDuckAIURLSuggestion() {
        // The Duck.ai surface already refetched its own URLs; the search surface re-fetches on next query.
    }

    func suggestionTrayRequestsDuckAIChatDeletionConfirmation(for chat: AIChatSuggestion,
                                                              sourceRect: CGRect,
                                                              onConfirm: @escaping () -> Void,
                                                              onCancel: @escaping () -> Void) {
        FireConfirmationPresenter.presentFireConfirmation(suggestion: chat,
                                                          presenter: self,
                                                          sourceRect: sourceRect,
                                                          onCancel: onCancel,
                                                          onConfirm: onConfirm)
    }
}

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

    func autocomplete(deletedSuggestion suggestion: Suggestion) {
        // NO-OP
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
        // In iPad duck.ai mode the visible editor is the chat text view, so keep the highlight on the
        // suggestion row rather than writing the hidden search field.
        guard !isModeToggleInAIChatMode else { return }

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
}

extension MainViewController: EscapeHatchActionRouter {
    func escapeHatchDidRequestSwitch(to tab: Tab) {
        guard tabManager.tabsModel(for: tab.mode).tabExists(tab: tab) else {
            clearEscapeHatch()
            return
        }

        onSwitchToTab(tab)
    }

    func escapeHatchDidRequestClose(_ tab: Tab) {
        let targetTabsModel = tabManager.tabsModel(for: tab.mode)
        guard targetTabsModel.tabExists(tab: tab) else {
            clearEscapeHatch()
            return
        }

        tabManager.remove(tab: tab, in: targetTabsModel)
        refreshTabIcon()
        refreshTabBar()
        ntpAfterIdleInstrumentation.escapeHatchCloseTabTapped()
        postIdleSessionInstrumentation.closeTabTapped()

        if targetTabsModel.hasActiveTabs {
            return
        }

        // Keep the hatch (and the current focus state) so the card collapses to the expanded pill,
        // consistent with the delete flow which also preserves focus.
    }

    func escapeHatchDidRequestBurnWithConfirmation(_ tab: Tab, sourceRect: CGRect) {
        let targetTabsModel = tabManager.tabsModel(for: tab.mode)
        guard targetTabsModel.tabExists(tab: tab) else {
            clearEscapeHatch()
            return
        }

        // Captured before the confirmation dialog steals focus, so we can restore the keyboard afterwards.
        let wasInFocusMode = isEscapeHatchInFocusMode
        let tabViewModel = tabManager.viewModel(for: tab)
        let presenter = FireConfirmationPresenter()
        presenter.presentFireConfirmation(
            on: topPresentedViewController,
            sourceRect: sourceRect,
            tabViewModel: tabViewModel,
            pixelSource: .escapeHatch,
            fireContext: .singleTab,
            browsingMode: tab.mode,
            onConfirm: { [weak self] fireRequest in
                self?.forgetAllWithAnimation(request: fireRequest) { [weak self] in
                    self?.restoreTabSwitcherOnlyHatchAfterBurn()
                    self?.restoreFocusModeAfterBurnIfNeeded(wasInFocusMode: wasInFocusMode)
                }
                self?.postIdleSessionInstrumentation.burnTabTapped()
            },
            onCancel: { }
        )

        ntpAfterIdleInstrumentation.escapeHatchBurnTapped(requiredConfirmation: true)
    }

    func escapeHatchDidRequestBurnImmediately(_ tab: Tab) {
        let targetTabsModel = tabManager.tabsModel(for: tab.mode)
        guard targetTabsModel.tabExists(tab: tab) else {
            clearEscapeHatch()
            return
        }

        let wasInFocusMode = isEscapeHatchInFocusMode
        let tabViewModel = tabManager.viewModel(for: tab)
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .tab(viewModel: tabViewModel),
            source: .escapeHatch
        )

        forgetAllWithAnimation(request: request) { [weak self] in
            self?.restoreTabSwitcherOnlyHatchAfterBurn()
            self?.restoreFocusModeAfterBurnIfNeeded(wasInFocusMode: wasInFocusMode)
        }
        ntpAfterIdleInstrumentation.escapeHatchBurnTapped(requiredConfirmation: false)
        postIdleSessionInstrumentation.burnTabTapped()
    }

    func escapeHatchDidRequestTabSwitcher() {
        requestTabSwitcher()
        ntpAfterIdleInstrumentation.escapeHatchTabSwitcherTapped()
    }

    func escapeHatchDidChangeOpeningScreenOption(to option: AfterInactivityOption) {
        ntpAfterIdleInstrumentation.escapeHatchOptionChanged(to: option)
        postIdleSessionInstrumentation.openingScreenChanged()
    }

}

extension MainViewController: NewTabPageControllerDelegate {

    func newTabPageDidSelectFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        self.onSelectFavorite(favorite)
    }

    func newTabPageDidEditFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        segueToEditBookmark(favorite)
    }

    func newTabPageDidRequestFaviconsFetcherOnboarding(_ controller: NewTabPageViewController) {
        faviconsFetcherOnboarding.presentOnboardingIfNeeded(from: self)
    }

    func newTabPageDidRequestSwitchToTab(_ controller: NewTabPageViewController, tab: Tab) {
        let targetTabsModel = tabManager.tabsModel(for: tab.mode)
        guard targetTabsModel.tabExists(tab: tab) else {
            clearEscapeHatch()
            return
        }
        let currentTab = tabManager.currentTabsModel.currentTab
        guard tab !== currentTab else { return }
        let wasAfterIdle = currentTab?.openedAfterIdle ?? false
        ntpAfterIdleInstrumentation.returnToPageTapped(afterIdle: wasAfterIdle)
        postIdleSessionInstrumentation.sessionEnded(reason: .returnToPageTapped)
        if let currentTab {
            closeTab(currentTab)
        }
        selectTab(tab)
        clearEscapeHatch()
    }

    func newTabPageDidRequestTabSwitcher(_ controller: NewTabPageViewController) {
        ntpAfterIdleInstrumentation.escapeHatchTabSwitcherTapped()
        requestTabSwitcher()
    }

    func newTabPageDidDismissDuckAIFireOnboardingCompletion(_ controller: NewTabPageViewController) {
        markSearchContextualOnboardingAsSeen()
    }

}

extension MainViewController: TabDelegate {

    func searchToken(for tab: TabViewController) -> String? {
        searchTokenFetcher.retrieveToken()
    }

    var isEmailProtectionSignedIn: Bool {
        emailManager.isSignedIn
    }

    func tabDidRequestNewPrivateEmailAddress(tab: TabViewController) {
        newEmailAddress()
    }

    func tabDidRequestSetYouTubeAdBlockingEnabled(_ enabled: Bool, tab: TabViewController) {
        setYouTubeAdBlockingEnabled(enabled)
        if enabled {
            tab.reload()
        }
    }

    func tabDidRequestYouTubeAdBlockPicker(tab: TabViewController) {
        let view = YouTubeAdBlockPickerView { [weak self, weak tab] mode in
            guard let self else { return }
            switch mode {
            case .alwaysOn:
                self.adBlockingAvailability.clearDisableUntilRelaunch()
                DailyPixel.fireDailyAndCount(pixel: .webExtensionAdBlockingPickerAlwaysOn,
                                             pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes)
            case .disableUntilRelaunch:
                self.adBlockingAvailability.disableUntilRelaunch()
                DailyPixel.fireDailyAndCount(pixel: .webExtensionAdBlockingPickerDisableUntilRelaunch,
                                             pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes)
            case .alwaysOff:
                self.setYouTubeAdBlockingEnabled(false)
                DailyPixel.fireDailyAndCount(pixel: .webExtensionAdBlockingPickerAlwaysOff,
                                             pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes)
            }
            self.dismiss(animated: true) { [weak self, weak tab] in
                switch mode {
                case .disableUntilRelaunch, .alwaysOff:
                    tab?.reload()
                    self?.presentYouTubeAdBlockBreakageReport()
                case .alwaysOn:
                    // No-op: the picker is only reachable when ad blocking is fully enabled,
                    // so clearDisableUntilRelaunch() above is a no-op and no reload is needed.
                    break
                }
            }
        }
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = UIColor(designSystemColor: .surface)
        presentYouTubeAdBlockSheet(controller, grabberVisible: true)
    }

    func tabDidRequestYouTubeAdBlockUnavailableDialog(tab: TabViewController) {
        let storage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> = keyValueStore.throwingKeyedStoring()
        guard (try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockUnavailableNoticeShown)) != true else { return }
        try? storage.set(true, for: \YouTubeAdBlockingKeys.youTubeAdBlockUnavailableNoticeShown)

        let view = YouTubeAdBlockUnavailableView(
            onAcknowledge: { [weak self] in self?.dismiss(animated: true) },
            onClose: { [weak self] in self?.dismiss(animated: true) }
        )
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = UIColor(designSystemColor: .surface)
        presentYouTubeAdBlockSheet(controller)
    }

    private func presentYouTubeAdBlockBreakageReport() {
        let view = YouTubeAdBlockBreakageReportView(
            onSend: { [weak self] in
                DailyPixel.fireDailyAndCount(pixel: .webExtensionAdBlockingBreakageReportEntered,
                                             pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes)
                self?.dismiss(animated: true) { [weak self] in
                    self?.segueToReportBrokenSite()
                }
            },
            onCancel: { [weak self] in self?.dismiss(animated: true) }
        )
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        presentYouTubeAdBlockSheet(controller)
    }

    private func presentYouTubeAdBlockSheet<Content: View>(_ controller: UIHostingController<Content>, grabberVisible: Bool = false) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.modalPresentationStyle = .formSheet
            let formSheetWidth: CGFloat = 540
            let contentHeight = controller.sizeThatFits(in: CGSize(width: formSheetWidth, height: .infinity)).height
            controller.preferredContentSize = CGSize(width: formSheetWidth, height: contentHeight)
        } else {
            controller.modalPresentationStyle = .pageSheet
            if let sheet = controller.sheetPresentationController {
                if #available(iOS 16.0, *) {
                    let fittingWidth = self.view.bounds.width
                    let contentHeight = controller.sizeThatFits(in: CGSize(width: fittingWidth, height: .infinity)).height
                    sheet.detents = [.custom { _ in contentHeight }]
                } else {
                    sheet.detents = [.medium()]
                }
                sheet.prefersGrabberVisible = grabberVisible
                if #unavailable(iOS 26) {
                    sheet.preferredCornerRadius = SheetMetrics.cornerRadius
                }
            }
        }
        present(controller, animated: true)
    }

    private func setYouTubeAdBlockingEnabled(_ enabled: Bool) {
        adBlockingAvailability.clearDisableUntilRelaunch()
        let storage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> = keyValueStore.throwingKeyedStoring()
        let disclosureVisibleAtToggle = (try? storage.value(for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)) != true
        try? storage.set(enabled, for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled)
        if !enabled {
            try? storage.set(false, for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
        } else if disclosureVisibleAtToggle {
            try? storage.set(true, for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
        }
        NotificationCenter.default.post(name: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification, object: nil)
    }

    func tabDidEngageWithPage(_ tab: TabViewController) {
        postIdleSessionInstrumentation.pageEngaged()
    }

    func tab(_ tab: TabViewController, didFailDuckAINavigationFor url: URL, error: Error) {
        duckAIWideEventInstrumentation.pageLoadFailed(scope: .tab(tab.tabModel.uid), error: error)
    }

    var isAIChatEnabled: Bool {
        return aiChatSettings.isAIChatEnabled
    }
    
    func tab(_ tab: TabViewController,
             didRequestNewWebViewWithConfiguration configuration: WKWebViewConfiguration,
             for navigationAction: WKNavigationAction,
             inheritingAttribution: AdClickAttributionLogic.State?) -> WKWebView? {
        capturePreviewForTab(tab)
        hideNotificationBarIfBrokenSitePromptShown()
        showBars()
        currentTab?.dismiss()
        tab.aiChatContextualSheetCoordinator.dismissSheet()
        themeColorManager.updateThemeColor()

        // Don't use a request or else the page gets stuck on "about:blank"
        let newTab = tabManager.addURLRequest(nil,
                                              with: configuration,
                                              inheritedAttribution: inheritingAttribution)
        newTab.openedByPage = true
        newTab.openingTab = tab
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)

        newTabAnimation {
            guard self.tabManager.currentTabsModel.tabs.contains(newTab.tabModel) else { return }

            self.dismissOmniBar()
            self.attachTab(tab: newTab)
            self.refreshOmniBar()
        }

        return newTab.webView
    }

    func tabDidRequestClose(_ tab: Tab,
                            behavior: TabClosingBehavior,
                            clearTabHistory: Bool) {
        closeTab(tab,
                 behavior: behavior,
                 clearTabHistory: clearTabHistory)
    }

    func tabLoadingStateDidChange(tab: TabViewController) {
        if tab.isLoading {
            duckAIFireOnboardingFlow.triggerWorkItem?.cancel()
            duckAIFireOnboardingFlow.triggerWorkItem = nil
        } else {
            scheduleDuckAIFireOnboardingAfterLoadIfNeeded(for: tab)
            if duckAIFireOnboardingFlow.shouldForcePostFireAddressBarPickerRestore && currentTab == tab {
                restorePostFireAddressBarPickerIfNeeded()
            }
        }

        guard currentTab == tab else { return }
        refreshControls()
        themeColorManager.updateThemeColor()
        tabManager.save()
        refreshTabBar()
        // note: model in swipeTabsCoordinator doesn't need to be updated here
        // https://app.asana.com/0/414235014887631/1206847376910045/f
    }

    func tabDidFinishNavigation(_ tab: TabViewController) {
        // For the current tab, `tabLoadingStateDidChange` (called immediately before this)
        // already triggers a save, so skip here to avoid a redundant save in the same run loop.
        guard currentTab != tab else { return }
        tabManager.save()
        tabsBarController?.reloadCell(for: tab.tabModel)
    }

    func tab(_ tab: TabViewController, didUpdatePreview preview: UIImage) {
        previewsSource.update(preview: preview, forTab: tab.tabModel)
    }

    func tabWillRequestNewTab(_ tab: TabViewController) -> UIKeyModifierFlags? {
        keyModifierFlags
    }

    func tabDidRequestNewTab(_ tab: TabViewController) {
        _ = findInPageView?.resignFirstResponder()
        // Pre-arm logo hiding BEFORE newTab() because attachHomeScreen() may call
        // omniBar.beginEditing(animated:) when KeyboardSettings.onNewTab is enabled, which
        // would create the editing-state VC before presentChatPathOnboardingCompletionIfNeeded()
        // gets a chance to set the pending flag.
        if daxDialogsManager.chatPathPhase == .trackerToEOJ, aiChatSettings.isAIChatEnabled {
            omniBar.setEditingStateLogoHidden(true)
        }
        newTab()
    }

    func tabDidRequestNewVoiceChat(_ tab: TabViewController) {
        // Same as the Duck.ai header Plus-menu "New Voice Chat".
        aiChatTabChatHeaderDidTapNewVoiceChat()
    }

    private func presentChatPathOnboardingCompletionIfNeeded() {
        guard daxDialogsManager.chatPathPhase == .trackerToEOJ,
              aiChatSettings.isAIChatEnabled else { return }
        let message = UserText.Onboarding.DuckAIQuery.completionOnboardingMessage
        // Hide the NTP synchronously, before any frame is rendered, so its empty-state Dax can't
        // flash before the editing-state transition begins. Restored by NewTabPageViewController
        // on every dismissal path.
        newTabPageViewController?.view.alpha = 0
        DispatchQueue.main.async { [weak self] in
            self?.newTabPageViewController?.showDuckAIOnboardingCompletionWithActiveAddressBar(message: message)
        }
    }
    
    func newTab(reuseExisting: Bool) {
        newTab(reuseExisting: reuseExisting, allowingKeyboard: false)
    }

    func tabDidRequestActivate(_ tab: TabViewController) {
        transitionTo(tab: tab, from: nil)
    }

    func tab(_ tab: TabViewController,
             didRequestNewBackgroundTabForUrl url: URL,
             inheritingAttribution attribution: AdClickAttributionLogic.State?) {
        _ = tabManager.add(url: url, inBackground: true, inheritedAttribution: attribution)
        animateBackgroundTab()
    }

    func tab(_ tab: TabViewController,
             didRequestNewFireTabForUrl url: URL,
             inheritingAttribution attribution: AdClickAttributionLogic.State?) {
        tabManager.setBrowsingMode(.fire, source: .longPressLink)
        loadUrlInNewTab(url, inheritedAttribution: attribution)
    }

    func capturePreviewForTab(_ tab: TabViewController) {
        // Capture source tab preview now; otherwise its thumbnail stays stale once we switch to the new tab.
        guard tab.link != nil, let image = tab.preparePreviewSync() else { return }
        previewsSource.update(preview: image, forTab: tab.tabModel)
    }

    func tab(_ tab: TabViewController,
             didRequestNewTabForUrl url: URL,
             openedByPage: Bool,
             inheritingAttribution attribution: AdClickAttributionLogic.State?) {
        _ = findInPageView?.resignFirstResponder()
        hideNotificationBarIfBrokenSitePromptShown()
        tab.aiChatContextualSheetCoordinator.dismissSheet()
        if openedByPage {
            capturePreviewForTab(tab)
            showBars()
            newTabAnimation {
                self.loadUrlInNewTab(url, inheritedAttribution: attribution)
                self.currentTab?.openedByPage = true
                self.currentTab?.openingTab = tab
            }
            tabSwitcherButton?.animateUpdate {
                self.tabSwitcherButton?.tabCount += 1
            }
            omniBarTabSwitcherButton?.animateUpdate {
                self.omniBarTabSwitcherButton?.tabCount += 1
            }
        } else {
            loadUrlInNewTab(url, inheritedAttribution: attribution)
            self.currentTab?.adClickExternalOpenDetector.invalidateForUserInitiated()
            self.currentTab?.openingTab = tab
        }

    }

    func tab(_ tab: TabViewController, didRequestReopenClosedTabAt url: URL) {
        self.tab(tab, didRequestNewTabForUrl: url, openedByPage: true, inheritingAttribution: nil)
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
            tab.tabModel.daxEasterEggLogoURL = logoURL
            if self.currentTab == tab {
                let finalLogoURL = self.logoURLForCurrentPage(tab: tab)
                self.viewCoordinator.omniBar.setDaxEasterEggLogoURL(finalLogoURL)
                self.updateBrowsingMenuHeaderDataSource()
            }
        }
    }

    private func logoURLForCurrentPage(tab: TabViewController) -> String? {
        guard let url = tab.url, url.isDuckDuckGoSearch else { return nil }
        guard featureFlagger.isFeatureOn(.daxEasterEggLogos) else { return nil }
        if featureFlagger.isFeatureOn(.daxEasterEggPermanentLogo) {
            return daxEasterEggLogoStore.logoURL ?? tab.tabModel.daxEasterEggLogoURL
        }
        return tab.tabModel.daxEasterEggLogoURL
    }

    func tabDidRequestReportBrokenSite(tab: TabViewController) {
        segueToReportBrokenSite()
    }

    func tab(_ tab: TabViewController, didRequestToggleReportWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        segueToReportBrokenSite(entryPoint: .toggleReport(completionHandler: completionHandler))
    }

    func tabDidRequestAIChat(tab: TabViewController) {
        fireAIChatUsagePixelAndSetFeatureUsed(tab.link == nil ? .browsingMenuAIChatNewTabPage : .browsingMenuAIChatWebPage)
        if DevicePlatform.isIpad {
            newTab(allowingKeyboard: false)
        }
        openAIChat()
    }

    func tabDidRequestAIChatHistory(tab: TabViewController, source: AIChatHistorySource) {
        openAIChatHistory(source: source)
    }

    func openAIChatHistory(source: AIChatHistorySource = .browserMenu) {
        // The native chat history sheet is an iPhone-only experience; entrypoints are hidden on iPad,
        // and this guard ensures the sheet can never be presented there.
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        // The disk-backed storage handler also conforms to `DuckAiNativeChatsObserving`
        // (forwarding to its GRDB `ValueObservation` backing). When storage failed to
        // configure at launch the cast yields `nil`, and the reader surfaces a
        // `.storageUnavailable` failure so the screen shows an error rather than a
        // misleading empty list.
        let reader = ChatHistoryReader(observer: duckAiNativeStorageHandler as? DuckAiNativeChatsObserving)
        // Snapshot the UTI model catalog for export header attribution. `uniquingKeysWith`
        // rather than `uniqueKeysWithValues:` — the model list is server-supplied so we
        // can't guarantee unique ids and the latter crashes on duplicates.
        let modelDisplays = Dictionary(
            (unifiedToggleInputCoordinator?.models ?? []).map { ($0.id, $0.toModelDisplay()) },
            uniquingKeysWith: { first, _ in first }
        )
        let downloader = ChatHistoryDownloader(
            storageHandler: duckAiNativeStorageHandler,
            modelDisplays: modelDisplays
        )
        let pinner: ChatPinning? = duckAiNativeStorageHandler.map { storage in
            ChatPinner(storageHandler: storage, syncCleaner: aiChatSyncCleaner)
        }
        let viewModel = AIChatHistoryViewModel(
            reader: reader,
            featureFlagger: featureFlagger,
            fireExecutor: fireExecutor,
            downloader: downloader,
            pinner: pinner,
            source: source
        )
        viewModel.delegate = self
        let content = AIChatHistoryViewController(viewModel: viewModel, fireButtonAnimator: fireButtonAnimator)
        let navigationController = UINavigationController(rootViewController: content)
        navigationController.modalPresentationStyle = .automatic
        present(navigationController, animated: true)
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
             source: AutofillSettingsSource, extensionPromotionManager: AutofillExtensionPromotionManaging? = nil) {
        launchAutofillLogins(with: currentTab?.url, currentTabUid: tab.tabModel.uid, source: source, selectedAccount: account, extensionPromotionManager: extensionPromotionManager)
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

    func tabDidRequestSettingsToVPN(_ tab: TabViewController) {
        segueToVPN(source: .browserMenu)
    }

    func tabDidRequestSettingsToAIChat(_ tab: TabViewController) {
        segueToSettingsAIChat()
    }

    func tabDidRequestSettingsToSync(_ tab: TabViewController) {
        segueToSettingsSync()
    }

    func tabContentProcessDidTerminate(tab: TabViewController) {
        findInPageView?.done()
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
        if #available(iOS 16.0, *), featureFlagger.isFeatureOn(.systemFindInPage) {
            dismissSystemFindNavigator(for: tab)
            return
        }

        if tab === currentTab {
            findInPageView?.done()
        } else {
            tab.findInPage?.done()
            tab.findInPage = nil
        }
    }
    
    func tabDidRequestFireButtonPulse(tab: TabViewController) {
        showFireButtonPulse()
    }

    func tabDidRequestDeleteContextualChat(tab: TabViewController, chatID: String) {
        let cleaner = HistoryCleaner(featureFlagger: featureFlagger,
                                     privacyConfig: privacyConfigurationManager,
                                     nativeStorageHandler: duckAiNativeStorageHandler,
                                     featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger))
        Task { @MainActor in
            await cleaner.deleteAIChat(chatID: chatID)
        }
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
        guard currentTab === tab,
              !adBlockingAvailability.shouldShowAnimation(for: privacyInfo.url)
        else { return }
        viewCoordinator.omniBar?.startTrackersAnimation(privacyInfo, forDaxDialog: !isCollapsing)
    }

    func tabDidRequestPresentingYouTubeAdBlockAnimation(tab: TabViewController) {
        guard currentTab === tab else { return }
        viewCoordinator.omniBar?.showYouTubeAdBlockNotification()
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
        viewCoordinator.navigationBarContainer.alpha = 1
        allowContentUnderflow = false

        let previousTab = tabManager.current()
        if let tab = tabManager.select(tab, dismissCurrent: false)  {
            transitionTo(tab: tab, from: previousTab)
        }
    }

    func tabCheckIfItsBeingCurrentlyPresented(_ tab: TabViewController) -> Bool {
        return currentTab === tab
    }

    func tab(_ tab: TabViewController, didRequestLoadURL url: URL) {
        loadUrlRespectingAIBoundary(url, fromExternalLink: true)
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

    func tabSwitcher(_ tabSwitcher: TabSwitcherViewController, didFinishWithSelectedTab tab: Tab?) {
        defer {
            showMenuHighlighterIfNeeded()
            applyWidth()
        }
        let previousTab = currentTab
        
        guard tab !== previousTab?.tabModel else {
            if daxDialogsManager.shouldShowFireButtonPulse {
                showFireButtonPulse()
            }
            themeColorManager.updateThemeColor()
            return
        }
        
        if let tab {
            tabManager.select(tab, dismissCurrent: false)
        }

        guard let newTab = tabManager.current(createIfNeeded: true) else {
            assertionFailure("Couldn't create new tab")
            return
        }
        transitionTo(tab: newTab, from: previousTab)
    }

    private func animateLogoAppearance() {
        newTabPageViewController?.view.transform = CGAffineTransform().scaledBy(x: 0.5, y: 0.5)
        newTabPageViewController?.view.alpha = 0.0
        UIView.animate(withDuration: 0.2, delay: 0.1, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.newTabPageViewController?.view.transform = .identity
            self.newTabPageViewController?.view.alpha = 1.0
        }
    }

    private func deferNTPAppearance() {
        newTabPageViewController?.view.alpha = 0.0
        UIView.animate(withDuration: 0.2, delay: 0.2, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.newTabPageViewController?.view.alpha = 1.0
        }
    }

    func tabSwitcherDidRequestNewTab(tabSwitcher: TabSwitcherViewController) {
        tabSwitcherNewTabWithAnimation()
    }

    func tabSwitcherDidRequestNewFireTab(tabSwitcher: TabSwitcherViewController, source: FireModeSwitchSource) {
        tabManager.setBrowsingMode(.fire, source: source)
        tabSwitcherNewTabWithAnimation()
    }

    func tabSwitcherDidRequestNewNormalTab(tabSwitcher: TabSwitcherViewController) {
        tabManager.setBrowsingMode(.normal, source: .tabSwitcherLongPress)
        tabSwitcherNewTabWithAnimation()
    }

    func tabSwitcher(_ tabSwitcher: TabSwitcherViewController, editBookmarkForUrl url: URL) {
        guard let bookmark = self.menuBookmarksViewModel.bookmark(for: url) else { return }
        tabSwitcher.dismiss(animated: true) {
            self.segueToEditBookmark(bookmark)
        }
    }
    
    func tabSwitcherDidBulkCloseTabs(tabSwitcher: TabSwitcherViewController) {
        tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        updateCurrentTab()
    }

    func tabSwitcher(_ tabSwitcher: TabSwitcherViewController, willCloseTabs tabs: [Tab]) {
        for tab in tabs {
            reportDuckAITabClosedIfNeeded(tab)
        }

        if #available(iOS 18.4, *) {
            for tab in tabs {
                if let tabController = tabManager.controller(for: tab) {
                    webExtensionEventsCoordinator?.didCloseTab(tabController)
                }
            }
        }
    }

    func closeTab(_ tab: Tab,
                  behavior: TabClosingBehavior = .onlyClose,
                  clearTabHistory: Bool = true) {
        
        func replaceTabWith(newTab: Tab) {
            tabManager.replace(tab: tab, withNewTab: newTab, clearTabHistory: clearTabHistory)
            tabManager.select(newTab, dismissCurrent: false)
            showBars() // In case the browser chrome bars are hidden when calling this method
        }
        if #available(iOS 18.4, *) {
            if let closingTabController = tabManager.controller(for: tab) {
                webExtensionEventsCoordinator?.didCloseTab(closingTabController)
            }
        }

        reportDuckAITabClosedIfNeeded(tab)

        hideSuggestionTray()
        hideNotificationBarIfBrokenSitePromptShown()
        themeColorManager.updateThemeColor()

        switch behavior {
        case .createEmptyTabAtSamePosition:
            let newTab = Tab(fireTab: tabManager.currentTabsModel.shouldCreateFireTabs)
            replaceTabWith(newTab: newTab)
        case .createOrReuseEmptyTab:
            tabManager.remove(tab: tab, clearTabHistory: clearTabHistory)
            if let existing = tabManager.firstHomeTab() {
                tabManager.select(existing, dismissCurrent: false)
            } else {
                tabManager.addHomeTab()
            }
            showBars() // In case the browser chrome bars are hidden when calling this method
        case .createNewChat:
            let aiChatLink = Link(title: nil, url: aiChatSettings.aiChatURL)
            let newTab = Tab(link: aiChatLink, fireTab: tabManager.currentTabsModel.shouldCreateFireTabs)
            replaceTabWith(newTab: newTab)
        case .onlyClose:
            tabManager.remove(tab: tab, clearTabHistory: clearTabHistory)
        }

        updateCurrentTab()
        refreshTabBar()
    }

    func tabSwitcherDidRequestForgetAll(tabSwitcher: TabSwitcherViewController, fireRequest: FireRequest) {
        self.forgetAllWithAnimation(request: fireRequest) {
            tabSwitcher.dismissIfPossible(animated: false)
        }
    }

    func tabSwitcherDidRequestCloseAll(tabSwitcher: TabSwitcherViewController) {
        for tab in tabSwitcher.tabsModel.tabs {
            reportDuckAITabClosedIfNeeded(tab)
        }

        Task {
            let request: FireRequest
            switch tabSwitcher.selectedBrowsingMode {
            case .fire:
                request = FireRequest(options: .all, trigger: .manualFire, scope: .fireMode, source: .tabSwitcher)
            case .normal:
                request = FireRequest(options: .tabs, trigger: .manualFire, scope: .normalMode, source: .tabSwitcher)
            }
            await fireExecutor.burn(request: request, applicationState: .unknown)
            tabSwitcher.dismissIfPossible()
        }
    }

    func tabSwitcherDidReorderTabs(tabSwitcher: TabSwitcherViewController) {
        tabsBarController?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
        swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel, scrollToSelected: true)
    }

    func tabSwitcherDidRequestAIChat(tabSwitcher: TabSwitcherViewController) {
        fireAIChatUsagePixelAndSetFeatureUsed(.openAIChatFromTabManager)
        self.aiChatViewControllerManager.openAIChat(on: tabSwitcher)
    }
    
    func tabSwitcherDidRequestAIChatTab(tabSwitcher: TabSwitcherViewController) {
        fireAIChatUsagePixelAndSetFeatureUsed(.openAIChatFromTabManager)
        newTab(allowingKeyboard: false)
        openAIChat()
    }

    private func tabSwitcherNewTabWithAnimation() {
        newTab()
        if newTabPageViewController?.isShowingLogo == true, !aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            animateLogoAppearance()
        } else if aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            deferNTPAppearance()
        }
        themeColorManager.updateThemeColor()
    }
    
}

extension MainViewController: BookmarksDelegate {
    func bookmarksDidSelect(url: URL) {

        dismissOmniBar()
        if url.isBookmarklet() {
            executeBookmarklet(url)
        } else {
            loadUrlRespectingAIBoundary(url)
        }
    }
}

extension MainViewController: TabSwitcherButtonDelegate {

    func launchNewTabWithCurrentMode(_ button: TabSwitcherButton) {
        newTabShortcutAction()
    }
    
    func launchNewNormalTab(_ button: any TabSwitcherButton) {
        newNormalTabLongPressMenuAction()
    }

    func launchNewFireTab(_ button: TabSwitcherButton) {
        newFireTabLongPressMenuAction()
    }

    func showTabSwitcher(_ button: TabSwitcherButton) {
        requestTabSwitcher()
    }

    /// Single entry point for every tab-switcher request — toolbar button, all five pill
    /// surfaces (regular NTP, UTI Search/Duck.ai, legacy editing-state Search/Duck.ai).
    /// Fires the same counted/daily pixels and runs `performCancel()` which handles all
    /// possible modal states (legacy editing state via `endEditing()`, UTI via
    /// `deactivateToOmnibar()`), so every entry produces identical behaviour.
    /// Not `private` because the UTI extension in `MainViewController+UnifiedToggleInput`
    /// calls it from another file.
    func requestTabSwitcher() {
        Pixel.fire(pixel: .tabBarTabSwitcherOpened,
                   withAdditionalParameters: [PixelParameters.browsingMode: tabManager.currentBrowsingMode.pixelParamValue])
        var openedDailyParams = TabSwitcherOpenDailyPixel().parameters(with: tabManager.allTabsModel.tabs)
        openedDailyParams[PixelParameters.browsingMode] = tabManager.currentBrowsingMode.pixelParamValue
        DailyPixel.fireDaily(.tabSwitcherOpenedDaily, withAdditionalParameters: openedDailyParams)

        performActionIfAITab { DailyPixel.fireDailyAndCount(pixel: .aiChatTabSwitcherOpened) }

        // Snap the UTI away so its collapse doesn't overlap the tab switcher segue (non-animated dismiss restores resting layout synchronously).
        performCancel(animated: false)
        showTabSwitcher()
    }

    func showTabSwitcher() {
        if !tabManager.currentTabsModel.allowsEmpty
            && tabManager.current(createIfNeeded: true) == nil {
            fatalError("Unable to get current tab")
        }
        if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
            ntpAfterIdleInstrumentation.tabSwitcherSelectedFromNTP(afterIdle: tab.openedAfterIdle)
        }
        postIdleSessionInstrumentation.sessionEnded(reason: .tabSwitcherSelected)
        // Don't clear `openedAfterIdle` on switcher open — the after-idle session
        // ends on actual tab transition (see `transitionTo`), not on peeking.
        hideNotificationBarIfBrokenSitePromptShown()
        updatePreviewForCurrentTab {
            ViewHighlighter.hideAll()
            Task { @MainActor in
                await self.segueToTabSwitcher()
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MainViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UnifiedInputSwipeTabsPanGestureRecognizer {
            return shouldBeginUnifiedInputSwipeTabsPan(pan)
        }
        return true
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

// MARK: - Fire Button Logic

extension MainViewController {

    func clearNavigationStack() {
        dismissOmniBar()

        if let presented = presentedViewController {
            presented.dismiss(animated: false) { [weak self] in
                self?.clearNavigationStack()
            }
        }
    }

    func forgetAllWithAnimation(request: FireRequest,
                                transitionCompletion: (() -> Void)? = nil,
                                showNextDaxDialog: Bool = false) {
        let spid = Instruments.shared.startTimedEvent(.clearingData)
        let tabsCount = tabsCount(for: request.scope)

        firePixels(for: request)
        productSurfaceTelemetry.dataClearingUsed()
        
        fireExecutor.prepare(for: request)
        
        fireButtonAnimator.animate {
            await self.fireExecutor.burn(request: request, applicationState: .unknown)
            Instruments.shared.endTimedEvent(for: spid)
            self.daxDialogsManager.resumeRegularFlow()
        } onTransitionCompleted: { [weak self] in
            self?.presentPostBurnMessage(tabsCount: tabsCount, request: request)
            transitionCompletion?()
        } completion: {
            self.subscriptionDataReporter.saveFireCount()

            // Ideally this should happen once data clearing has finished AND the animation is finished
            if showNextDaxDialog {
                self.newTabPageViewController?.showNextDaxDialog()
            } else if request.options.contains(.tabs) && KeyboardSettings().onNewTab && !self.isEscapeHatchBurn(request) {
                // Escape-hatch burns restore focus in `restoreFocusModeAfterBurnIfNeeded`.
                let showKeyboardAfterFireButton = DispatchWorkItem {
                    // A burned Duck.ai chat reopens as a new chat that owns its input; don't focus search over it.
                    guard self.currentTab?.isAITab != true else { return }
                    if !self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
                        self.enterSearch()
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: showKeyboardAfterFireButton)
                self.showKeyboardAfterFireButton = showKeyboardAfterFireButton
            }

            // The NTP's viewDidAppear may have fired during the fire animation and already called
            // nextHomeScreenMessageNew(), setting currentHomeSpec (e.g. to .final for the "High five!"
            // dialog). Calling clearedBrowserData() unconditionally would reset currentHomeSpec to nil,
            // making isShowingContextualOnboardingDialog return false and allowing the subscription promo
            // to appear on top of the pending dialog when the user backgrounds and foregrounds.
            //
            // When a home spec is already set, the browsing context was already cleared inside
            // nextHomeScreenMessageNew(); skip the redundant call here.
            if !self.daxDialogsManager.isShowingContextualOnboardingDialog {
                self.daxDialogsManager.clearedBrowserData()
            }
        }
    }
    
    private func tabsCount(for scope: FireRequest.Scope) -> Int {
        switch scope {
        case .tab:
            return 1
        case .fireMode:
            return tabManager.tabsModel(for: .fire).count
        case .normalMode:
            return tabManager.tabsModel(for: .normal).count
        case .all:
            return tabManager.allTabsModel.count
        }
    }
    
    @MainActor
    private func presentPostBurnMessage(tabsCount: Int, request: FireRequest) {
        let message = UserText.scopedFireConfirmationTabsDeletedToast(tabCount: tabsCount)
        // Escape-hatch-hide burns restore the keyboard, which would cover a bottom toast — show it at the top.
        let location: ActionMessageView.PresentationLocation = isEscapeHatchBurn(request)
            ? .top
            : .withBottomBar(andAddressBarBottom: self.appSettings.currentAddressBarPosition.isBottom)
        ActionMessageView.present(message: message, presentationLocation: location)
    }
    
    private func refreshUIAfterClear() {
        if tabManager.currentTabsModel.tabs.isEmpty && tabManager.currentTabsModel.allowsEmpty {
            showTabSwitcher()
            tabSwitcherController?.updateUIForSelectionMode()
            return
        }
        showBars()
        attachHomeScreen()
        refreshTabBar()

        if !autoClearInProgress {
            // We don't need to refresh tabs if autoclear is in progress as nothing has happened yet
            swipeTabsCoordinator?.refresh(tabsModel: tabManager.currentTabsModel)
        }
    }
    
    func showFireButtonPulse() {
        // During Duck.ai fire onboarding we control pulse lifecycle explicitly.
        // Avoid Dax pulse bookkeeping here, because it can immediately clear highlights.
        if duckAIFireOnboardingFlow.state != .active {
            daxDialogsManager.fireButtonPulseStarted()
        }
        guard let window = view.window else { return }
        
        let fireButtonView: UIView?
        if let utiCoordinator = unifiedToggleInputCoordinator, !utiCoordinator.aiTabFireButton.isHidden {
            // In the AI-tab collapsed pose the fire button is the flanking pill button on the
            // left of the UTI input bar — use it instead of the (hidden) legacy toolbar.
            fireButtonView = utiCoordinator.aiTabFireButton
        } else if viewCoordinator.toolbar.isHidden { // This is the iPad case
            fireButtonView = tabsBarController?.fireButton
        } else {
            fireButtonView = findFireButton()
        }
        guard let view = fireButtonView else { return }
        
        if !ViewHighlighter.highlightedViews.contains(where: { $0.view == view }) {
            ViewHighlighter.hideAll()
            ViewHighlighter.showIn(window, focussedOnView: view)
        }
    }

    func findFireButton() -> UIView? {
        let state = mobileCustomization.state

        if state.currentToolbarButton == .fire {
            if isInMinimalChromeLayout {
                return viewCoordinator.omniBar.barView.fireButton
            }
            return viewCoordinator.toolbarFireButton
        } else if state.currentAddressBarButton == .fire {
            return viewCoordinator.omniBar.barView.customizableButton
        } else {
            if isInMinimalChromeLayout {
                return viewCoordinator.omniBar.barView.menuButton
            }
            return viewCoordinator.menuToolbarButton
        }

    }

    private func showPrivacyDashboardButtonPulse() {
        viewCoordinator.omniBar.showOrScheduleOnboardingPrivacyIconAnimation()
    }

    private func dismissPrivacyDashboardButtonPulse() {
        daxDialogsManager.setPrivacyButtonPulseSeen()
        viewCoordinator.omniBar.dismissOnboardingPrivacyIconAnimation()
    }
}

// MARK: - Data Clearing Overlay

extension MainViewController {

    /// Shows a transparent overlay that captures user interactions during data clearing.
    ///
    /// The overlay detects when users attempt to interact with the UI before clearing completes,
    /// which may indicate perceived slowness or incomplete clearing. A pixel is fired on the first
    /// interaction, then the overlay is removed to allow normal user interaction.
    ///
    /// Only shown for manual fire triggers (user-initiated), not auto-clear operations.
    private func showBurningOverlay() {
        guard let window = view.window else { return }

        hideBurningOverlay()

        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: self, action: #selector(burningOverlayTapped))
        tap.cancelsTouchesInView = false
        overlay.addGestureRecognizer(tap)

        window.addSubview(overlay)
        window.bringSubviewToFront(overlay)
        burningOverlayView = overlay
    }

    /// Removes the burning overlay if it exists.
    private func hideBurningOverlay() {
        burningOverlayView?.removeFromSuperview()
        burningOverlayView = nil
    }

    /// Removes the overlay when user taps during data clearing, and fires a pixel if possible.
    ///
    /// This indicates the user attempted to interact before clearing completed,
    /// which is a secondary SLI metric for measuring perceived clearing performance.
    /// The overlay is always removed to respect user action, even if pixel firing fails.
    @objc private func burningOverlayTapped() {
        if let fireExecutor = fireExecutor as? FireExecutor {
            fireExecutor.pixelsReporter.fireUserActionBeforeCompletionPixel()
        }
        hideBurningOverlay()
    }
}

extension MainViewController: TabManagerFireModeDelegate {

    func tabManagerDidCloseLastFireTab() {
        // # Prevent re-entrant calls
        // Burn Fire Tab, triggered from the Escape Hatch, effectively triggers a Burn sequence.
        // When burning the last Tab, we'd end up here. Purpose of this safety check is to prevent re-entrant Burn sequences
        if fireExecutor.burnInProgress {
            return
        }

        DailyPixel.fireDailyAndCount(pixel: .fireModeLastTabClosedBurn)
        Task {
            let request = FireRequest(options: [.data, .aiChats],
                                      trigger: .fireModeAutoClear,
                                      scope: .fireMode,
                                      source: .browsing)
            await fireExecutor.burn(request: request, applicationState: .unknown)
        }
    }

    func tabManagerDidChangeBrowsingMode(_ mode: BrowsingMode) {
        Task {
            await aiChatViewControllerManager.killSessionAndResetTimer()
        }
    }
}

extension MainViewController: FireExecutorDelegate {
    
    func willStartBurning(fireRequest: FireRequest) {
        switch fireRequest.trigger {
        case .manualFire:
            showBurningOverlay()
        case .autoClearOnLaunch:
            autoClearInProgress = true
        case .autoClearOnForeground:
            autoClearInProgress = true
            clearNavigationStack()
        case .fireModeAutoClear:
            break
        }
    }
    
    private func firePixels(for request: FireRequest) {
        let tabType = tabManager.viewModelForCurrentTab()?.tab.isAITab == true ? "ai" : "web"
        let browsingMode = tabManager.currentBrowsingMode.pixelParamValue
        let params: [String: String] = [
            PixelParameters.source: request.source.rawValue,
            PixelParameters.tabType: tabType,
            PixelParameters.browsingMode: browsingMode
        ]

        switch request.scope {
        case .all:
            Pixel.fire(pixel: .forgetAllExecuted, withAdditionalParameters: params)
            DailyPixel.fire(pixel: .forgetAllExecutedDaily, withAdditionalParameters: params)
        case .tab:
            DailyPixel.fireDailyAndCount(pixel: .singleTabBurnExecuted, withAdditionalParameters: params)
        case .fireMode:
            DailyPixel.fireDailyAndCount(pixel: .fireModeBurnExecuted, withAdditionalParameters: params)
        case .normalMode:
            DailyPixel.fireDailyAndCount(pixel: .normalModeBurnExecuted, withAdditionalParameters: params)
        }
    }
    
    func willStartBurningTabs(fireRequest: FireRequest) {
        omniBar.endEditing()
        findInPageView?.done()
        reportDuckAIFireButtonClearedTabsIfNeeded(fireRequest)

        if #available(iOS 18.4, *) {
            let tabs: [Tab]
            switch fireRequest.scope {
            case .all:
                tabs = tabManager.allTabsModel.tabs
            case .fireMode:
                tabs = tabManager.tabsModel(for: .fire).tabs
            case .normalMode:
                tabs = tabManager.tabsModel(for: .normal).tabs
            case .tab:
                tabs = []
            }
            for tab in tabs {
                if let tabController = tabManager.controller(for: tab) {
                    webExtensionEventsCoordinator?.didCloseTab(tabController)
                }
            }
        }
    }
    
    func didFinishBurningTabs(fireRequest: FireRequest) {
        guard fireRequest.trigger == .manualFire else { return }
                
        switch fireRequest.scope {
        case .all, .fireMode, .normalMode:
            refreshUIAfterClear()
        case .tab:
            // For single tab, the UI was already updated in closeTab() → updateCurrentTab()
            return
        }
    }
    
    func willStartBurningData(fireRequest: FireRequest) {
        self.clearInProgress = true
        if #available(iOS 18.4, *) {
            webExtensionEventsCoordinator?.extensionsWillUnload()
            webExtensionManager?.unloadAllExtensions()
        }
    }
    
    func didFinishBurningData(fireRequest: FireRequest) {
        self.clearInProgress = false
        self.postClear?()
        self.postClear = nil
    }

    func willStartBurningAIHistory(fireRequest: FireRequest) {
        // No operation
    }
    
    func didFinishBurningAIHistory(fireRequest: FireRequest) {
        switch fireRequest.scope {
        case .all, .fireMode, .normalMode:
            Task {
                await aiChatViewControllerManager.killSessionAndResetTimer()
            }
        case .tab:
            // No custom logic for tab scope
            return
        }
    }
    
    func didFinishBurning(fireRequest: FireRequest) {
        // Trigger sync if needed after data and aichats finish
        // because data could potentially delete a contextual chat that needs syncing
        if syncService.authState != .inactive {
            syncService.scheduler.requestSyncImmediately()
        }
        if #available(iOS 18.4, *) {
            Task { @MainActor [weak self] in
                guard let self, let coordinator = self.webExtensionLifecycleCoordinator else { return }
                if self.featureFlagger.isFeatureOn(.webExtensionLightweightReload) {
                    await coordinator.reload().value
                } else {
                    await coordinator.load().value
                }
                self.webExtensionEventsCoordinator?.registerExistingTabsAndWindow()
            }
        }
        switch fireRequest.trigger {
        case .manualFire:
            hideBurningOverlay()
            return
        case .autoClearOnLaunch:
            autoClearInProgress = false
            autoClearShouldRefreshUIAfterClear = true
        case .autoClearOnForeground:
            autoClearInProgress = false
            if autoClearShouldRefreshUIAfterClear {
                refreshUIAfterClear()
            }
            autoClearShouldRefreshUIAfterClear = true
        case .fireModeAutoClear:
            break
        }
    }
}

extension MainViewController {
    var isFloatingUIEnabled: Bool {
        floatingUIManager.isFloatingUIEnabled
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if !themeColorManager.updateThemeColor() {
            updateStatusBarBackgroundColor()
        }
        updateFindInPage()

        revealChromeIfPinned()
    }

    func refreshStatusBarBackgroundAfterAIChrome() {
        if !themeColorManager.updateThemeColor() {
            updateStatusBarBackgroundColor()
        }
    }

    private func updateStatusBarBackgroundColor() {
        let theme = ThemeManager.shared.currentTheme
        let color: UIColor

        if appSettings.currentAddressBarPosition == .bottom {
            color = theme.backgroundColor
        } else {
            if AppWidthObserver.shared.isPad && traitCollection.horizontalSizeClass == .regular {
                color = theme.tabsBarBackgroundColor
            } else {
                color = theme.omniBarBackgroundColor
            }
        }

        viewCoordinator.setStandardStatusBackgroundColor(color)
    }

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme

        updateStatusBarBackgroundColor()

        setNeedsStatusBarAppearanceUpdate()

        view.backgroundColor = theme.mainViewBackgroundColor

        viewCoordinator.navigationBarContainer.backgroundColor = theme.barBackgroundColor
        viewCoordinator.navigationBarContainer.tintColor = theme.barTintColor

        viewCoordinator.toolbar.tintColor = UIColor(singleUseColor: .toolbarButton)

        viewCoordinator.toolbarTabSwitcherView.tintColor = UIColor(singleUseColor: .toolbarButton)

        viewCoordinator.logoText.tintColor = theme.ddgTextTintColor

        // This may move when the feature is further developed.
        applyFloatingUIIfNeeded()
    }

    private func applyFloatingUIIfNeeded() {
        guard floatingUIManager.isFloatingUIEnabled else { return }
        viewCoordinator.setFloatingUIEnabled(floatingUIManager.isFloatingUIEnabled)
        FloatingUIChromeStyler().decorateMainViewIfNeeded(manager: floatingUIManager, coordinator: viewCoordinator)
        viewCoordinator.updateToolbarLayoutForAddressBarPosition(appSettings.currentAddressBarPosition)
        reconcileAIChromeForCurrentTab()
    }

}

extension MainViewController: OnboardingDelegate {

    func didStartOnboardingInterlude(_ interlude: OnboardingIntroStep.Interlude) {
        linearOnboardingContext?.activeInterlude = interlude
        UIView.animate(withDuration: 0.2) {
            self.linearOnboardingContext?.onboardingViewController?.view.alpha = 0
        } completion: { _ in
            self.linearOnboardingContext?.onboardingViewController?.dismiss(animated: false)
        }
    }

    func finishOnboardingInterlude(completion: @escaping () -> Void) {
        linearOnboardingContext?.activeInterlude = nil
        guard let viewModel = linearOnboardingContext?.onboardingViewModel else { return }
        viewModel.resumeOnboardingFromInterlude()
        let controller = OnboardingIntroFactory.makeController(
            viewModel: viewModel,
            delegate: self
        )
        linearOnboardingContext?.onboardingViewController = controller
        linearOnboardingContext?.onboardingViewModel = viewModel
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        present(controller, animated: true, completion: completion)
    }

    func onboardingCompleted(controller: UIViewController) {
        markOnboardingSeen()

        // Enrol new users into the Search Token experiment. Must run here (post-onboarding) so we only
        // enrol new users; enrollIfEligible function additionally excludes returning users (reinstallers).
        searchTokenExperiment.enrollIfEligible()

        appSettings.applyAdBlockingRolloutDuckPlayerDefaultsIfNeeded(rolloutActive: adBlockingAvailability.areAdBlockingDefaultsActive)


        // Now that linear onboarding has finished, run the unified-toggle-input
        // setup that was deferred at viewDidLoad.
        setUpUnifiedToggleInputIfNeeded()
        if duckAIFireOnboardingFlow.state == .awaitingFirstResponse {
            onboardingCompletedWithDuckAITransition(controller: controller)
            return
        }

        // For Duck.ai tailored flow, the NTP completion dialog hosts inside `OmniBarEditingStateViewController`,
        // which only installs when `shouldUseExperimentalEditingState` is true — itself gated on
        // `aiChatSettings.isAIChatSearchInputUserSettingsEnabled`.
        //
        // IMPORTANT: Contrary to the Duck.ai fire onboarding on the default flow we do not call `ensureDuckAiCompletionDialogPresentationPrerequisites()`.
        // The full prerequisite also calls `daxDialogsManager.disableContextualDaxDialogs()`, which would set
        // `isEnabled = false` before the tailored completion dialog is presented, breaking the subscription
        // chain inside the dialog's `onDismiss` (`nextHomeScreenMessageNew()` would return `nil` from its
        // `guard isEnabled` and the EOJ → subscription transition would silently drop).
        if onboardingManager.currentOnboardingFlow == .duckAI && !aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
            aiChatSettings.enableAIChatSearchInputUserSettings(enable: true)
        }

        controller.modalTransitionStyle = .crossDissolve
        // The Duck.ai tailored flow's NTP completion dialog presents `OmniBarEditingStateViewController`.
        // Wait for the OnboardingIntroViewController to be dismissed before presenting `OmniBarEditingStateViewController`
        // otherwise `OmniBarEditingStateViewController` will not be presented while the onboarding is mid-dismissal.
        controller.dismiss(animated: true) { [weak self] in
            self?.newTabPageViewController?.onboardingCompleted()
        }
    }

    func markOnboardingSeen() {
        linearOnboardingContext = nil
        isStartupOnboardingPending = false
        tutorialSettings.hasSeenOnboarding = true
        clearDuckAIOnboardingResumeStepIfNeeded()
    }

    func needsToShowOnboardingIntro() -> Bool {
        isStartupOnboardingPending || !tutorialSettings.hasSeenOnboarding
    }

}


extension MainViewController: OnboardingNavigationDelegate {
    func navigateFromOnboarding(to url: URL) {
        // If the chat-path visit-site dialog had hidden the bars, animate them back in before
        // navigating. loadUrl → prepareTabForRequest immediately sets navigationBarContainer.alpha = 1,
        // which would cancel any in-progress UIView animation; delaying the load by one animation
        // duration lets the bars slide in visibly before the navigation begins.
        if daxDialogsManager.chatPathPhase == .visitSite {
            setBarsHidden(false, animated: true, customAnimationDuration: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + ChromeAnimationConstants.duration) { [weak self] in
                self?.loadUrl(url, fromExternalLink: true)
            }
        } else {
            loadUrl(url, fromExternalLink: true)
        }
    }

    func searchFromOnboarding(for query: String) {
        // Suppress the Search onboarding dialog when the user came from the duck.ai query selection step.
        daxDialogsManager.setTryAnonymousSearchMessageSeen()
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
            if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
                ntpAfterIdleInstrumentation.barUsedFromNTP(afterIdle: tab.openedAfterIdle)
            }
            postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
            loadQuery(query)

        case .AIChat:
            Pixel.fire(pixel: .voiceSearchAIChatDone)
            if let coordinator = unifiedToggleInputCoordinator, coordinator.isAITabState, coordinator.hasBoundUserScript {
                if let tab = tabManager.currentTabsModel.currentTab, tab.link == nil {
                    ntpAfterIdleInstrumentation.barUsedFromNTP(afterIdle: tab.openedAfterIdle)
                }
                postIdleSessionInstrumentation.sessionEnded(reason: .barUsed)
                coordinator.submitVoicePrompt(query)
            } else {
                performCancel()
                openAIChat(query, autoSend: true)
            }
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
        viewCoordinator.toolbarBackButton.menu = backMenu

        let forwardMenu = historyMenu(with: currentTab.webView.backForwardList.forwardList)
        viewCoordinator.omniBar.barView.forwardButton.menu = forwardMenu
        viewCoordinator.toolbarForwardButton.menu = forwardMenu
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

// MARK: - OmniBarFocuser

extension MainViewController: OmniBarFocuser {
    func beginSearch() {
        omniBar.beginEditing(animated: true)
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

    func aiChatViewControllerManagerDidReceiveOpenSyncSettingsRequest(_ manager: AIChatViewControllerManager) {
        segueToSettingsSync()
    }

    func aiChatViewControllerManagerDidReceivePromptSubmission(_ manager: AIChatViewControllerManager) {
        reportDuckAIFrontendSubmissionAcknowledged()
    }
}

// MARK: - AIChatContentHandlingDelegate
extension MainViewController: AIChatContentHandlingDelegate {

    func aiChatContentHandlerDidReceiveOpenSettingsRequest(_ handler:
                                                           AIChatContentHandling) {
        if let controller = tabSwitcherController {
            controller.dismiss(animated: true) {
                self.segueToSettingsAIChat()
            }
        } else {
            segueToSettingsAIChat()
        }
    }

    func aiChatContentHandlerDidReceiveOpenSyncSettingsRequest(_ handler: any AIChatContentHandling) {
        segueToSettingsSync()
    }

    func aiChatContentHandlerDidReceiveCloseChatRequest(_ handler:
                                                        AIChatContentHandling) {
        closeCurrentTab()
    }

    func aiChatContentHandlerDidReceivePromptSubmission(_ handler: AIChatContentHandling) {
        reportDuckAIFrontendSubmissionAcknowledged()
    }

    func aiChatContentHandlerDidReceiveNewChatCreated(_ handler: AIChatContentHandling) {
        DispatchQueue.main.async { [weak self] in
            self?.unifiedToggleInputCoordinator?.startNewChat()
            self?.unifiedToggleInputCoordinator?.showExpanded(inputMode: .aiChat)
        }
    }

    func aiChatContentHandler(_ handler: AIChatContentHandling, didRequestToOpen url: URL) {
        loadUrlInNewTab(url, inheritedAttribution: nil)
        currentTab?.adClickExternalOpenDetector.invalidateForUserInitiated()
    }

    private func closeCurrentTab() {
        guard let tab = currentTab?.tabModel else { return }
        closeTab(tab)
    }

}

/// This extension allows delegating from the RMF action button when the action type is 'navigation'.  It shadows existing functions.
extension MainViewController: MessageNavigationDelegate {

    func segueToSettingsAIChat(openedFromSERPSettingsButton: Bool, presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            segueToSettingsAIChat(openedFromSERPSettingsButton: openedFromSERPSettingsButton)
        case .withinCurrentContext:
            assertionFailure("Not implemented yet.")
        }
    }
    
    func segueToSettings(presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            segueToSettings()
        case .withinCurrentContext:
            assertionFailure("Not implemented yet.")
        }
    }

    func segueToSettingsAppearance(presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            segueToAppearanceSettings()
        case .withinCurrentContext:
            assertionFailure("Not implemented yet.")
        }
    }

    func segueToSettingsGeneral(presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            segueToGeneralSettings()
        case .withinCurrentContext:
            assertionFailure("Not implemented yet.")
        }
    }

    func segueToFeedback(presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            segueToFeedback()
        case .withinCurrentContext:
            assertionFailure("Not implemented yet.")
        }
    }
    
    func segueToSettingsSync(with source: String?, pairingInfo: PairingInfo?, presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            segueToSettingsSync(with: source, pairingInfo: pairingInfo)
        case .withinCurrentContext:
            assertionFailure("Not implemented yet.")
        }
    }
    
    func segueToImportPasswords(presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            assertionFailure("Not implemented yet.")
        case .withinCurrentContext:
            let destinationViewController: UIViewController
            switch DataImportEntryPointHandler().destination(for: .whatsNew) {
            case .legacy(let importScreen):
                destinationViewController = makeDataImportViewController(source: importScreen)
            case .hub:
                destinationViewController = DataImportHubViewController(syncService: syncService,
                                                                         keyValueStore: keyValueStore,
                                                                         bookmarksDatabase: bookmarksDatabase,
                                                                         favoritesDisplayMode: appSettings.favoritesDisplayMode,
                                                                         entryPoint: .whatsNew)
                Pixel.fire(pixel: .importHubEntryTapped, withAdditionalParameters: DataImportViewModel.ImportScreen.whatsNew.importHubEntryPointParameters)
            }
            guard let viewController = topMostPresentedViewController() else {
                assertionFailure("No ViewController presented.")
                return
            }
            viewController.show(destinationViewController, sender: nil)
        }
    }

    func segueToPIR(presentationStyle: PresentationContext.Style) {
        switch presentationStyle {
        case .dismissModalsAndPresentFromRoot:
            segueToPIRWithSubscriptionCheck()
        case .withinCurrentContext:
            assertionFailure("Not implemented yet.")
        }
    }

}

extension MainViewController: MainViewEditingStateTransitioning {

    private var isDaxLogoVisible: Bool {
        newTabPageViewController?.isShowingLogo == true
    }

    var logoView: UIView? {
        if newTabPageViewController?.isShowingLogo == true {
            // Treat NTP view as logo view, but only if it's visible.
            // This prevents favorites from flickering during transition.
            return newTabPageViewController?.view
        } else {
            return nil
        }
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

// MARK: AutoClear Action Delegate
extension MainViewController: SettingsAutoClearActionDelegate {
    func performDataClearing(for request: FireRequest) {
        forgetAllWithAnimation(request: request)
    }
}

// MARK: Customization support
extension MainViewController: MobileCustomization.Delegate {

    func canEditBookmark() -> Bool {
        guard let url = currentTab?.url else { return false }
        return menuBookmarksViewModel.bookmark(for: url) != nil
    }
    
    func canEditFavorite() -> Bool {
        guard let url = currentTab?.url, let bookmark = menuBookmarksViewModel.bookmark(for: url) else { return false }
        return bookmark.isFavorite(on: .mobile)
    }

}

extension MainViewController {

    private func subscribeToCustomizationSettingsEvents() {
        NotificationCenter.default.publisher(for: AppUserDefaults.Notifications.customizationSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCustomizationState()
            }
            .store(in: &settingsCancellables)
    }

    private func subscribeToDaxEasterEggLogoChanges() {
        NotificationCenter.default.publisher(for: .logoDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOmniBar()
            }
            .store(in: &settingsCancellables)
    }

    func applyCustomizationState() {
        applyCustomizationForToolbar(mobileCustomization.state)
        applyCustomizationForAddressBar(mobileCustomization.state)
    }

    func applyCustomizationForAddressBar(_ state: MobileCustomization.State) {
        omniBar.refreshCustomizableButton()
        if state.isEnabled {
            omniBar.barView.customizableButton.menu = UIMenu(children: [
                UIAction(title: "Customize", image: DesignSystemImages.Glyphs.Size16.options) { [weak self] _ in
                    self?.segueToCustomizeAddressBarSettings()
                }
            ])
        } else {
            omniBar.barView.customizableButton.menu = nil
        }
    }

    @objc private func performCustomizationActionForToolbar() {
        // On NTP the default is fire button
        if isNewTabPageVisible {
            self.onFirePressed()
            return
        }

        // Will be removed when feature flag is removed
        guard mobileCustomization.state.isEnabled else {
            self.onFirePressed()
            return
        }

        let button = mobileCustomization.state.currentToolbarButton
        switch button {
        case .home:
            guard let tab = self.currentTab?.tabModel else { return }
            self.closeTab(tab, behavior: .createEmptyTabAtSamePosition)

        case .newTab:
            self.newTab()

        case .fire:
            self.onFirePressed()

        case .bookmarks:
            self.segueToBookmarks()

        case .passwords:
            self.launchAutofillLogins(with: currentTab?.url, currentTabUid: currentTab?.tabModel.uid, source: .customizedToolbarButton, selectedAccount: nil)

        case .vpn:
            self.presentNetworkProtectionStatusSettingsModal(entryPoint: .toolbar)

        case .share:
            self.shareCurrentURLFromToolbar()

        case .downloads:
            self.segueToDownloads()

        case .duckAIVoice:
            Pixel.fire(pixel: .voiceEntryPointTapped, withAdditionalParameters: [PixelParameters.source: VoiceEntryPointSource.toolbar.rawValue])
            self.openAIChatInVoiceMode()

        default:
            assertionFailure("Unexpected case \(button)")
        }
    }

    /// Applies customization if enabled, ensures default otherwise.
    private func applyCustomizationForToolbar(_ state: MobileCustomization.State) {
        let toolbarFireButton = viewCoordinator.toolbarFireButton
        customizeFireButton(toolbarFireButton, state: state)

        if let omniBarFireButton = viewCoordinator.omniBar.barView.fireButton as? BrowserChromeButton {
            customizeFireButton(omniBarFireButton, state: state)
        }
    }

    private func customizeFireButton(_ button: BrowserChromeButton, state: MobileCustomization.State) {
        if !isNewTabPageVisible && state.isEnabled {
            button.setImage(state.currentToolbarButton.largeIcon)
            button.menu = UIMenu(children: [
                UIAction(title: "Customize", image: DesignSystemImages.Glyphs.Size16.options) { [weak self] _ in
                    self?.segueToCustomizeToolbarSettings()
                }
            ])
        } else {
            button.setImage(DesignSystemImages.Glyphs.Size24.fireSolid)
            button.menu = nil
        }
    }

    private func handleCustomizableAddressBarButtonPressed() {
        let button = mobileCustomization.state.currentAddressBarButton
        switch button {
        case .share:
            shareCurrentURLFromAddressBar()

        case .addEditBookmark:
            addOrEditBookmarkForCurrentTab()
            omniBar.refreshCustomizableButton()

        case .addEditFavorite:
            addOrEditFavoriteForCurrentTab()
            omniBar.refreshCustomizableButton()

        case .fire:
            onFirePressed()

        case .vpn:
            presentNetworkProtectionStatusSettingsModal(entryPoint: .addressBar)

        case .zoom:
            showTextZoomEditorIfPossible()

        case .duckAIVoice:
            Pixel.fire(pixel: .voiceEntryPointTapped, withAdditionalParameters: [PixelParameters.source: VoiceEntryPointSource.addressBar.rawValue])
            openAIChatInVoiceMode()

        default:
            assertionFailure("Unexpected case: \(button)")
            return
        }

    }

    private func addOrEditBookmarkForCurrentTab() {
        guard let webView = currentTab?.webView,
              let url = webView.url else {
            assertionFailure("Expecting current tab with web view")
            return
        }
        if let bookmark = menuBookmarksViewModel.bookmark(for: url) {
            segueToEditBookmark(bookmark)
        } else {
            currentTab?.saveAsBookmark(favorite: false, viewModel: menuBookmarksViewModel)
        }
    }

    private func addOrEditFavoriteForCurrentTab() {
        guard let webView = currentTab?.webView,
              let url = webView.url else {
            assertionFailure("Expecting current tab with web view")
            return
        }

        let bookmark = menuBookmarksViewModel.bookmark(for: url)
        if bookmark?.isFavorite(on: .mobile) == true {
            segueToEditBookmark(bookmark!)
        } else {
            currentTab?.saveAsBookmark(favorite: true, viewModel: menuBookmarksViewModel)
        }
    }

    private func showTextZoomEditorIfPossible() {
        guard let currentTab, let webView = currentTab.webView else {
            assertionFailure("Expecting current tab with web view")
            return
        }
        Task { @MainActor in
            let textZoomCoordinator = textZoomCoordinatorProvider.coordinator(for: currentTab.tabModel.textZoomContext)
            await textZoomCoordinator.showTextZoomEditor(inController: self, forWebView: webView)
        }
    }

}

// MARK: - AIChatHistoryManagerDelegate

extension MainViewController: AIChatHistoryManagerDelegate {

    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChatURL url: URL) {
        onChatHistorySelected(url: url)
    }

    func aiChatHistoryManagerDidSelectViewAllChats(_ manager: AIChatHistoryManager) {
        openAIChatHistory(source: .addressBar)
    }
}

// MARK: - Duck.ai Wide Event

extension MainViewController {

    fileprivate var currentDuckAIWideEventFlowScope: DuckAIWideEventFlowScope? {
        currentTab.map { .tab($0.tabModel.uid) }
    }

    fileprivate func reportDuckAITabClosedIfNeeded(_ tab: Tab) {
        guard let closingURL = tabManager.controller(for: tab)?.webView.url, closingURL.isDuckAIURL else { return }
        duckAIWideEventInstrumentation.tabClosedDuringGeneration(tabID: tab.uid)
    }

    fileprivate func reportDuckAIFireButtonClearedTabsIfNeeded(_ fireRequest: FireRequest) {
        guard fireRequest.trigger == .manualFire else { return }

        for tab in tabsClearedByFireButton(fireRequest.scope) {
            duckAIWideEventInstrumentation.fireButtonClearedTabDuringGeneration(tabID: tab.uid)
        }
    }

    private func tabsClearedByFireButton(_ scope: FireRequest.Scope) -> [Tab] {
        switch scope {
        case .all:
            return tabManager.allTabsModel.tabs
        case .fireMode:
            return tabManager.tabsModel(for: .fire).tabs
        case .normalMode:
            return tabManager.tabsModel(for: .normal).tabs
        case .tab(let viewModel):
            return [viewModel.tab]
        }
    }

    fileprivate func reportDuckAIFrontendSubmissionAcknowledged() {
        guard let scope = currentDuckAIWideEventFlowScope else { return }
        duckAIWideEventInstrumentation.frontendSubmissionAcknowledged(scope: scope)
    }
}
