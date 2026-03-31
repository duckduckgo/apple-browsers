//
//  AppDelegate.swift
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
import AppKitExtensions
import AppUpdaterShared
import AttributedMetric
import AutoconsentStats
import BWManagementShared
import Bookmarks
import BrokenSitePrompt
import BrowserServicesKit
import Cocoa
import Combine
import Common
import Configuration
import ContentScopeScripts
import CoreData
import Crashes
import CrashReportingShared
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import DDGSync
import FeatureFlags
import Freemium
import History
import HistoryView
import Lottie
import MetricKit
import Network
import Networking
import NetworkProtectionIPC
import NewTabPage
import os.log
import Persistence
import PixelExperimentKit
import PixelKit
import PrivacyConfig
import PrivacyStats
import RemoteMessaging
import ScreenTimeDataCleaner
import ServiceManagement
import Subscription
import SyncDataProviders
import UserNotifications
import Utilities
import VPN
import VPNAppState
import WebExtensions
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {

#if DEBUG
    let disableCVDisplayLinkLogs: Void = {
        // Disable CVDisplayLink logs
        CFPreferencesSetValue("cv_note" as CFString,
                              0 as CFPropertyList,
                              "com.apple.corevideo" as CFString,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesSynchronize("com.apple.corevideo" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }()
#endif

    let urlEventHandler = URLEventHandler()

    private let keyStore: EncryptionKeyStoring
    let fileStore: FileStore

    private let crashReporting: any CrashReporting

    let watchdog: Watchdog
    private let watchdogSleepMonitor: WatchdogSleepMonitor
    private var hangReportingFeatureMonitor: HangReportingFeatureMonitor?

    let keyValueStore: ThrowingKeyValueStoring

    let faviconManager: FaviconManager
    let pinnedTabsManager = PinnedTabsManager()
    let pinningManager = LocalPinningManager()
    let tabDragAndDropManager: TabDragAndDropManager
    let pinnedTabsManagerProvider: PinnedTabsManagerProvider
    private(set) var stateRestorationManager: AppStateRestorationManager!
    private var grammarFeaturesManager = GrammarFeaturesManager()
    let internalUserDecider: InternalUserDecider
    private var isInternalUserSharingCancellable: AnyCancellable?
    let featureFlagger: FeatureFlagger
    let visualizeFireSettingsDecider: VisualizeFireSettingsDecider
    let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    let contentScopePreferences: ContentScopePreferences
    let featureFlagOverridesPublishingHandler = FeatureFlagOverridesPublishingHandler<FeatureFlag>()
    private var appIconChanger: AppIconChanger!
    private var autoClearHandler: AutoClearHandler!
    private(set) var autofillPixelReporter: AutofillPixelReporter?
    private var passwordsStatusBarMenu: PasswordsStatusBarMenu?
    private var passwordsMenuBarCancellable: AnyCancellable?

    private(set) var syncDataProviders: SyncDataProvidersSource?
    private(set) var syncService: DDGSyncing?
    private(set) var syncErrorHandler = SyncErrorHandler()
    private(set) var aiChatSyncCleaner: AIChatSyncCleaning?
    private var isSyncInProgressCancellable: AnyCancellable?
    private var syncFeatureFlagsCancellable: AnyCancellable?
    private var screenLockedCancellable: AnyCancellable?
    private var emailCancellables = Set<AnyCancellable>()
    private(set) var promoService: PromoService?
    var privacyDashboardWindow: NSWindow?

    let tabCrashAggregator = TabCrashAggregator()
    let windowControllersManager: WindowControllersManager
    let tabSuspensionService: TabSuspensionService
    let subscriptionNavigationCoordinator: SubscriptionNavigationCoordinator

    let appearancePreferences: AppearancePreferences
    let dataClearingPreferences: DataClearingPreferences
    let startupPreferences: StartupPreferences
    let defaultBrowserPreferences: DefaultBrowserPreferences
    let downloadsPreferences: DownloadsPreferences
    let searchPreferences: SearchPreferences
    let tabsPreferences: TabsPreferences
    let webTrackingProtectionPreferences: WebTrackingProtectionPreferences
    let cookiePopupProtectionPreferences: CookiePopupProtectionPreferences
    let aboutPreferences: AboutPreferences
    let dockPreferences: DockPreferencesModel
    let accessibilityPreferences: AccessibilityPreferences
    let duckPlayer: DuckPlayer

    let database: Database!
    let bookmarkDatabase: BookmarkDatabase
    let bookmarkManager: LocalBookmarkManager
    let bookmarkDragDropManager: BookmarkDragDropManager
    let historyCoordinator: HistoryCoordinator
    let fireproofDomains: FireproofDomains
    let bitwardenManager: BWManagement?
    let passwordManagerCoordinator: PasswordManagerCoordinator
    let webCacheManager: WebCacheManager
    let tld = TLD()
    let privacyFeatures: AnyPrivacyFeatures
    let brokenSitePromptLimiter: BrokenSitePromptLimiter
    let fireCoordinator: FireCoordinator
    let permissionManager: PermissionManager
    let notificationService: UserNotificationAuthorizationServicing
    let recentlyClosedCoordinator: RecentlyClosedCoordinating
    let downloadManager: FileDownloadManagerProtocol
    let downloadListCoordinator: DownloadListCoordinator
    let autoconsentManagement = AutoconsentManagement()
    let attributedMetricManager: AttributedMetricManager

    @MainActor
    private(set) lazy var autoconsentStatsPopoverCoordinator: AutoconsentStatsPopoverCoordinator = AutoconsentStatsPopoverCoordinator(
        autoconsentStats: autoconsentStats,
        keyValueStore: keyValueStore,
        windowControllersManager: windowControllersManager,
        cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
        appearancePreferences: appearancePreferences,
        onboardingStateUpdater: onboardingContextualDialogsManager
    )

    private var updateProgressCancellable: AnyCancellable?

    @MainActor
    private(set) lazy var newTabPageCoordinator: NewTabPageCoordinator = NewTabPageCoordinator(
        appearancePreferences: appearancePreferences,
        customizationModel: newTabPageCustomizationModel,
        bookmarkManager: bookmarkManager,
        faviconManager: faviconManager,
        duckPlayerHistoryEntryTitleProvider: duckPlayer,
        activeRemoteMessageModel: activeRemoteMessageModel,
        historyCoordinator: historyCoordinator,
        contentBlocking: privacyFeatures.contentBlocking,
        fireproofDomains: fireproofDomains,
        privacyStats: privacyStats,
        autoconsentStats: autoconsentStats,
        cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
        freemiumDBPPromotionViewCoordinator: freemiumDBPPromotionViewCoordinator,
        tld: tld,
        fireCoordinator: fireCoordinator,
        keyValueStore: keyValueStore,
        visualizeFireAnimationDecider: visualizeFireSettingsDecider,
        featureFlagger: featureFlagger,
        windowControllersManager: windowControllersManager,
        tabsPreferences: tabsPreferences,
        newTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProvider(aiChatMenuConfiguration: aiChatMenuConfiguration),
        winBackOfferPromotionViewCoordinator: winBackOfferPromotionViewCoordinator,
        subscriptionCardVisibilityManager: homePageSetUpDependencies.subscriptionCardVisibilityManager,
        protectionsReportModel: newTabPageProtectionsReportModel,
        homePageContinueSetUpModelPersistor: homePageSetUpDependencies.continueSetUpModelPersistor,
        nextStepsCardsPersistor: homePageSetUpDependencies.nextStepsCardsPersistor,
        subscriptionCardPersistor: homePageSetUpDependencies.subscriptionCardPersistor,
        duckPlayerPreferences: DuckPlayerPreferencesUserDefaultsPersistor(),
        syncService: syncService,
        pinningManager: pinningManager,
        promoService: promoService,
        dockCustomization: dockCustomization
    )

    private(set) lazy var aiChatTabOpener: AIChatTabOpening = AIChatTabOpener(
        promptHandler: AIChatPromptHandler.shared,
        aiChatTabManaging: windowControllersManager
    )
    let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    let aiChatSessionStore: AIChatSessionStoring
    let aiChatPreferences: AIChatPreferences

    let privacyStats: PrivacyStatsCollecting
    let autoconsentStats: AutoconsentStatsCollecting
    private var autoconsentEventCoordinator: AutoconsentEventCoordinator?
    let activeRemoteMessageModel: ActiveRemoteMessageModel
    let newTabPageCustomizationModel: NewTabPageCustomizationModel
    private(set) lazy var newTabPageProtectionsReportModel: NewTabPageProtectionsReportModel = NewTabPageProtectionsReportModel(
        privacyStats: privacyStats,
        autoconsentStats: autoconsentStats,
        keyValueStore: keyValueStore,
        burnAnimationSettingChanges: visualizeFireSettingsDecider.shouldShowFireAnimationPublisher,
        showBurnAnimation: visualizeFireSettingsDecider.shouldShowFireAnimation,
        isAutoconsentEnabled: { self.cookiePopupProtectionPreferences.isAutoconsentEnabled },
        getLegacyIsViewExpandedSetting: settingsMigrator.isViewExpanded,
        getLegacyActiveFeedSetting: settingsMigrator.activeFeed
    )
    private let settingsMigrator = NewTabPageProtectionsReportSettingsMigrator(legacyKeyValueStore: UserDefaultsWrapper<Any>.sharedDefaults)

    let remoteMessagingClient: RemoteMessagingClient!
    let onboardingContextualDialogsManager: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater
    let defaultBrowserAndDockPromptService: DefaultBrowserAndDockPromptService
    private lazy var webNotificationClickHandler = WebNotificationClickHandler(tabFinder: windowControllersManager)
    let userChurnScheduler: UserChurnBackgroundActivityScheduler
    lazy var vpnUpsellPopoverPresenter = DefaultVPNUpsellPopoverPresenter(
        subscriptionManager: subscriptionManager,
        featureFlagger: featureFlagger,
        vpnUpsellVisibilityManager: vpnUpsellVisibilityManager
    )
    let themeManager: ThemeManager

    let wideEvent: WideEventManaging
    let freeTrialConversionService: FreeTrialConversionInstrumentationService
    let subscriptionManager: any SubscriptionManager
    static let deadTokenRecoverer = DeadTokenRecoverer()

    public let subscriptionUIHandler: SubscriptionUIHandling

    private(set) lazy var sessionRestorePromptCoordinator = SessionRestorePromptCoordinator(pixelFiring: PixelKit.shared)

    // MARK: - Automation Server
    private var automationServer: AutomationServer?
    private let launchOptionsHandler = LaunchOptionsHandler()

    // MARK: - Freemium DBP
    public let freemiumDBPFeature: FreemiumDBPFeature
    public let freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator
    private var freemiumDBPScanResultPolling: FreemiumDBPScanResultPolling?

    var configurationStore = ConfigurationStore()
    var configurationManager: ConfigurationManager
    var configurationURLProvider: CustomConfigurationURLProviding

    // MARK: - VPN

    public let vpnSettings = VPNSettings(defaults: .netP)

    private lazy var vpnAppEventsHandler = VPNAppEventsHandler(
        featureGatekeeper: DefaultVPNFeatureGatekeeper(vpnUninstaller: VPNUninstaller(pinningManager: pinningManager), subscriptionManager: subscriptionManager),
        featureFlagOverridesPublisher: featureFlagOverridesPublishingHandler.flagDidChangePublisher,
        loginItemsManager: LoginItemsManager(),
        defaults: .netP)
    private var vpnSubscriptionEventHandler: VPNSubscriptionEventsHandler?

    private var vpnXPCClient: VPNControllerXPCClient {
        VPNControllerXPCClient.shared
    }

    lazy var vpnUpsellVisibilityManager: VPNUpsellVisibilityManager = {
        return VPNUpsellVisibilityManager(
            isNewUser: AppDelegate.isNewUser,
            subscriptionManager: subscriptionManager,
            defaultBrowserProvider: SystemDefaultBrowserProvider(),
            contextualOnboardingPublisher: onboardingContextualDialogsManager.isContextualOnboardingCompletedPublisher.eraseToAnyPublisher(),
            persistor: vpnUpsellUserDefaultsPersistor,
            timerDuration: vpnUpsellUserDefaultsPersistor.expectedUpsellTimeInterval
        )
    }()

    lazy var vpnUpsellUserDefaultsPersistor: VPNUpsellUserDefaultsPersistor = {
        return VPNUpsellUserDefaultsPersistor(keyValueStore: keyValueStore)
    }()

    // MARK: - Home Page Continue Set Up Model

    // Note: Using UserDefaultsWrapper as legacy store here because the pre-existed code used it.
    lazy var homePageSetUpDependencies: HomePageSetUpDependencies = {
        return HomePageSetUpDependencies(subscriptionManager: subscriptionManager,
                                         keyValueStore: keyValueStore,
                                         legacyKeyValueStore: UserDefaultsWrapper<Any>.sharedDefaults)
    }()

    // MARK: - DBP

    private lazy var dataBrokerProtectionSubscriptionEventHandler: DataBrokerProtectionSubscriptionEventHandler = {
        let authManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(subscriptionManager: subscriptionManager)
        return DataBrokerProtectionSubscriptionEventHandler(featureDisabler: DataBrokerProtectionFeatureDisabler(),
                                                            authenticationManager: authManager,
                                                            pixelHandler: DataBrokerProtectionMacOSPixelsHandler())
    }()

    // MARK: - Win-back Campaign
    lazy var winBackOfferVisibilityManager: WinBackOfferVisibilityManaging = {
        let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging
        let buildType = StandardApplicationBuildType()
        if buildType.isDebugBuild || buildType.isReviewBuild {
            let winBackOfferDebugStore = WinBackOfferDebugStore(keyValueStore: keyValueStore)
            let dateProvider: () -> Date = { winBackOfferDebugStore.simulatedTodayDate }
            winBackOfferVisibilityManager = WinBackOfferVisibilityManager(subscriptionManager: subscriptionManager,
                                                                        winbackOfferStore: winbackOfferStore,
                                                                        winbackOfferFeatureFlagProvider: winbackOfferFeatureFlagProvider,
                                                                        dateProvider: dateProvider,
                                                                        timeBeforeOfferAvailability: .seconds(5))
        } else {
            winBackOfferVisibilityManager = WinBackOfferVisibilityManager(subscriptionManager: subscriptionManager,
                                                                          winbackOfferStore: winbackOfferStore,
                                                                          winbackOfferFeatureFlagProvider: winbackOfferFeatureFlagProvider)
        }
        return winBackOfferVisibilityManager
    }()

    lazy var winbackOfferStore: WinbackOfferStoring = {
        return WinbackOfferStore(keyValueStore: keyValueStore)
    }()

    private lazy var winbackOfferFeatureFlagProvider: WinBackOfferFeatureFlagProvider = {
        return WinBackOfferFeatureFlagger(featureFlagger: featureFlagger)
    }()

    lazy var winBackOfferPromptPresenter: WinBackOfferPromptPresenting = {
        return WinBackOfferPromptPresenter(visibilityManager: winBackOfferVisibilityManager,
                                          subscriptionManager: subscriptionManager)
    }()

    lazy var winBackOfferPromotionViewCoordinator: WinBackOfferPromotionViewCoordinator = {
        return WinBackOfferPromotionViewCoordinator(winBackOfferVisibilityManager: winBackOfferVisibilityManager)
    }()

    let blackFridayCampaignProvider: BlackFridayCampaignProviding

    // MARK: - Wide Event Service

    private lazy var wideEventService: WideEventService = {
        return WideEventService(
            wideEvent: wideEvent,
            subscriptionManager: subscriptionManager
        )
    }()

    private(set) var webExtensionManager: WebExtensionManaging?
    private(set) var webExtensionAvailability: WebExtensionAvailabilityProviding
    private let webExtensionManagerHolder = WebExtensionManagerHolder()
    private var webExtensionFeatureFlagHandler: AnyObject?
    private var isSyncingEmbeddedExtensions = false
    private(set) var darkReaderFeatureSettings: DarkReaderFeatureSettings?
    private var darkReaderCancellables = Set<AnyCancellable>()

    /// Holder class that allows `WebExtensionAvailability` to be created before `super.init()`,
    /// while still providing access to `webExtensionManager` which is set on `self` after `super.init()`.
    private final class WebExtensionManagerHolder {
        weak var appDelegate: AppDelegate?
        var manager: WebExtensionManaging? {
            appDelegate?.webExtensionManager
        }
    }

    private var didFinishLaunching = false

    var updateController: UpdateController?
    let dockCustomization: DockCustomization

    @UserDefaultsWrapper(key: .firstLaunchDate, defaultValue: Date.monthAgo)
    static var firstLaunchDate: Date

    @UserDefaultsWrapper
    private var didCrashDuringCrashHandlersSetUp: Bool

    static var isNewUser: Bool {
        return firstLaunchDate >= Date.weekAgo
    }

    static var twoDaysPassedSinceFirstLaunch: Bool {
        return firstLaunchDate.daysSinceNow() >= 2
    }

    let memoryUsageMonitor: MemoryUsageMonitor
    /// Optional `var` because its `syncServiceProvider` closure captures `self`,
    /// which is unavailable before `super.init()`. Initialized immediately after `super.init()`.
    var memoryPressureReporter: MemoryPressureReporter?
    let memoryUsageThresholdReporter: MemoryUsageThresholdReporter
    /// Optional `var` because its `syncServiceProvider` closure captures `self`,
    /// which is unavailable before `super.init()`. Initialized immediately after `super.init()`.
    var memoryUsageIntervalReporter: MemoryUsageIntervalReporter?

    let startupProfiler: StartupProfiler
    private var startupMetricsReporter: PerformanceMetricsReporter?

    let displaysTabsAnimations: Bool

    /// The date this app instance was launched, used for computing uptime in memory pixels.
    private let appLaunchDate = Date()

    @MainActor
    // swiftlint:disable cyclomatic_complexity
    init(dockCustomization: DockCustomization) {
        let startupProfiler = StartupProfiler()
        let profilerToken = startupProfiler.startMeasuring(.appDelegateInit)
        defer {
            profilerToken.stop()
        }

        self.startupProfiler = startupProfiler
        self.dockCustomization = dockCustomization

        if [.unitTests, .integrationTests].contains(AppVersion.runType) {
            keyStore = (NSClassFromString("MockEncryptionKeyStore") as? EncryptionKeyStoring.Type)!.init()
        } else {
            keyStore = EncryptionKeyStore()
        }

        // will not add crash handlers and will fire pixel on applicationDidFinishLaunching if didCrashDuringCrashHandlersSetUp == true
        let didCrashDuringCrashHandlersSetUp = UserDefaultsWrapper(key: .didCrashDuringCrashHandlersSetUp, defaultValue: false)
        _didCrashDuringCrashHandlersSetUp = didCrashDuringCrashHandlersSetUp
        if case .normal = AppVersion.runType,
           !didCrashDuringCrashHandlersSetUp.wrappedValue {

            didCrashDuringCrashHandlersSetUp.wrappedValue = true
            CrashLogMessageExtractor.setUp(swapCxaThrow: false)
            didCrashDuringCrashHandlersSetUp.wrappedValue = false
        }

        if AppVersion.runType.requiresEnvironment {
            Self.configurePixelKit()
        }

        do {
            keyValueStore = try KeyValueFileStore(location: URL.sandboxApplicationSupportURL, name: "AppKeyValueStore")
            // perform a dummy read to ensure that KVS is accessible
            _ = try keyValueStore.object(forKey: AppearancePreferencesUserDefaultsPersistor.Key.newTabPageIsProtectionsReportVisible.rawValue)
        } catch {
            PixelKit.fire(DebugEvent(GeneralPixel.keyValueFileStoreInitError, error: error))
            Thread.sleep(forTimeInterval: 1)
            fatalError("Could not prepare key value store: \(error.localizedDescription)")
        }

        do {
            let encryptionKey = AppVersion.runType.requiresEnvironment ? try keyStore.readKey() : nil
            fileStore = EncryptedFileStore(encryptionKey: encryptionKey)
        } catch {
            Logger.general.error("App Encryption Key could not be read: \(error.localizedDescription)")
            fileStore = EncryptedFileStore()
        }

        bookmarkDatabase = BookmarkDatabase()

        let internalUserDeciderStore = InternalUserDeciderStore(fileStore: fileStore)
        internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)

        if AppVersion.runType.requiresEnvironment {
            let commonDatabase = Database()
            database = commonDatabase

            database.db.loadStore { _, error in
                guard let error = error else { return }

                switch error {
                case CoreDataDatabase.Error.containerLocationCouldNotBePrepared(let underlyingError):
                    PixelKit.fire(DebugEvent(GeneralPixel.dbContainerInitializationError(error: underlyingError)))
                default:
                    PixelKit.fire(DebugEvent(GeneralPixel.dbInitializationError(error: error)))
                }

                // Give Pixel a chance to be sent, but not too long
                Thread.sleep(forTimeInterval: 1)
                fatalError("Could not load DB: \(error.localizedDescription)")
            }

            do {
                let formFactorFavMigration = BookmarkFormFactorFavoritesMigration()
                let favoritesOrder = try formFactorFavMigration.getFavoritesOrderFromPreV4Model(dbContainerLocation: BookmarkDatabase.defaultDBLocation,
                                                                                                dbFileURL: BookmarkDatabase.defaultDBFileURL)
                bookmarkDatabase.preFormFactorSpecificFavoritesFolderOrder = favoritesOrder
            } catch {
                PixelKit.fire(DebugEvent(GeneralPixel.bookmarksCouldNotLoadDatabase(error: error)))
                Thread.sleep(forTimeInterval: 1)
                fatalError("Could not create Bookmarks database stack: \(error.localizedDescription)")
            }

            bookmarkDatabase.db.loadStore { context, error in
                guard let context = context else {
                    PixelKit.fire(DebugEvent(GeneralPixel.bookmarksCouldNotLoadDatabase(error: error)))
                    Thread.sleep(forTimeInterval: 1)
                    fatalError("Could not create Bookmarks database stack: \(error?.localizedDescription ?? "err")")
                }

                let legacyDB = commonDatabase.db.makeContext(concurrencyType: .privateQueueConcurrencyType)
                legacyDB.performAndWait {
                    LegacyBookmarksStoreMigration.setupAndMigrate(from: legacyDB, to: context)
                }
            }
        } else {
            database = nil
        }

        let privacyConfigurationManager: PrivacyConfigurationManager
        let buildType = StandardApplicationBuildType()

        // When TEST_PRIVACY_CONFIG_PATH is set, skip cached config to use the test config from embedded data provider
        let useTestConfig = (buildType.isDebugBuild || buildType.isReviewBuild) && ProcessInfo.processInfo.environment[AppPrivacyConfigurationDataProvider.EnvironmentKeys.testPrivacyConfigPath] != nil
        let fetchedEtag: String? = useTestConfig ? nil : configurationStore.loadEtag(for: .privacyConfiguration)
        let fetchedData: Data? = useTestConfig ? nil : configurationStore.loadData(for: .privacyConfiguration)

        if useTestConfig {
            Logger.general.log("[DDG-TEST-CONFIG] Skipping cached privacy config to use TEST_PRIVACY_CONFIG_PATH")
        }

        if AppVersion.runType.requiresEnvironment {
            privacyConfigurationManager = PrivacyConfigurationManager(
                fetchedETag: fetchedEtag,
                fetchedData: fetchedData,
                embeddedDataProvider: AppPrivacyConfigurationDataProvider(),
                localProtection: LocalUnprotectedDomains(database: database.db),
                errorReporting: AppContentBlocking.debugEvents,
                internalUserDecider: internalUserDecider
            )
        } else {
            privacyConfigurationManager = PrivacyConfigurationManager(
                fetchedETag: fetchedEtag,
                fetchedData: fetchedData,
                embeddedDataProvider: AppPrivacyConfigurationDataProvider(),
                localProtection: LocalUnprotectedDomains(database: nil),
                errorReporting: AppContentBlocking.debugEvents,
                internalUserDecider: internalUserDecider
            )
        }

        let featureFlagger: FeatureFlagger
        if [.unitTests, .integrationTests, .xcPreviews].contains(AppVersion.runType)  {
            featureFlagger = MockFeatureFlagger()
            self.contentScopeExperimentsManager = MockContentScopeExperimentManager()

        } else {
            let featureFlagOverrides = FeatureFlagLocalOverrides(
                keyValueStore: UserDefaults.appConfiguration,
                actionHandler: featureFlagOverridesPublishingHandler
            )
            let defaultFeatureFlagger = DefaultFeatureFlagger(
                internalUserDecider: internalUserDecider,
                privacyConfigManager: privacyConfigurationManager,
                localOverrides: featureFlagOverrides,
                allowOverrides: { [internalUserDecider, isRunningUITests=(AppVersion.runType == .uiTests)] in
                    internalUserDecider.isInternalUser || isRunningUITests
                },
                experimentManager: ExperimentCohortsManager(
                    store: ExperimentsDataStore(),
                    fireCohortAssigned: PixelKit.fireExperimentEnrollmentPixel(subfeatureID:experiment:)
                ),
                for: FeatureFlag.self
            )
            featureFlagger = defaultFeatureFlagger
            self.contentScopeExperimentsManager = defaultFeatureFlagger

            featureFlagOverrides.applyUITestsFeatureFlagsIfNeeded()
        }
        self.featureFlagger = featureFlagger

        displaysTabsAnimations = AnimationsAvailabilityDecider(featureFlagger: featureFlagger).displaysTabsAnimations

        webExtensionAvailability = WebExtensionAvailability(
            featureFlagger: featureFlagger,
            webExtensionManagerProvider: { [webExtensionManagerHolder] in
                webExtensionManagerHolder.manager
            }
        )

        wideEvent = WideEvent(
            useMockRequests: buildType.isDebugBuild || buildType.isReviewBuild || buildType.isAlphaBuild,
            featureFlagProvider: WideEventFeatureFlagAdapter(featureFlagger: featureFlagger)
        )

        aiChatSessionStore = AIChatSessionStore(featureFlagger: featureFlagger)
        aiChatMenuConfiguration = AIChatMenuConfiguration(
            storage: DefaultAIChatPreferencesStorage(),
            remoteSettings: AIChatRemoteSettings(
                privacyConfigurationManager: privacyConfigurationManager
            ),
            featureFlagger: featureFlagger
        )

        appearancePreferences = AppearancePreferences(
            keyValueStore: keyValueStore,
            privacyConfigurationManager: privacyConfigurationManager,
            pixelFiring: PixelKit.shared,
            featureFlagger: featureFlagger,
            aiChatMenuConfig: aiChatMenuConfiguration
        )

#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            bookmarkManager = LocalBookmarkManager(
                bookmarkStore: LocalBookmarkStore(
                    bookmarkDatabase: bookmarkDatabase,
                    favoritesDisplayMode: appearancePreferences.favoritesDisplayMode
                ),
                appearancePreferences: appearancePreferences
            )
            historyCoordinator = HistoryCoordinator(
                historyStoring: EncryptedHistoryStore(
                    context: self.database.db.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "History")
                )
            )
        } else {
            bookmarkManager = LocalBookmarkManager(bookmarkStore: BookmarkStoreMock(), appearancePreferences: appearancePreferences)
            historyCoordinator = HistoryCoordinator(historyStoring: MockHistoryStore())
        }
#else
        bookmarkManager = LocalBookmarkManager(
            bookmarkStore: LocalBookmarkStore(
                bookmarkDatabase: bookmarkDatabase,
                favoritesDisplayMode: appearancePreferences.favoritesDisplayMode
            ),
            appearancePreferences: appearancePreferences
        )
        historyCoordinator = HistoryCoordinator(
            historyStoring: EncryptedHistoryStore(
                context: self.database.db.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "History")
            )
        )
#endif
        bookmarkDragDropManager = BookmarkDragDropManager(bookmarkManager: bookmarkManager)

        // MARK: - Subscription configuration

        subscriptionUIHandler = SubscriptionUIHandler(windowControllersManagerProvider: {
            return Application.appDelegate.windowControllersManager
        })

        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)

        // Configuring V2 for migration
        let pixelHandler: SubscriptionPixelHandling = SubscriptionPixelHandler(source: .mainApp, pixelKit: PixelKit.shared)
        let keychainType = KeychainType.dataProtection(.named(subscriptionAppGroup))
        let keychainManager = KeychainManager(attributes: SubscriptionTokenKeychainStorage.defaultAttributes(keychainType: keychainType), pixelHandler: pixelHandler)
        let authService = DefaultOAuthService(baseURL: subscriptionEnvironment.authEnvironment.url,
                                              apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: UserAgent.duckDuckGoUserAgent()))
        let tokenStorage = SubscriptionTokenKeychainStorage(keychainManager: keychainManager, userDefaults: .subs) { accessType, error in
            PixelKit.fire(SubscriptionErrorPixel.subscriptionKeychainAccessError(accessType: accessType,
                                                                                 accessError: error,
                                                                                 source: KeychainErrorSource.browser,
                                                                                 authVersion: KeychainErrorAuthVersion.v2),
                          frequency: .legacyDailyAndCount)
        }

        let authRefreshWideEventMapper = AuthV2TokenRefreshWideEventData.authV2RefreshEventMapping(wideEvent: wideEvent, isFeatureEnabled: {
#if DEBUG
            return true // Allow the refresh event when using staging in debug mode, for easier testing
#else
            return subscriptionEnvironment.serviceEnvironment == .production
#endif
        })
        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            authService: authService,
                                            refreshEventMapping: authRefreshWideEventMapper)
        Logger.general.log("Configuring Subscription")
        var apiServiceForSubscription = APIServiceFactory.makeAPIServiceForSubscription(withUserAgent: UserAgent.duckDuckGoUserAgent())
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: apiServiceForSubscription,
                                                                               baseURL: subscriptionEnvironment.serviceEnvironment.url)
        apiServiceForSubscription.authorizationRefresherCallback = { _ in

            guard let tokenContainer = try? tokenStorage.getTokenContainer() else {
                throw OAuthClientError.internalError("Missing refresh token")
            }

            if tokenContainer.decodedAccessToken.isExpired() {
                Logger.OAuth.debug("Refreshing tokens")
                let tokens = try await authClient.getTokens(policy: .localForceRefresh)
                return tokens.accessToken
            } else {
                Logger.general.debug("Trying to refresh valid token, using the old one")
                return tokenContainer.accessToken
            }
        }
        let subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags> = FeatureFlaggerMapping { feature in
            switch feature {
            case .useSubscriptionUSARegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        subscriptionEnvironment.serviceEnvironment == .staging &&
                        subscriptionUserDefaults.storefrontRegionOverride == .usa)
            case .useSubscriptionROWRegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        subscriptionEnvironment.serviceEnvironment == .staging &&
                        subscriptionUserDefaults.storefrontRegionOverride == .restOfWorld)
            }
        }

        let isInternalUserEnabled = { featureFlagger.internalUserDecider.isInternalUser }
        let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: subscriptionUserDefaults,
                                                                         pixelHandler: pixelHandler)
        let defaultSubscriptionManager: DefaultSubscriptionManager
        if #available(macOS 12.0, *) {
            defaultSubscriptionManager = DefaultSubscriptionManager(storePurchaseManager: DefaultStorePurchaseManager(subscriptionFeatureMappingCache: subscriptionEndpointService,
                                                                                                                      subscriptionFeatureFlagger: subscriptionFeatureFlagger,
                                                                                                                      pendingTransactionHandler: pendingTransactionHandler),
                                                                    oAuthClient: authClient,
                                                                    userDefaults: subscriptionUserDefaults,
                                                                    subscriptionEndpointService: subscriptionEndpointService,
                                                                    subscriptionEnvironment: subscriptionEnvironment,
                                                                    pixelHandler: pixelHandler,
                                                                    isInternalUserEnabled: isInternalUserEnabled)
        } else {
            defaultSubscriptionManager = DefaultSubscriptionManager(oAuthClient: authClient,
                                                                    userDefaults: subscriptionUserDefaults,
                                                                    subscriptionEndpointService: subscriptionEndpointService,
                                                                    subscriptionEnvironment: subscriptionEnvironment,
                                                                    pixelHandler: pixelHandler,
                                                                    isInternalUserEnabled: isInternalUserEnabled)
        }

        // Expired refresh token recovery
        if #available(iOS 15.0, macOS 12.0, *) {
            let restoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: defaultSubscriptionManager,
                                                         storePurchaseManager: defaultSubscriptionManager.storePurchaseManager(),
                                                         pendingTransactionHandler: pendingTransactionHandler)
            defaultSubscriptionManager.tokenRecoveryHandler = {
                try await Self.deadTokenRecoverer.attemptRecoveryFromPastPurchase(purchasePlatform: defaultSubscriptionManager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)
            }
        }

        subscriptionManager = defaultSubscriptionManager
        freeTrialConversionService = DefaultFreeTrialConversionInstrumentationService(
            wideEvent: wideEvent,
            pixelHandler: FreeTrialPixelHandler(),
            subscriptionFetcher: { try? await defaultSubscriptionManager.getSubscription(cachePolicy: .cacheFirst) },
            isFeatureEnabled: { [featureFlagger] in featureFlagger.isFeatureOn(.freeTrialConversionWideEvent) }
        )
        freeTrialConversionService.startObservingSubscriptionChanges()

        pinnedTabsManagerProvider = PinnedTabsManagerProvider(sharedPinnedTabsManager: pinnedTabsManager)

        let windowControllersManager = WindowControllersManager(
            pinnedTabsManagerProvider: pinnedTabsManagerProvider,
            subscriptionFeatureAvailability: DefaultSubscriptionFeatureAvailability(
                privacyConfigurationManager: privacyConfigurationManager,
                purchasePlatform: defaultSubscriptionManager.currentEnvironment.purchasePlatform,
                featureFlagProvider: SubscriptionPageFeatureFlagAdapter(featureFlagger: featureFlagger)
            ),
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            pinningManager: pinningManager
        )
        tabsPreferences = TabsPreferences(
            persistor: TabsPreferencesUserDefaultsPersistor(keyValueStore: UserDefaults.standard),
            windowControllersManager: windowControllersManager
        )
        windowControllersManager.tabsPreferences = tabsPreferences
        self.windowControllersManager = windowControllersManager
        self.tabSuspensionService = TabSuspensionService(windowControllersManager: windowControllersManager, featureFlagger: featureFlagger)

        pinnedTabsManagerProvider.tabsPreferences = tabsPreferences
        pinnedTabsManagerProvider.windowControllersManager = windowControllersManager

        contentScopePreferences = ContentScopePreferences(windowControllersManager: windowControllersManager)
        webTrackingProtectionPreferences = WebTrackingProtectionPreferences(persistor: WebTrackingProtectionPreferencesUserDefaultsPersistor(), windowControllersManager: windowControllersManager)
        cookiePopupProtectionPreferences = CookiePopupProtectionPreferences(persistor: CookiePopupProtectionPreferencesUserDefaultsPersistor(), windowControllersManager: windowControllersManager)
        aiChatPreferences = AIChatPreferences(
            storage: DefaultAIChatPreferencesStorage(),
            aiChatMenuConfiguration: aiChatMenuConfiguration,
            windowControllersManager: windowControllersManager,
            featureFlagger: featureFlagger
        )

        let subscriptionNavigationCoordinator = SubscriptionNavigationCoordinator(
            tabShower: windowControllersManager,
            subscriptionManager: subscriptionManager
        )
        self.subscriptionNavigationCoordinator = subscriptionNavigationCoordinator

        themeManager = ThemeManager(appearancePreferences: appearancePreferences, featureFlagger: featureFlagger, displaysTabsAnimations: displaysTabsAnimations)

#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            fireproofDomains = FireproofDomains(store: FireproofDomainsStore(database: database.db, tableName: "FireproofDomains"), tld: tld)
            faviconManager = FaviconManager(cacheType: .standard(database.db), bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains, privacyConfigurationManager: privacyConfigurationManager)
            permissionManager = PermissionManager(store: LocalPermissionStore(database: database.db), featureFlagger: featureFlagger)
        } else {
            fireproofDomains = FireproofDomains(store: FireproofDomainsStore(context: nil), tld: tld)
            faviconManager = FaviconManager(cacheType: .inMemory, bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains, privacyConfigurationManager: privacyConfigurationManager)
            permissionManager = PermissionManager(store: LocalPermissionStore(database: nil), featureFlagger: featureFlagger)
        }
#else
        fireproofDomains = FireproofDomains(store: FireproofDomainsStore(database: database.db, tableName: "FireproofDomains"), tld: tld)
        faviconManager = FaviconManager(cacheType: .standard(database.db), bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains, privacyConfigurationManager: privacyConfigurationManager)
        permissionManager = PermissionManager(store: LocalPermissionStore(database: database.db), featureFlagger: featureFlagger)
#endif
        notificationService = UserNotificationAuthorizationService()

        webCacheManager = WebCacheManager(fireproofDomains: fireproofDomains)

        let aiChatHistoryCleaner = AIChatHistoryCleaner(featureFlagger: featureFlagger,
                                                        aiChatMenuConfiguration: aiChatMenuConfiguration,
                                                        featureDiscovery: DefaultFeatureDiscovery(),
                                                        privacyConfig: privacyConfigurationManager)
        dataClearingPreferences = DataClearingPreferences(
            fireproofDomains: fireproofDomains,
            faviconManager: faviconManager,
            windowControllersManager: windowControllersManager,
            featureFlagger: featureFlagger,
            pixelFiring: PixelKit.shared,
            aiChatHistoryCleaner: aiChatHistoryCleaner
        )
        visualizeFireSettingsDecider = DefaultVisualizeFireSettingsDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)
        startupPreferences = StartupPreferences(
            pinningManager: pinningManager,
            persistor: StartupPreferencesUserDefaultsPersistor(keyValueStore: keyValueStore),
            appearancePreferences: appearancePreferences
        )
        defaultBrowserPreferences = DefaultBrowserPreferences()
        searchPreferences = SearchPreferences(persistor: SearchPreferencesUserDefaultsPersistor(), windowControllersManager: windowControllersManager)
        aboutPreferences = AboutPreferences(
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            windowControllersManager: windowControllersManager,
            keyValueStore: UserDefaults.standard
        )
        dockPreferences = DockPreferencesModel(
            featureFlagger: featureFlagger,
            dockCustomizer: dockCustomization,
            pixelFiring: PixelKit.shared
        )
        accessibilityPreferences = AccessibilityPreferences()
        duckPlayer = DuckPlayer(
            preferencesPersistor: DuckPlayerPreferencesUserDefaultsPersistor(),
            privacyConfigurationManager: privacyConfigurationManager,
            internalUserDecider: internalUserDecider
        )
        newTabPageCustomizationModel = NewTabPageCustomizationModel(appearancePreferences: appearancePreferences)

        fireCoordinator = FireCoordinator(tld: tld,
                                          featureFlagger: featureFlagger,
                                          historyCoordinating: historyCoordinator,
                                          visualizeFireAnimationDecider: visualizeFireSettingsDecider,
                                          onboardingContextualDialogsManager: { Application.appDelegate.onboardingContextualDialogsManager },
                                          fireproofDomains: fireproofDomains,
                                          faviconManagement: faviconManager,
                                          windowControllersManager: windowControllersManager,
                                          pixelFiring: PixelKit.shared,
                                          wideEventManaging: wideEvent,
                                          aiChatSyncCleaner: { Application.appDelegate.aiChatSyncCleaner })

        var appContentBlocking: AppContentBlocking?
#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            let contentBlocking = AppContentBlocking(
                privacyConfigurationManager: privacyConfigurationManager,
                internalUserDecider: internalUserDecider,
                featureFlagger: featureFlagger,
                configurationStore: configurationStore,
                contentScopeExperimentsManager: self.contentScopeExperimentsManager,
                onboardingNavigationDelegate: windowControllersManager,
                appearancePreferences: appearancePreferences,
                themeManager: themeManager,
                startupPreferences: startupPreferences,
                webTrackingProtectionPreferences: webTrackingProtectionPreferences,
                cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
                duckPlayer: duckPlayer,
                windowControllersManager: windowControllersManager,
                bookmarkManager: bookmarkManager,
                pinningManager: pinningManager,
                historyCoordinator: historyCoordinator,
                fireproofDomains: fireproofDomains,
                fireCoordinator: fireCoordinator,
                tld: tld,
                autoconsentManagement: autoconsentManagement,
                contentScopePreferences: contentScopePreferences,
                syncErrorHandler: syncErrorHandler,
                webExtensionAvailability: webExtensionAvailability,
                dockCustomization: dockCustomization
            )
            privacyFeatures = AppPrivacyFeatures(contentBlocking: contentBlocking, database: database.db)
            appContentBlocking = contentBlocking
        } else {
            // runtime mock-replacement for Unit Tests, to be redone when we‘ll be doing Dependency Injection
            privacyFeatures = AppPrivacyFeatures(contentBlocking: ContentBlockingMock(), httpsUpgradeStore: HTTPSUpgradeStoreMock())
        }
#else
        let contentBlocking = AppContentBlocking(
            privacyConfigurationManager: privacyConfigurationManager,
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            configurationStore: configurationStore,
            contentScopeExperimentsManager: self.contentScopeExperimentsManager,
            onboardingNavigationDelegate: windowControllersManager,
            appearancePreferences: appearancePreferences,
            themeManager: themeManager,
            startupPreferences: startupPreferences,
            webTrackingProtectionPreferences: webTrackingProtectionPreferences,
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
            duckPlayer: duckPlayer,
            windowControllersManager: windowControllersManager,
            bookmarkManager: bookmarkManager,
            pinningManager: pinningManager,
            historyCoordinator: historyCoordinator,
            fireproofDomains: fireproofDomains,
            fireCoordinator: fireCoordinator,
            tld: tld,
            autoconsentManagement: autoconsentManagement,
            contentScopePreferences: contentScopePreferences,
            syncErrorHandler: syncErrorHandler,
            webExtensionAvailability: webExtensionAvailability,
            dockCustomization: dockCustomization
        )
        privacyFeatures = AppPrivacyFeatures(
            contentBlocking: contentBlocking,
            database: database.db
        )
        appContentBlocking = contentBlocking
#endif
        configurationURLProvider = ConfigurationURLProvider(defaultProvider: AppConfigurationURLProvider(privacyConfigurationManager: privacyConfigurationManager, featureFlagger: featureFlagger), internalUserDecider: internalUserDecider, store: CustomConfigurationURLStorage(defaults: UserDefaults.appConfiguration))
        configurationManager = ConfigurationManager(
            fetcher: ConfigurationFetcher(store: configurationStore, configurationURLProvider: configurationURLProvider, eventMapping: ConfigurationManager.configurationDebugEvents),
            store: configurationStore,
            trackerDataManager: privacyFeatures.contentBlocking.trackerDataManager,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingManager: privacyFeatures.contentBlocking.contentBlockingManager,
            httpsUpgrade: privacyFeatures.httpsUpgrade
        )

        onboardingContextualDialogsManager = ContextualDialogsManager(
            trackerMessageProvider: TrackerMessageProvider(
                entityProviding: privacyFeatures.contentBlocking.contentBlockingManager
            )
        )

        let onboardingManager = onboardingContextualDialogsManager
        let notificationPresenter = DefaultBrowserAndDockPromptNotificationPresenter(reportABrowserProblemPresenter: Self.openReportABrowserProblem)
        defaultBrowserAndDockPromptService = DefaultBrowserAndDockPromptService(privacyConfigManager: privacyConfigurationManager,
                                                                                keyValueStore: keyValueStore,
                                                                                notificationPresenter: notificationPresenter,
                                                                                uiHosting: { windowControllersManager.activeViewController },
                                                                                isOnboardingCompletedProvider: { onboardingManager.state == .onboardingCompleted },
                                                                                dockCustomization: dockCustomization)

        if AppVersion.runType.requiresEnvironment {
            remoteMessagingClient = RemoteMessagingClient(
                remoteMessagingDatabase: RemoteMessagingDatabase().db,
                bookmarksDatabase: bookmarkDatabase.db,
                database: database.db,
                appearancePreferences: appearancePreferences,
                startupPreferences: startupPreferences,
                pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                internalUserDecider: internalUserDecider,
                configurationStore: configurationStore,
                remoteMessagingAvailabilityProvider: PrivacyConfigurationRemoteMessagingAvailabilityProvider(
                    privacyConfigurationManager: privacyConfigurationManager
                ),
                remoteMessagingSurfacesProvider: DefaultRemoteMessagingSurfacesProvider(),
                subscriptionManager: subscriptionManager,
                featureFlagger: self.featureFlagger,
                configurationURLProvider: configurationURLProvider,
                themeManager: themeManager,
                dbpDataManagerProvider: { DataBrokerProtectionManager.shared.dataManager }
            )
            let subscriptionManagerForPIR = subscriptionManager
            activeRemoteMessageModel = ActiveRemoteMessageModel(remoteMessagingClient: remoteMessagingClient, openURLHandler: { url in
                windowControllersManager.showTab(with: .contentFromURL(url, source: .appOpenUrl))
            }, navigateToFeedbackHandler: {
                windowControllersManager.showFeedbackModal(preselectedFormOption: .feedback(feedbackCategory: .other))
            }, navigateToPIRHandler: {
                let hasEntitlement = (try? await subscriptionManagerForPIR.isFeatureEnabled(.dataBrokerProtection)) ?? false
                await MainActor.run {
                    if hasEntitlement {
                        windowControllersManager.showTab(with: .dataBrokerProtection)
                    } else {
                        let url = subscriptionManagerForPIR.url(for: .purchase)
                        windowControllersManager.showTab(with: .subscription(url))
                    }
                }
            }, navigateToSoftwareUpdateHandler: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
            })
        } else {
            // As long as remoteMessagingClient is private to App Delegate and activeRemoteMessageModel
            // is used only by HomePage RootView as environment object,
            // it's safe to not initialize the client for unit tests to avoid side effects.
            remoteMessagingClient = nil
            activeRemoteMessageModel = ActiveRemoteMessageModel(
                remoteMessagingStore: nil,
                remoteMessagingAvailabilityProvider: nil,
                openURLHandler: { _ in },
                navigateToFeedbackHandler: { },
                navigateToPIRHandler: { },
                navigateToSoftwareUpdateHandler: { }
            )
        }

        // Update VPN environment and match the Subscription environment
        vpnSettings.alignTo(subscriptionEnvironment: subscriptionManager.currentEnvironment)

        // Update DBP environment and match the Subscription environment
        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)
        dbpSettings.alignTo(subscriptionEnvironment: subscriptionManager.currentEnvironment)

        // Also update the stored run type so the login item knows if tests are running
        dbpSettings.updateStoredRunType()

        // Freemium DBP
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)

        freemiumDBPFeature = DefaultFreemiumDBPFeature(privacyConfigurationManager: privacyConfigurationManager,
                                                       subscriptionManager: subscriptionManager,
                                                       freemiumDBPUserStateManager: freemiumDBPUserStateManager)
        freemiumDBPPromotionViewCoordinator = FreemiumDBPPromotionViewCoordinator(freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                                                                                  freemiumDBPFeature: freemiumDBPFeature,
                                                                                  contextualOnboardingPublisher: onboardingContextualDialogsManager.isContextualOnboardingCompletedPublisher.eraseToAnyPublisher())

        brokenSitePromptLimiter = BrokenSitePromptLimiter(privacyConfigManager: privacyConfigurationManager, store: BrokenSitePromptLimiterStore())
#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            privacyStats = PrivacyStats(databaseProvider: PrivacyStatsDatabase(), errorEvents: PrivacyStatsErrorHandler())
        } else {
            privacyStats = MockPrivacyStats()
        }
#else
        privacyStats = PrivacyStats(databaseProvider: PrivacyStatsDatabase())
#endif
        autoconsentStats = AutoconsentStats(keyValueStore: keyValueStore)
        autoconsentEventCoordinator = AutoconsentEventCoordinator(
            autoconsentStats: autoconsentStats,
            historyCoordinating: historyCoordinator,
            webExtensionAvailability: webExtensionAvailability
        )
        PixelKit.configureExperimentKit(featureFlagger: featureFlagger, eventTracker: ExperimentEventTracker(store: UserDefaults.appConfiguration))

        crashReporting = CrashReportingFactory.makeCrashReporting(internalUserDecider: internalUserDecider,
                                                                  featureFlagger: featureFlagger,
                                                                  keyValueStore: UserDefaults.standard)

        let watchdogDiagnosticProvider = MacWatchdogDiagnosticProvider(windowControllersManager: windowControllersManager)
        let eventMapper = WatchdogEventMapper(diagnosticProvider: watchdogDiagnosticProvider)
        watchdog = Watchdog(eventMapper: eventMapper)
        watchdogSleepMonitor = WatchdogSleepMonitor(watchdog: watchdog)

#if !DEBUG
        if AppVersion.runType == .normal {
            hangReportingFeatureMonitor = HangReportingFeatureMonitor(
                privacyConfigurationManager: privacyConfigurationManager,
                featureFlagger: featureFlagger,
                watchdog: watchdog
            )
        }
#endif

        recentlyClosedCoordinator = RecentlyClosedCoordinator(windowControllersManager: windowControllersManager, pinnedTabsManagerProvider: pinnedTabsManagerProvider)
        downloadsPreferences = DownloadsPreferences(persistor: DownloadsPreferencesUserDefaultsPersistor())
        downloadManager = FileDownloadManager(preferences: downloadsPreferences)
#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            downloadListCoordinator = DownloadListCoordinator(
                store: DownloadListStore(database: database.db),
                downloadManager: downloadManager,
                windowControllersManager: windowControllersManager
            )
        } else {
            downloadListCoordinator = DownloadListCoordinator(
                store: DownloadListStore(database: nil),
                downloadManager: downloadManager,
                windowControllersManager: windowControllersManager
            )
        }
#else
        downloadListCoordinator = DownloadListCoordinator(
            store: DownloadListStore(database: database.db),
            downloadManager: downloadManager,
            windowControllersManager: windowControllersManager
        )
#endif

        tabDragAndDropManager = TabDragAndDropManager()

        blackFridayCampaignProvider = DefaultBlackFridayCampaignProvider(
            privacyConfigurationManager: privacyConfigurationManager,
            isFeatureEnabled: { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.blackFridayCampaign) ?? false
            }
        )

        userChurnScheduler = UserChurnBackgroundActivityScheduler(
            defaultBrowserProvider: SystemDefaultBrowserProvider(),
            keyValueStore: keyValueStore,
            pixelFiring: PixelKit.shared,
            atbProvider: { LocalStatisticsStore().atb }
        )

        bitwardenManager = BWManagerProvider.makeManager()
        passwordManagerCoordinator = PasswordManagerCoordinator(bitwardenManagement: bitwardenManager)

        // AttributedMetric initialisation

        let errorHandler = AttributedMetricErrorHandler(pixelKit: PixelKit.shared)
        let attributedMetricDataStorage = AttributedMetricDataStorage(userDefaults: .appConfiguration,
                                                                      errorHandler: errorHandler)
        let settingsProvider = DefaultAttributedMetricSettingsProvider(privacyConfig: privacyConfigurationManager.privacyConfig)
        let subscriptionStateProvider = DefaultSubscriptionStateProvider(subscriptionManager: subscriptionManager)
        let defaultBrowserProvider = SystemDefaultBrowserProvider()
        let returningUserProvider = AttributedMetricReturningUserProvider(
            reinstallUserDetection: DefaultReinstallUserDetection(keyValueStore: keyValueStore)
        )
        self.attributedMetricManager = AttributedMetricManager(pixelKit: PixelKit.shared,
                                                               dataStoring: attributedMetricDataStorage,
                                                               featureFlagger: featureFlagger,
                                                               originProvider: AttributedMetricOriginFileProvider(),
                                                               defaultBrowserProviding: defaultBrowserProvider,
                                                               subscriptionStateProvider: subscriptionStateProvider,
                                                               returningUserProvider: returningUserProvider,
                                                               settingsProvider: settingsProvider)
        self.attributedMetricManager.addNotificationsObserver()

        memoryUsageMonitor = MemoryUsageMonitor(internalUserDecider: internalUserDecider, logger: .memory)
        memoryUsageThresholdReporter = MemoryUsageThresholdReporter(
            memoryUsageMonitor: memoryUsageMonitor,
            featureFlagger: featureFlagger,
            pixelFiring: PixelKit.shared,
            launchDate: appLaunchDate,
            logger: .memory
        )

        super.init()

        webExtensionManagerHolder.appDelegate = self

        memoryPressureReporter = MemoryPressureReporter(
            pixelFiring: PixelKit.shared,
            memoryUsageMonitor: memoryUsageMonitor,
            windowContext: WindowContext(windowControllersManager: windowControllersManager),
            isSyncEnabled: { [weak self] in
                guard let syncService = self?.syncService else { return nil }

                return syncService.authState == .active
            },
            launchDate: appLaunchDate,
            logger: .memory
        )

        memoryUsageIntervalReporter = MemoryUsageIntervalReporter(
            memoryUsageMonitor: memoryUsageMonitor,
            featureFlagger: featureFlagger,
            pixelFiring: PixelKit.shared,
            windowContext: WindowContext(windowControllersManager: windowControllersManager),
            isSyncEnabled: { [weak self] in
                guard let syncService = self?.syncService else { return nil }

                return syncService.authState == .active
            },
            launchDate: appLaunchDate,
            logger: .memory
        )

        let metricsReporter = PerformanceMetricsReporter(
            pixelFiring: PixelKit.shared,
            previousSessionRestored: startupPreferences.restorePreviousSession,
            windowContext: WindowContext(windowControllersManager: windowControllersManager)
        )
        startupProfiler.delegate = metricsReporter
        startupMetricsReporter = metricsReporter

        appContentBlocking?.userContentUpdating.userScriptDependenciesProvider = self
    }
    // swiftlint:enable cyclomatic_complexity

    func applicationWillFinishLaunching(_ notification: Notification) {
        let profilerToken = startupProfiler.startMeasuring(.appWillFinishLaunching)
        defer {
            profilerToken.stop()
        }

        /// Check for reinstalling user by comparing bundle creation dates.
        /// Stores the bundle's creation date in the KeyValueStore and compares
        /// on subsequent launches. If the date changes and it's not a Sparkle update,
        /// the user has reinstalled the app.
        ///
        /// This needs to run before the SparkleUpdateController is run to avoid having the user defaults resetted after an update restart.
        do {
            try DefaultReinstallUserDetection(keyValueStore: keyValueStore).checkForReinstallingUser()
        } catch {
            Logger.general.error("Problem when checking for reinstalling user: \(error.localizedDescription)")
        }

        APIRequest.Headers.setUserAgent(UserAgent.duckDuckGoUserAgent())

        stateRestorationManager = AppStateRestorationManager(fileStore: fileStore,
                                                             startupPreferences: startupPreferences,
                                                             tabsPreferences: tabsPreferences,
                                                             keyValueStore: keyValueStore,
                                                             sessionRestorePromptCoordinator: sessionRestorePromptCoordinator,
                                                             pixelFiring: PixelKit.shared)

        initializeUpdateController()

        appIconChanger = AppIconChanger(internalUserDecider: internalUserDecider, appearancePreferences: appearancePreferences)

        if AppVersion.runType.requiresEnvironment {
            // Configure Event handlers
            let vpnUninstaller = VPNUninstaller(pinningManager: pinningManager, ipcClient: vpnXPCClient)
            let featureGatekeeper = DefaultVPNFeatureGatekeeper(vpnUninstaller: vpnUninstaller, subscriptionManager: subscriptionManager)
            let tunnelController = NetworkProtectionIPCTunnelController(featureGatekeeper: featureGatekeeper, ipcClient: vpnXPCClient)

            vpnSubscriptionEventHandler = VPNSubscriptionEventsHandler(subscriptionManager: subscriptionManager,
                                                                       tunnelController: tunnelController,
                                                                       vpnUninstaller: vpnUninstaller)

            // Freemium DBP
            freemiumDBPFeature.subscribeToDependencyUpdates()
        }

        // ignore popovers shown from a view not in view hierarchy
        // https://app.asana.com/0/1201037661562251/1206407295280737/f
        _ = NSPopover.swizzleShowRelativeToRectOnce
        // disable macOS system-wide window tabbing
        NSWindow.allowsAutomaticWindowTabbing = false
        // Fix SwifUI context menus and its owner View leaking
        SwiftUIContextMenuRetainCycleFix.setUp()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppVersion.runType.requiresEnvironment else { return }
        defer {
            didFinishLaunching = true
        }

        let profilerToken = startupProfiler.measureSequence(initialStep: .appDidFinishLaunchingBeforeRestoration)

        Task {
            await subscriptionManager.loadInitialData()

            vpnAppEventsHandler.applicationDidFinishLaunching()
        }

        historyCoordinator.loadHistory {
            self.historyCoordinator.migrateModelV5toV6IfNeeded()
        }

        privacyFeatures.httpsUpgrade.loadDataAsync()
        bookmarkManager.loadBookmarks()

        // Force use of .mainThread to prevent high WindowServer Usage
        // Pending Fix with newer Lottie versions
        // https://app.asana.com/0/1177771139624306/1207024603216659/f
        LottieConfiguration.shared.renderingEngine = .mainThread

        configurationManager.start()

        let isFirstLaunch = LocalStatisticsStore().atb == nil

        if isFirstLaunch {
            AppDelegate.firstLaunchDate = Date()
            if let build = Int(AppVersion.shared.buildNumber) {
                let store: any ThrowingKeyedStoring<UpdateControllerSettings> = keyValueStore.throwingKeyedStoring()
                try? store.set(build, for: \.installBuild)
            }
        }
        dockCustomization.synchronizeNotificationVisibilityWithFirstLaunchDate()

        setupWebExtensions()

        vpnUpsellVisibilityManager.setup(isFirstLaunch: isFirstLaunch, isOnboardingFinished: OnboardingActionsManager.isOnboardingFinished)

        AtbAndVariantCleanup.cleanup()
        DefaultVariantManager().assignVariantIfNeeded { _ in
            // MARK: perform first time launch logic here
        }
        AttributionXattrCanaryValidator().validateAndReport()

        let statisticsLoader = AppVersion.runType.requiresEnvironment ? StatisticsLoader.shared : nil
        statisticsLoader?.load()

        startupSync()

        profilerToken.advance(to: .appStateRestoration)

        if AppVersion.runType.stateRestorationAllowed {
            stateRestorationManager.applicationDidFinishLaunching()
        }

        profilerToken.advance(to: .appDidFinishLaunchingAfterRestoration)

        let urlEventHandlerResult = urlEventHandler.applicationDidFinishLaunching()

        if featureFlagger.isFeatureOn(.promoQueue) {
            let dependencies = PromoDependencies(
                keyValueStore: keyValueStore,
                isExternallyActivated: urlEventHandlerResult.willOpenWindows,
                isOnboardingCompletedProvider: { OnboardingActionsManager.isOnboardingFinished },
                activeRemoteMessageModel: activeRemoteMessageModel,
                defaultBrowserAndDockPromptService: defaultBrowserAndDockPromptService,
                sessionRestoreCoordinator: sessionRestorePromptCoordinator
            )
            promoService = PromoServiceFactory.makePromoService(dependencies: dependencies)
            NotificationCenter.default.post(name: .promoServiceAppLaunched, object: nil)
        }

        setUpAutoClearHandler()
        bitwardenManager?.initCommunication()

        if AppVersion.runType.opensWindowOnStartupIfNeeded,
           !urlEventHandlerResult.willOpenWindows && WindowsManager.windows.first(where: { $0 is MainWindow }) == nil {
            // Use startup window preferences if not restoring previous session
            if !startupPreferences.restorePreviousSession {
                let burnerMode = startupPreferences.startupBurnerMode()
                WindowsManager.openNewWindow(burnerMode: burnerMode, lazyLoadTabs: true)
            } else {
                WindowsManager.openNewWindow(lazyLoadTabs: true)
            }
        }

        grammarFeaturesManager.manage()

        applyPreferredTheme()

        if case .normal = AppVersion.runType {
            Task {
                await crashReporting.start()
            }
        }

        subscribeToEmailProtectionStatusNotifications()
        subscribeToDataImportCompleteNotification()
        subscribeToInternalUserChanges()
        subscribeToUpdateControllerChanges()

        fireFailedCompilationsPixelIfNeeded()

        UserDefaultsWrapper<Any>.clearRemovedKeys()

        vpnSubscriptionEventHandler?.startMonitoring()

        UNUserNotificationCenter.current().delegate = self

        dataBrokerProtectionSubscriptionEventHandler.registerForSubscriptionAccountManagerEvents()

        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let pirGatekeeper = DefaultDataBrokerProtectionFeatureGatekeeper(
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            subscriptionManager: subscriptionManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager
        )

        DataBrokerProtectionAppEvents(featureGatekeeper: pirGatekeeper).applicationDidFinishLaunching()

        TipKitAppEventHandler(featureFlagger: featureFlagger).appDidFinishLaunching()

        setUpAutofillPixelReporter()
        setUpPasswordsMenuBarVisibility()

        remoteMessagingClient?.startRefreshingRemoteMessages()

        // This messaging system has been replaced by RMF, but we need to clean up the message manifest for any users who had it stored.
        let deprecatedRemoteMessagingStorage = DefaultSurveyRemoteMessagingStorage.surveys()
        deprecatedRemoteMessagingStorage.removeStoredMessagesIfNecessary()

        if didCrashDuringCrashHandlersSetUp {
            PixelKit.fire(GeneralPixel.crashOnCrashHandlersSetUp)
            didCrashDuringCrashHandlersSetUp = false
        }

        freemiumDBPScanResultPolling = DefaultFreemiumDBPScanResultPolling(dataManager: DataBrokerProtectionManager.shared.dataManager, freemiumDBPUserStateManager: freemiumDBPUserStateManager)
        freemiumDBPScanResultPolling?.startPollingOrObserving()

        Task(priority: .utility) {
            await wideEventService.sendPendingEvents()
        }

        userChurnScheduler.start()

        memoryUsageMonitor.enableIfNeeded(featureFlagger: featureFlagger)

        startAutomationServerIfNeeded()

        PixelKit.fire(GeneralPixel.launch, doNotEnforcePrefix: true)
        profilerToken.stop()
    }

    func applicationDidResignActive(_ notification: Notification) {
        cleanScreenTimeDataOnMacOS26()
    }

    private func cleanScreenTimeDataOnMacOS26() {
        guard featureFlagger.isFeatureOn(.screenTimeCleaning) else { return }
        guard #available(macOS 26, *) else { return }
        Task {
            await ScreenTimeDataCleaner().removeScreenTimeData()
        }
    }

    private func fireFailedCompilationsPixelIfNeeded() {
        let store = FailedCompilationsStore()
        if store.hasAnyFailures {
            PixelKit.fire(DebugEvent(GeneralPixel.compilationFailed),
                          frequency: .legacyDaily,
                          withAdditionalParameters: store.summary,
                          includeAppVersionParameter: true) { didFire, _ in
                if !didFire {
                    store.cleanup()
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard didFinishLaunching else { return }

        // Touch coordinator so Next Steps delegate is registered before promo service starts (1s fallback).
        _ = newTabPageCoordinator
        promoService?.applicationDidBecomeActive()

        // Fire quit survey return user pixel if the user completed the survey and returned within 8-14 day window
        let quitSurveyPersistor = QuitSurveyUserDefaultsPersistor(keyValueStore: keyValueStore)
        QuitSurveyReturnUserHandler(
            persistor: quitSurveyPersistor,
            installDate: AppDelegate.firstLaunchDate
        ).fireReturnUserPixelIfNeeded()

        fireDailyActiveUserPixels()
        fireDailyFireWindowConfigurationPixels()
        fireDailyAIChatEnabledPixel()

        fireAutoconsentDailyPixel()
        fireThemeDailyPixel()

        initializeSync()

        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let pirGatekeeper = DefaultDataBrokerProtectionFeatureGatekeeper(
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            subscriptionManager: subscriptionManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager
        )

        DataBrokerProtectionAppEvents(featureGatekeeper: pirGatekeeper).applicationDidBecomeActive()

        Task { @MainActor in
            vpnAppEventsHandler.applicationDidBecomeActive()
        }

        defaultBrowserAndDockPromptService.applicationDidBecomeActive()

        Task { @MainActor in
            await autoconsentStatsPopoverCoordinator.checkAndShowDialogIfNeeded()
        }
    }

    private func fireDailyActiveUserPixels() {
        PixelKit.fire(GeneralPixel.dailyActiveUser, frequency: .legacyDaily, doNotEnforcePrefix: true)
        PixelKit.fire(GeneralPixel.dailyDefaultBrowser(isDefault: defaultBrowserPreferences.isDefault), frequency: .daily, doNotEnforcePrefix: true)
        PixelKit.fire(GeneralPixel.dailyAddedToDock(isAddedToDock: dockCustomization.isAddedToDock), frequency: .daily, doNotEnforcePrefix: true)
    }

    private func fireDailyFireWindowConfigurationPixels() {
        PixelKit.fire(GeneralPixel.dailyFireWindowConfigurationStartupFireWindowEnabled(
            startupFireWindow: startupPreferences.startupWindowType == .fireWindow
        ), frequency: .daily, doNotEnforcePrefix: true)

        PixelKit.fire(GeneralPixel.dailyFireWindowConfigurationOpenFireWindowByDefaultEnabled(
            openFireWindowByDefault: dataClearingPreferences.shouldOpenFireWindowByDefault
        ), frequency: .daily, doNotEnforcePrefix: true)

        PixelKit.fire(GeneralPixel.dailyFireWindowConfigurationFireAnimationEnabled(
            fireAnimationEnabled: dataClearingPreferences.isFireAnimationEnabled
        ), frequency: .daily, doNotEnforcePrefix: true)
    }

    private func fireDailyAIChatEnabledPixel() {
        PixelKit.fire(AIChatPixel.aiChatIsEnabled(isEnabled: aiChatPreferences.isAIFeaturesEnabled), frequency: .daily)
    }

    private func fireAutoconsentDailyPixel() {
        Task {
            let dailyStats = await autoconsentStats.fetchAutoconsentDailyUsagePack().asPixelParameters()
            PixelKit.fire(AutoconsentPixel.usageStats(stats: dailyStats), frequency: .daily)
        }
    }

    private func fireThemeDailyPixel() {
        PixelKit.fire(ThemePixels.themeNameDaily(themeName: themeManager.theme.name), frequency: .daily)
    }

    private func initializeSync() {
        guard let syncService else { return }
        syncService.initializeIfNeeded()
        syncService.scheduler.notifyAppLifecycleEvent()
        SyncDiagnosisHelper(syncService: syncService).diagnoseAccountStatus()
    }

    @MainActor
    private func initializeUpdateController() {
        guard AppVersion.runType.allowsUpdates else { return }

        let buildType = StandardApplicationBuildType()
        let notificationPresenter = UpdateNotificationPresenter(
            pixelFiring: PixelKit.shared,
            shouldSuppressPostUpdateNotification: { [weak self] in
                let wc = self?.windowControllersManager.lastKeyMainWindowController
                            ?? self?.windowControllersManager.mainWindowControllers.last
                return wc?.mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab.content == .releaseNotes
            },
            showNotificationPopover: { [weak self] popover in
                guard let wc = self?.windowControllersManager.lastKeyMainWindowController
                            ?? self?.windowControllersManager.mainWindowControllers.last,
                      let button = wc.mainViewController.navigationBarViewController.optionsButton else {
                    return false
                }
                let parent = wc.mainViewController
                guard parent.view.window?.isKeyWindow == true,
                      (parent.presentedViewControllers ?? []).isEmpty else {
                    return false
                }
                popover.show(onParent: parent, relativeTo: button)
                return true
            }
        )

        if buildType.isAppStoreBuild {
            guard let appStoreFactory = UpdateControllerFactory.self as? any AppStoreUpdateControllerFactory.Type else {
                assertionFailure("Failed to instantiate app store update controller")
                return
            }

            self.updateController = appStoreFactory.instantiate(
                internalUserDecider: internalUserDecider,
                featureFlagger: featureFlagger,
                pixelFiring: PixelKit.shared,
                notificationPresenter: notificationPresenter,
                isOnboardingFinished: { OnboardingActionsManager.isOnboardingFinished }
            )
        } else {
            assert(buildType.isSparkleBuild)

            guard let sparkleFactory = UpdateControllerFactory.self as? any SparkleUpdateControllerFactory.Type else {
                assertionFailure("Failed to instantiate sparkle update controller")
                return
            }

            let allowCustomUpdateFeed = buildType.isDebugBuild || buildType.isReviewBuild

            let sparkleUpdateController = sparkleFactory.instantiate(
                internalUserDecider: internalUserDecider,
                featureFlagger: featureFlagger,
                pixelFiring: PixelKit.shared,
                notificationPresenter: notificationPresenter,
                keyValueStore: UserDefaults.standard,
                allowCustomUpdateFeed: allowCustomUpdateFeed,
                isAutoUpdatePaused: { [featureFlagger] in
                    if buildType.isDebugBuild {
                        return !featureFlagger.isFeatureOn(.autoUpdateInDEBUG)
                    } else if buildType.isReviewBuild {
                        return !featureFlagger.isFeatureOn(.autoUpdateInREVIEW)
                    } else {
                        return false
                    }
                },
                wideEvent: wideEvent,
                isOnboardingFinished: { OnboardingActionsManager.isOnboardingFinished },
                openUpdatesPage: { [windowControllersManager] in
                    windowControllersManager.showTab(with: .releaseNotes)
                }
            )
            stateRestorationManager.subscribeToAutomaticAppRelaunching(using: sparkleUpdateController.willRelaunchAppPublisher)
            self.updateController = sparkleUpdateController
        }
    }

    private var terminationHandler: TerminationDeciderHandler?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Already running — the in-flight handler will reply() when done
        if terminationHandler != nil {
            return .terminateLater
        }

        let handler = TerminationDeciderHandler(
            deciders: createTerminationDeciders(),
            replyToApplicationShouldTerminate: { [weak self] shouldTerminate in
                // Keep terminationHandler set after successful completion so the
                // guard in applicationShouldTerminate blocks any subsequent calls.
                // During Sparkle updates the system can fire a second terminate
                // request right after reply:YES. If we cleared the handler, the
                // decider chain would re-run against already-closed windows and
                // overwrite the saved state with empty data.
                if !shouldTerminate {
                    self?.terminationHandler = nil
                }
                NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        )
        terminationHandler = handler
        let reply = handler.executeTerminationDeciders()

        if reply == .terminateCancel {
            // Synchronous cancellation — discard handler
            terminationHandler = nil
        }
        return reply
    }

    @MainActor
    private func createTerminationDeciders() -> [ApplicationTerminationDecider] {
        let persistor = QuitSurveyUserDefaultsPersistor(keyValueStore: keyValueStore)

        let deciders: [ApplicationTerminationDecider?] = [
            // 1. Quit survey (for new users within first 3 days)
            QuitSurveyAppTerminationDecider(
                featureFlagger: featureFlagger,
                dataClearingPreferences: dataClearingPreferences,
                downloadManager: downloadManager,
                installDate: AppDelegate.firstLaunchDate,
                persistor: persistor,
                reinstallUserDetection: DefaultReinstallUserDetection(keyValueStore: keyValueStore),
                showQuitSurvey: { [weak self] in
                    guard let self else { return }
                    let presenter = QuitSurveyPresenter(windowControllersManager: self.windowControllersManager, persistor: persistor, featureFlagger: self.featureFlagger, historyCoordinating: self.historyCoordinator, faviconManaging: self.faviconManager)
                    await presenter.showSurvey()
                }
            ),

            // 2. Active downloads check
            ActiveDownloadsAppTerminationDecider(
                downloadManager: downloadManager,
                downloadListCoordinator: downloadListCoordinator
            ),

            // 3. Warn before quit confirmation
            makeWarnBeforeQuitDecider(),

            // 4. Update controller cleanup
            .perform { [updateController] in
                updateController?.handleAppTermination()
            },

            // 5. State restoration
            .perform { [stateRestorationManager] in
                stateRestorationManager?.applicationWillTerminate()
            },

            // 6. Auto-clear (burn on quit)
            autoClearHandler,

            // 7. Privacy stats cleanup
            .terminationDecider { [privacyStats] _ in
                .async(Task {
                    await privacyStats.handleAppTermination()
                    return .next
                })
            },

            // 8. Close windows before quitting while waiting for ⌘Q release
            .perform {
                NSApp.visibleWindows.forEach { $0.close() }
            }
        ]

        return deciders.compactMap { $0 }
    }

    @MainActor
    private func makeWarnBeforeQuitDecider() -> ApplicationTerminationDecider? {
        // Don't show "warn before quit" if autoclear warning will be shown
        let willShowAutoClearWarning = dataClearingPreferences.isAutoClearEnabled && dataClearingPreferences.isWarnBeforeClearingEnabled

        // Don't show if no window is open
        let hasWindow = windowControllersManager.lastKeyMainWindowController?.window != nil

        guard featureFlagger.isFeatureOn(.warnBeforeQuit),
              !willShowAutoClearWarning,
              hasWindow,
              let currentEvent = NSApp.currentEvent else { return nil }

        guard let manager = WarnBeforeQuitManager(
            currentEvent: currentEvent,
            action: .quit,
            isWarningEnabled: { [tabsPreferences] in
                tabsPreferences.warnBeforeQuitting
            },
            isPhysicalKeyPress: WarnBeforeQuitManager.makePhysicalKeyPressCheck(for: currentEvent)
        ) else { return nil }

        let presenter = WarnBeforeQuitOverlayPresenter(
            startupPreferences: startupPreferences,
            buttonHandlers: [.dontShowAgain: { [tabsPreferences] in
                PixelKit.fire(GeneralPixel.warnBeforeQuitDontShowAgain, frequency: .standard)
                tabsPreferences.warnBeforeQuitting = false
            }],
            onHoverChange: { [weak manager] isHovering in
                manager?.setMouseHovering(isHovering)
            }
        )

        // Subscribe to state stream (the Task keeps presenter alive)
        presenter.subscribe(to: manager.stateStream)
        return manager
    }

    // MARK: - Automation Server

    private func startAutomationServerIfNeeded() {
        let buildType = StandardApplicationBuildType()
        guard buildType.isDebugBuild || buildType.isReviewBuild,
              let port = launchOptionsHandler.automationPort else {
            return
        }
        Task { @MainActor in
            automationServer = AutomationServer(
                windowControllersManager: windowControllersManager,
                contentBlockingManager: privacyFeatures.contentBlocking.contentBlockingManager,
                port: port
            )
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Application.appDelegate.windowControllersManager.mainWindowControllers.isEmpty,
           case .normal = AppVersion.runType {
            // Use startup window preferences when reopening from dock
            let burnerMode = startupPreferences.startupBurnerMode()
            WindowsManager.openNewWindow(burnerMode: burnerMode)
            return true
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return ApplicationDockMenu(internalUserDecider: internalUserDecider, isFireWindowDefault: visualizeFireSettingsDecider.isOpenFireWindowByDefaultEnabled)
    }

    func application(_ sender: NSApplication, openFiles files: [String]) {
        urlEventHandler.handleFiles(files)
    }

    // MARK: - Web Extensions

    @MainActor
    private func setupWebExtensions() {
        guard #available(macOS 15.4, *) else { return }

        let darkReaderSettings = AppDarkReaderFeatureSettings(
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            storage: keyValueStore.throwingKeyedStoring(),
            currentThemeProvider: appearancePreferences,
            pixelFiring: PixelKit.shared
        )
        self.darkReaderFeatureSettings = darkReaderSettings
        appearancePreferences.darkReaderFeatureSettings = darkReaderSettings

        darkReaderSettings.forceDarkModeChangedPublisher
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.syncEmbeddedExtensions()
                }
            }
            .store(in: &darkReaderCancellables)

        appearancePreferences.$themeAppearance
            .dropFirst()
            .sink { [weak self] _ in
                self?.darkReaderFeatureSettings?.themeDidChange()
            }
            .store(in: &darkReaderCancellables)

        let webExtensionsPublisher = featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.webExtensions)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        let embeddedExtensionPublisher = featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.embeddedExtension)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        webExtensionFeatureFlagHandler = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.webExtensionManager },
            featureFlagPublisher: webExtensionsPublisher,
            embeddedExtensionFlagPublisher: embeddedExtensionPublisher,
            onFeatureFlagEnabled: { [weak self] in
                await self?.initializeWebExtensions()
            },
            onFeatureFlagDisabled: { [weak self] in
                self?.webExtensionManager = nil
            },
            onEmbeddedExtensionFlagEnabled: { [weak self] in
                await self?.syncEmbeddedExtensions()
            }
        )

        if featureFlagger.isFeatureOn(.webExtensions) {
            // Create manager synchronously so it's available during state restoration.
            // Tabs restored before the manager exists won't have webExtensionController attached.
            let webExtensionManager = WebExtensionManagerFactory.makeManager(
                privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
                autoconsentPreferences: cookiePopupProtectionPreferences,
                darkReaderExcludedDomainsProvider: darkReaderSettings
            )
            self.webExtensionManager = webExtensionManager

            // Load extensions asynchronously - the controller is already attached to tabs
            Task {
                await webExtensionManager.loadInstalledExtensions()
                await syncEmbeddedExtensions()
            }
        } else {
            webExtensionManager = nil
        }
    }

    @available(macOS 15.4, *)
    @MainActor
    private func initializeWebExtensions() async {
        guard webExtensionManager == nil else {
            // Already initialized, just load extensions
            await (webExtensionManager as? WebExtensionManager)?.loadInstalledExtensions()
            await syncEmbeddedExtensions()
            return
        }

        let webExtensionManager = WebExtensionManagerFactory.makeManager(
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            autoconsentPreferences: cookiePopupProtectionPreferences,
            darkReaderExcludedDomainsProvider: darkReaderFeatureSettings
        )
        self.webExtensionManager = webExtensionManager

        await webExtensionManager.loadInstalledExtensions()
        await syncEmbeddedExtensions()
    }

    @available(macOS 15.4, *)
    @MainActor
    private func syncEmbeddedExtensions() async {
        guard !isSyncingEmbeddedExtensions else { return }
        guard let webExtensionManager = webExtensionManager as? WebExtensionManager else { return }

        isSyncingEmbeddedExtensions = true
        defer { isSyncingEmbeddedExtensions = false }

        var enabledTypes: Set<DuckDuckGoWebExtensionType> = []
        if featureFlagger.isFeatureOn(.embeddedExtension) {
            enabledTypes.insert(.embedded)
        }
        if darkReaderFeatureSettings?.isForceDarkModeEnabled == true {
            enabledTypes.insert(.darkReader)
        }
        await webExtensionManager.syncEmbeddedExtensions(enabledTypes: enabledTypes)
    }

    // MARK: - PixelKit

    static func configurePixelKit() {
        Self.setUpPixelKit(dryRun: PixelKitConfig.isDryRun(isProductionBuild: BuildFlags.isProductionBuild))
    }

    private static func setUpPixelKit(dryRun: Bool) {
        let source = NSApp.isSandboxed ? "browser-appstore" : "browser-dmg"
        let userAgent = UserAgent.duckDuckGoUserAgent()

        PixelKit.setUp(dryRun: dryRun,
                       appVersion: AppVersion.shared.versionNumber,
                       source: source,
                       defaultHeaders: [:],
                       defaults: .netP) { (pixelName: String, headers: [String: String], parameters: [String: String], _, _, onComplete: @escaping PixelKit.CompletionBlock) in

            let url = URL.pixelUrl(forPixelNamed: pixelName)
            let apiHeaders = APIRequest.Headers(userAgent: userAgent, additionalHeaders: headers)
            let configuration = APIRequest.Configuration(url: url, method: .get, queryParameters: parameters, headers: apiHeaders)
            let request = APIRequest(configuration: configuration)

            request.fetch { _, error in
                onComplete(error == nil, error)
            }
        }
    }

    // MARK: - Theme

    private func applyPreferredTheme() {
        appearancePreferences.updateUserInterfaceStyle()
    }

    // MARK: - Sync

    @MainActor private func startupSync() {
#if DEBUG
        let defaultEnvironment = ServerEnvironment.development
#else
        let defaultEnvironment = ServerEnvironment.production
#endif

        let environment: ServerEnvironment
        let buildType = StandardApplicationBuildType()
        if buildType.isDebugBuild || buildType.isReviewBuild {
            environment = ServerEnvironment(
                UserDefaultsWrapper(key: .syncEnvironment, defaultValue: defaultEnvironment.description).wrappedValue
            ) ?? defaultEnvironment
        } else {
            environment = defaultEnvironment
        }
        let syncDataProviders = SyncDataProvidersSource(
            bookmarksDatabase: bookmarkDatabase.db,
            bookmarkManager: bookmarkManager,
            appearancePreferences: appearancePreferences,
            syncErrorHandler: syncErrorHandler
        )
        let syncService = DDGSync(
            dataProvidersSource: syncDataProviders,
            errorEvents: SyncErrorHandler(),
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            keyValueStore: keyValueStore,
            environment: environment
        )
        let aiChatSyncCleaner = AIChatSyncCleaner(
            sync: syncService,
            keyValueStore: keyValueStore,
            featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger),
            httpRequestErrorHandler: syncErrorHandler.handleAiChatsError
        )
        syncService.setCustomOperations([AIChatDeleteOperation(cleaner: aiChatSyncCleaner)])

        syncService.initializeIfNeeded()
        syncDataProviders.setUpDatabaseCleaners(syncService: syncService)

        // This is also called in applicationDidBecomeActive, but we're also calling it here, since
        // syncService can be nil when applicationDidBecomeActive is called during startup, if a modal
        // alert is shown before it's instantiated.  In any case it should be safe to call this here,
        // since the scheduler debounces calls to notifyAppLifecycleEvent().
        //
        syncService.scheduler.notifyAppLifecycleEvent()

        self.syncDataProviders = syncDataProviders
        self.syncService = syncService
        self.aiChatSyncCleaner = aiChatSyncCleaner

        isSyncInProgressCancellable = syncService.isSyncInProgressPublisher
            .filter { $0 }
            .asVoid()
            .sink { [weak syncService] in
                PixelKit.fire(GeneralPixel.syncDaily, frequency: .legacyDailyNoSuffix)
                syncService?.syncDailyStats.sendStatsIfNeeded(handler: { params in
                    PixelKit.fire(GeneralPixel.syncSuccessRateDaily, withAdditionalParameters: params)
                })
            }

        subscribeSyncQueueToScreenLockedNotifications()
        subscribeToSyncFeatureFlags(syncService)
    }

    @UserDefaultsWrapper(key: .syncDidShowSyncPausedByFeatureFlagAlert, defaultValue: false)
    private var syncDidShowSyncPausedByFeatureFlagAlert: Bool

    private func subscribeToSyncFeatureFlags(_ syncService: DDGSync) {
        syncFeatureFlagsCancellable = syncService.featureFlagsPublisher
            .dropFirst()
            .map { $0.contains(.dataSyncing) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak syncService] isDataSyncingAvailable in
                if isDataSyncingAvailable {
                    self?.syncDidShowSyncPausedByFeatureFlagAlert = false
                } else if syncService?.authState == .active, self?.syncDidShowSyncPausedByFeatureFlagAlert == false {
                    let isSyncUIVisible = syncService?.featureFlags.contains(.userInterface) == true
                    let alert = NSAlert.dataSyncingDisabledByFeatureFlag(showLearnMore: isSyncUIVisible)
                    let response = alert.runModal()
                    self?.syncDidShowSyncPausedByFeatureFlagAlert = true

                    switch response {
                    case .alertSecondButtonReturn:
                        alert.window.sheetParent?.endSheet(alert.window)
                        DispatchQueue.main.async {
                            Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .sync)
                        }
                    default:
                        break
                    }
                }
            }
    }

    private func subscribeSyncQueueToScreenLockedNotifications() {
        let screenIsLockedPublisher = DistributedNotificationCenter.default
            .publisher(for: .init(rawValue: "com.apple.screenIsLocked"))
            .map { _ in true }
        let screenIsUnlockedPublisher = DistributedNotificationCenter.default
            .publisher(for: .init(rawValue: "com.apple.screenIsUnlocked"))
            .map { _ in false }

        screenLockedCancellable = Publishers.Merge(screenIsLockedPublisher, screenIsUnlockedPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked in
                guard let syncService = self?.syncService, syncService.authState != .inactive else {
                    return
                }
                if isLocked {
                    Logger.sync.debug("Screen is locked")
                    syncService.scheduler.cancelSyncAndSuspendSyncQueue()
                } else {
                    Logger.sync.debug("Screen is unlocked")
                    syncService.scheduler.resumeSyncQueue()
                }
            }
    }

    private func subscribeToEmailProtectionStatusNotifications() {
        NotificationCenter.default.publisher(for: .emailDidSignIn)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.emailDidSignInNotification(notification)
            }
            .store(in: &emailCancellables)

        NotificationCenter.default.publisher(for: .emailDidSignOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.emailDidSignOutNotification(notification)
            }
            .store(in: &emailCancellables)
    }

    private func subscribeToDataImportCompleteNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(dataImportCompleteNotification(_:)), name: .dataImportComplete, object: nil)
    }

    private func subscribeToInternalUserChanges() {
        UserDefaults.appConfiguration.isInternalUser = internalUserDecider.isInternalUser

        isInternalUserSharingCancellable = internalUserDecider.isInternalUserPublisher
            .assign(to: \.isInternalUser, onWeaklyHeld: UserDefaults.appConfiguration)
    }

    private func subscribeToUpdateControllerChanges() {
        guard AppVersion.runType.allowsUpdates,
              let sparkleUpdateController = updateController as? any SparkleUpdateControlling else { return }

        updateProgressCancellable = sparkleUpdateController.updateProgressPublisher
            .sink { [weak sparkleUpdateController] progress in
                sparkleUpdateController?.checkNewApplicationVersionIfNeeded(updateProgress: progress)
            }
    }

    private func emailDidSignInNotification(_ notification: Notification) {
        PixelKit.fire(NonStandardPixel.emailEnabled, doNotEnforcePrefix: true)
        if AppDelegate.isNewUser {
            PixelKit.fire(GeneralPixel.emailEnabledInitial, frequency: .legacyInitial)
        }

        if let object = notification.object as? EmailManager, let emailManager = syncDataProviders?.settingsAdapter.emailManager, object !== emailManager {
            syncService?.scheduler.notifyDataChanged()
        }
    }

    private func emailDidSignOutNotification(_ notification: Notification) {
        PixelKit.fire(NonStandardPixel.emailDisabled, doNotEnforcePrefix: true)
        if let object = notification.object as? EmailManager, let emailManager = syncDataProviders?.settingsAdapter.emailManager, object !== emailManager {
            syncService?.scheduler.notifyDataChanged()
        }
    }

    @objc private func dataImportCompleteNotification(_ notification: Notification) {
        if AppDelegate.isNewUser {
            PixelKit.fire(GeneralPixel.importDataInitial, frequency: .legacyInitial)
        }
    }

    @MainActor
    private func setUpAutoClearHandler() {
        let autoClearHandler = AutoClearHandler(dataClearingPreferences: dataClearingPreferences,
                                                startupPreferences: startupPreferences,
                                                fireViewModel: fireCoordinator.fireViewModel,
                                                stateRestorationManager: self.stateRestorationManager,
                                                aiChatSyncCleaner: aiChatSyncCleaner,
                                                wideEvent: wideEvent)
        self.autoClearHandler = autoClearHandler
        DispatchQueue.main.async {
            autoClearHandler.handleAppLaunch()
        }
    }

    private func setUpAutofillPixelReporter() {
        autofillPixelReporter = AutofillPixelReporter(
            usageStore: AutofillUsageStore(standardUserDefaults: .standard, appGroupUserDefaults: nil),
            autofillEnabled: AutofillPreferences().askToSaveUsernamesAndPasswords,
            eventMapping: EventMapping<AutofillPixelEvent> {event, _, params, _ in
                switch event {
                case .autofillActiveUser:
                    PixelKit.fire(GeneralPixel.autofillActiveUser, withAdditionalParameters: params)
                case .autofillEnabledUser:
                    PixelKit.fire(GeneralPixel.autofillEnabledUser)
                case .autofillOnboardedUser:
                    PixelKit.fire(GeneralPixel.autofillOnboardedUser)
                case .autofillToggledOn:
                    PixelKit.fire(GeneralPixel.autofillToggledOn, withAdditionalParameters: params)
                case .autofillToggledOff:
                    PixelKit.fire(GeneralPixel.autofillToggledOff, withAdditionalParameters: params)
                case .autofillLoginsStacked:
                    PixelKit.fire(GeneralPixel.autofillLoginsStacked, withAdditionalParameters: params)
                case .autofillCreditCardsStacked:
                    PixelKit.fire(GeneralPixel.autofillCreditCardsStacked, withAdditionalParameters: params)
                case .autofillIdentitiesStacked:
                    PixelKit.fire(GeneralPixel.autofillIdentitiesStacked, withAdditionalParameters: params)
                }
            },
            passwordManager: passwordManagerCoordinator,
            installDate: AppDelegate.firstLaunchDate)

        _ = NotificationCenter.default.addObserver(forName: .autofillUserSettingsDidChange,
                                                   object: nil,
                                                   queue: nil) { [weak self] _ in
            self?.autofillPixelReporter?.updateAutofillEnabledStatus(AutofillPreferences().askToSaveUsernamesAndPasswords)
        }
    }

    @MainActor
    private func setUpPasswordsMenuBarVisibility() {
        guard featureFlagger.isFeatureOn(.autofillPasswordsStatusBar) else {
            passwordsStatusBarMenu?.hide()
            passwordsStatusBarMenu = nil
            passwordsMenuBarCancellable = nil
            return
        }

        let preferences = AutofillPreferences()
        if passwordsStatusBarMenu == nil {
            passwordsStatusBarMenu = PasswordsStatusBarMenu(preferences: preferences, pinningManager: pinningManager)
        }

        if preferences.showInMenuBar {
            passwordsStatusBarMenu?.show()
        } else {
            passwordsStatusBarMenu?.hide()
        }

        passwordsMenuBarCancellable = NotificationCenter.default.publisher(for: .autofillShowInMenuBarDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    let showInMenuBar = AutofillPreferences().showInMenuBar
                    if showInMenuBar {
                        self?.passwordsStatusBarMenu?.show()
                    } else {
                        self?.passwordsStatusBarMenu?.hide()
                    }
                }
            }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return .banner
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let notificationIdentifier = DefaultBrowserAndDockPromptNotificationIdentifier(rawValue: response.notification.request.identifier) {
            await defaultBrowserAndDockPromptService.handleNotificationResponse(notificationIdentifier)
            return
        }

        // Handle web notification clicks
        let userInfo = response.notification.request.content.userInfo
        if let tabUUID = userInfo[WebNotificationsHandler.UserInfoKey.tabUUID] as? String,
           let notificationId = userInfo[WebNotificationsHandler.UserInfoKey.notificationId] as? String {
            await webNotificationClickHandler.handleClick(tabUUID: tabUUID, notificationId: notificationId)
        }
    }

}

extension AppDelegate: UserScriptDependenciesProviding {}

private extension FeatureFlagLocalOverrides {

    func applyUITestsFeatureFlagsIfNeeded() {
        guard AppVersion.runType == .uiTests else { return }

        for item in ProcessInfo().environment["FEATURE_FLAGS", default: ""].split(separator: " ") {
            let keyValue = item.split(separator: "=")
            let key = String(keyValue[0])
            guard let value = Bool(keyValue[safe: 1]?.lowercased() ?? "true") else {
                fatalError("Only true/false values are supported for feature flag values (or none)")
            }
            guard let featureFlag = FeatureFlag(rawValue: key) else {
                fatalError("Unrecognized feature flag: \(key)")
            }
            guard featureFlag.supportsLocalOverriding else {
                fatalError("Feature flag \(key) does not support local overriding")
            }
            if currentValue(for: featureFlag)! != value {
                toggleOverride(for: featureFlag)
            }
        }
    }

}
