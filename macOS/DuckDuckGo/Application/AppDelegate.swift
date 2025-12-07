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
import AutoconsentStats
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
import PrivacyStats
import RemoteMessaging
import ServiceManagement
import Subscription
import SyncDataProviders
import UserNotifications
import Utilities
import VPN
import VPNAppState
import WebKit
import AttributedMetric

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

#if CI
    private let keyStore = (NSClassFromString("MockEncryptionKeyStore") as? EncryptionKeyStoring.Type)!.init()
#else
    private let keyStore = EncryptionKeyStore()
#endif

    let fileStore: FileStore

#if APPSTORE
    private let crashCollection = CrashCollection(crashReportSender: CrashReportSender(platform: .macOSAppStore,
                                                                                       pixelEvents: CrashReportSender.pixelEvents))
#else
    private let crashReporter: CrashReporter
#endif

    let watchdog: Watchdog
    private let watchdogSleepMonitor: WatchdogSleepMonitor
    private var hangReportingFeatureMonitor: HangReportingFeatureMonitor?

    let keyValueStore: ThrowingKeyValueStoring

    let faviconManager: FaviconManager
    let pinnedTabsManager = PinnedTabsManager()
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

    private(set) var syncDataProviders: SyncDataProvidersSource?
    private(set) var syncService: DDGSyncing?
    private var isSyncInProgressCancellable: AnyCancellable?
    private var syncFeatureFlagsCancellable: AnyCancellable?
    private var screenLockedCancellable: AnyCancellable?
    private var emailCancellables = Set<AnyCancellable>()
    var privacyDashboardWindow: NSWindow?

    let tabCrashAggregator = TabCrashAggregator()
    let windowControllersManager: WindowControllersManager
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
    let accessibilityPreferences: AccessibilityPreferences
    let duckPlayer: DuckPlayer

    let database: Database!
    let bookmarkDatabase: BookmarkDatabase
    let bookmarkManager: LocalBookmarkManager
    let bookmarkDragDropManager: BookmarkDragDropManager
    let historyCoordinator: HistoryCoordinator
    let fireproofDomains: FireproofDomains
    let webCacheManager: WebCacheManager
    let tld = TLD()
    let privacyFeatures: AnyPrivacyFeatures
    let brokenSitePromptLimiter: BrokenSitePromptLimiter
    let fireCoordinator: FireCoordinator
    let permissionManager: PermissionManager
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
        featureFlagger: featureFlagger,
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
        protectionsReportModel: newTabPageProtectionsReportModel
    )

    private(set) lazy var aiChatTabOpener: AIChatTabOpening = AIChatTabOpener(
        promptHandler: AIChatPromptHandler.shared,
        aiChatTabManaging: windowControllersManager
    )
    let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    let aiChatSidebarProvider: AIChatSidebarProviding
    let aiChatPreferences: AIChatPreferences

    let privacyStats: PrivacyStatsCollecting
    let autoconsentStats: AutoconsentStatsCollecting
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
        subscriptionManager: subscriptionAuthV1toV2Bridge,
        featureFlagger: featureFlagger,
        vpnUpsellVisibilityManager: vpnUpsellVisibilityManager
    )
    let themeManager: ThemeManager

    let displaysTabsProgressIndicator: Bool

    let wideEvent: WideEventManaging
    let isUsingAuthV2: Bool
    var subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge
    let subscriptionManagerV1: (any SubscriptionManager)?
    let subscriptionManagerV2: (any SubscriptionManagerV2)?
    let subscriptionAuthMigrator: AuthMigrator
    static let deadTokenRecoverer = DeadTokenRecoverer()

    public let subscriptionUIHandler: SubscriptionUIHandling

    private(set) lazy var sessionRestorePromptCoordinator = SessionRestorePromptCoordinator(pixelFiring: PixelKit.shared)

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
        featureGatekeeper: DefaultVPNFeatureGatekeeper(subscriptionManager: subscriptionAuthV1toV2Bridge),
        featureFlagOverridesPublisher: featureFlagOverridesPublishingHandler.flagDidChangePublisher,
        loginItemsManager: LoginItemsManager(),
        defaults: .netP)
    private var vpnSubscriptionEventHandler: VPNSubscriptionEventsHandler?

    private var vpnXPCClient: VPNControllerXPCClient {
        VPNControllerXPCClient.shared
    }

    lazy var vpnUpsellVisibilityManager: VPNUpsellVisibilityManager = {
        return VPNUpsellVisibilityManager(
            isFirstLaunch: false,
            isNewUser: AppDelegate.isNewUser,
            subscriptionManager: subscriptionAuthV1toV2Bridge,
            defaultBrowserProvider: SystemDefaultBrowserProvider(),
            contextualOnboardingPublisher: onboardingContextualDialogsManager.isContextualOnboardingCompletedPublisher.eraseToAnyPublisher(),
            persistor: vpnUpsellUserDefaultsPersistor,
            timerDuration: vpnUpsellUserDefaultsPersistor.expectedUpsellTimeInterval
        )
    }()

    lazy var vpnUpsellUserDefaultsPersistor: VPNUpsellUserDefaultsPersistor = {
        return VPNUpsellUserDefaultsPersistor(keyValueStore: keyValueStore)
    }()

    // MARK: - DBP

    private lazy var dataBrokerProtectionSubscriptionEventHandler: DataBrokerProtectionSubscriptionEventHandler = {
        let authManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(subscriptionManager: subscriptionAuthV1toV2Bridge)
        return DataBrokerProtectionSubscriptionEventHandler(featureDisabler: DataBrokerProtectionFeatureDisabler(),
                                                            authenticationManager: authManager,
                                                            pixelHandler: DataBrokerProtectionMacOSPixelsHandler())
    }()

    // MARK: - Win-back Campaign
    lazy var winBackOfferVisibilityManager: WinBackOfferVisibilityManaging = {
        let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging
#if DEBUG || REVIEW
        let winBackOfferDebugStore = WinBackOfferDebugStore(keyValueStore: keyValueStore)
        let dateProvider: () -> Date = { winBackOfferDebugStore.simulatedTodayDate }
        winBackOfferVisibilityManager = WinBackOfferVisibilityManager(subscriptionManager: subscriptionAuthV1toV2Bridge,
                                                                      winbackOfferStore: winbackOfferStore,
                                                                      winbackOfferFeatureFlagProvider: winbackOfferFeatureFlagProvider,
                                                                      dateProvider: dateProvider,
                                                                      timeBeforeOfferAvailability: .seconds(5))
#else
        winBackOfferVisibilityManager = WinBackOfferVisibilityManager(subscriptionManager: subscriptionAuthV1toV2Bridge,
                                                                      winbackOfferStore: winbackOfferStore,
                                                                      winbackOfferFeatureFlagProvider: winbackOfferFeatureFlagProvider)
#endif
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
                                          subscriptionManager: subscriptionAuthV1toV2Bridge)
    }()

    lazy var winBackOfferPromotionViewCoordinator: WinBackOfferPromotionViewCoordinator = {
        return WinBackOfferPromotionViewCoordinator(winBackOfferVisibilityManager: winBackOfferVisibilityManager)
    }()

    let blackFridayCampaignProvider: BlackFridayCampaignProviding

    // MARK: - Wide Event Service

    private lazy var wideEventService: WideEventService = {
        return WideEventService(
            wideEvent: wideEvent,
            featureFlagger: featureFlagger,
            subscriptionBridge: subscriptionAuthV1toV2Bridge
        )
    }()

    private(set) var webExtensionManager: WebExtensionManaging?

    private var didFinishLaunching = false

    var updateController: UpdateController!
#if SPARKLE
    var dockCustomization: DockCustomization?
#endif

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

    @MainActor
    // swiftlint:disable cyclomatic_complexity
    override init() {
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
        wideEvent = WideEvent()

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

#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            privacyConfigurationManager = PrivacyConfigurationManager(
                fetchedETag: configurationStore.loadEtag(for: .privacyConfiguration),
                fetchedData: configurationStore.loadData(for: .privacyConfiguration),
                embeddedDataProvider: AppPrivacyConfigurationDataProvider(),
                localProtection: LocalUnprotectedDomains(database: database.db),
                errorReporting: AppContentBlocking.debugEvents,
                internalUserDecider: internalUserDecider
            )
        } else {
            privacyConfigurationManager = PrivacyConfigurationManager(
                fetchedETag: configurationStore.loadEtag(for: .privacyConfiguration),
                fetchedData: configurationStore.loadData(for: .privacyConfiguration),
                embeddedDataProvider: AppPrivacyConfigurationDataProvider(),
                localProtection: LocalUnprotectedDomains(database: nil),
                errorReporting: AppContentBlocking.debugEvents,
                internalUserDecider: internalUserDecider
            )
        }
#else
        privacyConfigurationManager = PrivacyConfigurationManager(
            fetchedETag: configurationStore.loadEtag(for: .privacyConfiguration),
            fetchedData: configurationStore.loadData(for: .privacyConfiguration),
            embeddedDataProvider: AppPrivacyConfigurationDataProvider(),
            localProtection: LocalUnprotectedDomains(database: database.db),
            errorReporting: AppContentBlocking.debugEvents,
            internalUserDecider: internalUserDecider
        )
#endif

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

        displaysTabsProgressIndicator = featureFlagger.isFeatureOn(.tabProgressIndicator)

        aiChatSidebarProvider = AIChatSidebarProvider(featureFlagger: featureFlagger)
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
            featureFlagger: featureFlagger
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
        let pixelHandler: SubscriptionPixelHandling = SubscriptionPixelHandler(source: .mainApp)
        let keychainType = KeychainType.dataProtection(.named(subscriptionAppGroup))
        let keychainManager = KeychainManager(attributes: SubscriptionTokenKeychainStorageV2.defaultAttributes(keychainType: keychainType), pixelHandler: pixelHandler)
        let authService = DefaultOAuthService(baseURL: subscriptionEnvironment.authEnvironment.url,
                                              apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: UserAgent.duckDuckGoUserAgent()))
        let tokenStorage = SubscriptionTokenKeychainStorageV2(keychainManager: keychainManager, userDefaults: .subs) { accessType, error in
            PixelKit.fire(SubscriptionErrorPixel.subscriptionKeychainAccessError(accessType: accessType,
                                                                                 accessError: error,
                                                                                 source: KeychainErrorSource.shared,
                                                                                 authVersion: KeychainErrorAuthVersion.v2),
                          frequency: .legacyDailyAndCount)
        }

        let legacyTokenStorage = SubscriptionTokenKeychainStorage(keychainType: keychainType)
        let authRefreshWideEventMapper = AuthV2TokenRefreshWideEventData.authV2RefreshEventMapping(wideEvent: wideEvent, isFeatureEnabled: {
#if DEBUG
            return featureFlagger.isFeatureOn(.authV2WideEventEnabled) // Allow the refresh event when using staging in debug mode, for easier testing
#else
            return featureFlagger.isFeatureOn(.authV2WideEventEnabled) && subscriptionEnvironment.serviceEnvironment == .production
#endif
        })
        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            legacyTokenStorage: legacyTokenStorage,
                                            authService: authService,
                                            refreshEventMapping: authRefreshWideEventMapper)
        let isAuthV2Enabled = featureFlagger.isFeatureOn(.privacyProAuthV2)
        subscriptionAuthMigrator = AuthMigrator(oAuthClient: authClient,
                                                    pixelHandler: pixelHandler,
                                                    isAuthV2Enabled: isAuthV2Enabled)
        self.isUsingAuthV2 = subscriptionAuthMigrator.isReadyToUseAuthV2

        if self.isUsingAuthV2 {
            // MARK: V2
            Logger.general.log("Configuring Subscription V2")
            var apiServiceForSubscription = APIServiceFactory.makeAPIServiceForSubscription(withUserAgent: UserAgent.duckDuckGoUserAgent())
            let subscriptionEndpointService = DefaultSubscriptionEndpointServiceV2(apiService: apiServiceForSubscription,
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
            let legacyAccountStorage = AccountKeychainStorage()
            let subscriptionManager: DefaultSubscriptionManagerV2
            if #available(macOS 12.0, *) {
                subscriptionManager = DefaultSubscriptionManagerV2(storePurchaseManager: DefaultStorePurchaseManagerV2(subscriptionFeatureMappingCache: subscriptionEndpointService,
                                                                              subscriptionFeatureFlagger: subscriptionFeatureFlagger),
                          oAuthClient: authClient,
                          userDefaults: subscriptionUserDefaults,
                          subscriptionEndpointService: subscriptionEndpointService,
                          subscriptionEnvironment: subscriptionEnvironment,
                          pixelHandler: pixelHandler,
                          legacyAccountStorage: legacyAccountStorage,
                          isInternalUserEnabled: isInternalUserEnabled)
            } else {
                subscriptionManager = DefaultSubscriptionManagerV2(oAuthClient: authClient,
                          userDefaults: subscriptionUserDefaults,
                          subscriptionEndpointService: subscriptionEndpointService,
                          subscriptionEnvironment: subscriptionEnvironment,
                          pixelHandler: pixelHandler,
                          legacyAccountStorage: legacyAccountStorage,
                          isInternalUserEnabled: isInternalUserEnabled)
            }

            // Expired refresh token recovery
            if #available(iOS 15.0, macOS 12.0, *) {
                let restoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager, storePurchaseManager: subscriptionManager.storePurchaseManager())
                subscriptionManager.tokenRecoveryHandler = {
                    try await Self.deadTokenRecoverer.attemptRecoveryFromPastPurchase(purchasePlatform: subscriptionManager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)
                }
            }

            subscriptionManagerV2 = subscriptionManager
            subscriptionManagerV1 = nil
            subscriptionAuthV1toV2Bridge = subscriptionManager
        } else {
            Logger.general.log("Configuring Subscription V1")
            let subscriptionManager = DefaultSubscriptionManager(featureFlagger: featureFlagger, pixelHandlingSource: .mainApp)
            subscriptionManagerV1 = subscriptionManager
            subscriptionManagerV2 = nil
            subscriptionAuthV1toV2Bridge = subscriptionManager
        }

        VPNAppState(defaults: .netP).isAuthV2Enabled = isUsingAuthV2

        pinnedTabsManagerProvider = PinnedTabsManagerProvider(sharedPinedTabsManager: pinnedTabsManager)

        let windowControllersManager = WindowControllersManager(
            pinnedTabsManagerProvider: pinnedTabsManagerProvider,
            subscriptionFeatureAvailability: DefaultSubscriptionFeatureAvailability(
                privacyConfigurationManager: privacyConfigurationManager,
                purchasePlatform: subscriptionAuthV1toV2Bridge.currentEnvironment.purchasePlatform,
                featureFlagProvider: SubscriptionPageFeatureFlagAdapter(featureFlagger: featureFlagger)
            ),
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger
        )
        tabsPreferences = TabsPreferences(persistor: TabsPreferencesUserDefaultsPersistor(), windowControllersManager: windowControllersManager)
        windowControllersManager.tabsPreferences = tabsPreferences
        self.windowControllersManager = windowControllersManager

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
            subscriptionManager: subscriptionAuthV1toV2Bridge
        )
        self.subscriptionNavigationCoordinator = subscriptionNavigationCoordinator

        themeManager = ThemeManager(appearancePreferences: appearancePreferences, internalUserDecider: internalUserDecider, featureFlagger: featureFlagger)

#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            fireproofDomains = FireproofDomains(store: FireproofDomainsStore(database: database.db, tableName: "FireproofDomains"), tld: tld)
            faviconManager = FaviconManager(cacheType: .standard(database.db), bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains)
            permissionManager = PermissionManager(store: LocalPermissionStore(database: database.db), featureFlagger: featureFlagger)
        } else {
            fireproofDomains = FireproofDomains(store: FireproofDomainsStore(context: nil), tld: tld)
            faviconManager = FaviconManager(cacheType: .inMemory, bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains)
            permissionManager = PermissionManager(store: LocalPermissionStore(database: nil), featureFlagger: featureFlagger)
        }
#else
        fireproofDomains = FireproofDomains(store: FireproofDomainsStore(database: database.db, tableName: "FireproofDomains"), tld: tld)
        faviconManager = FaviconManager(cacheType: .standard(database.db), bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains)
        permissionManager = PermissionManager(store: LocalPermissionStore(database: database.db), featureFlagger: featureFlagger)
#endif

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
            persistor: StartupPreferencesUserDefaultsPersistor(keyValueStore: keyValueStore),
            windowControllersManager: windowControllersManager,
            appearancePreferences: appearancePreferences
        )
        defaultBrowserPreferences = DefaultBrowserPreferences()
        searchPreferences = SearchPreferences(persistor: SearchPreferencesUserDefaultsPersistor(), windowControllersManager: windowControllersManager)
        aboutPreferences = AboutPreferences(
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            windowControllersManager: windowControllersManager
        )
        accessibilityPreferences = AccessibilityPreferences()
        duckPlayer = DuckPlayer(
            preferencesPersistor: DuckPlayerPreferencesUserDefaultsPersistor(),
            privacyConfigurationManager: privacyConfigurationManager,
            internalUserDecider: internalUserDecider
        )
        newTabPageCustomizationModel = NewTabPageCustomizationModel(themeManager: themeManager, appearancePreferences: appearancePreferences)

        fireCoordinator = FireCoordinator(tld: tld,
                                          featureFlagger: featureFlagger,
                                          historyCoordinating: historyCoordinator,
                                          visualizeFireAnimationDecider: visualizeFireSettingsDecider,
                                          onboardingContextualDialogsManager: { Application.appDelegate.onboardingContextualDialogsManager },
                                          fireproofDomains: fireproofDomains,
                                          faviconManagement: faviconManager,
                                          windowControllersManager: windowControllersManager,
                                          pixelFiring: PixelKit.shared)

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
                startupPreferences: startupPreferences,
                webTrackingProtectionPreferences: webTrackingProtectionPreferences,
                cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
                duckPlayer: duckPlayer,
                windowControllersManager: windowControllersManager,
                bookmarkManager: bookmarkManager,
                historyCoordinator: historyCoordinator,
                fireproofDomains: fireproofDomains,
                fireCoordinator: fireCoordinator,
                tld: tld,
                autoconsentManagement: autoconsentManagement,
                contentScopePreferences: contentScopePreferences
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
            startupPreferences: startupPreferences,
            webTrackingProtectionPreferences: webTrackingProtectionPreferences,
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
            duckPlayer: duckPlayer,
            windowControllersManager: windowControllersManager,
            bookmarkManager: bookmarkManager,
            historyCoordinator: historyCoordinator,
            fireproofDomains: fireproofDomains,
            fireCoordinator: fireCoordinator,
            tld: tld,
            autoconsentManagement: autoconsentManagement,
            contentScopePreferences: contentScopePreferences
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
        defaultBrowserAndDockPromptService = DefaultBrowserAndDockPromptService(featureFlagger: featureFlagger,
                                                                                privacyConfigManager: privacyConfigurationManager,
                                                                                keyValueStore: keyValueStore,
                                                                                notificationPresenter: notificationPresenter,
                                                                                isOnboardingCompletedProvider: { onboardingManager.state == .onboardingCompleted })

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
                subscriptionManager: subscriptionAuthV1toV2Bridge,
                featureFlagger: self.featureFlagger,
                configurationURLProvider: configurationURLProvider,
                themeManager: themeManager
            )
            activeRemoteMessageModel = ActiveRemoteMessageModel(remoteMessagingClient: remoteMessagingClient, openURLHandler: { url in
                windowControllersManager.showTab(with: .contentFromURL(url, source: .appOpenUrl))
            }, navigateToFeedbackHandler: {
                windowControllersManager.showFeedbackModal(preselectedFormOption: .feedback(feedbackCategory: .other))
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
                navigateToFeedbackHandler: { }
            )
        }

        // Update VPN environment and match the Subscription environment
        vpnSettings.alignTo(subscriptionEnvironment: subscriptionAuthV1toV2Bridge.currentEnvironment)

        // Update DBP environment and match the Subscription environment
        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)
        dbpSettings.alignTo(subscriptionEnvironment: subscriptionAuthV1toV2Bridge.currentEnvironment)
        dbpSettings.isAuthV2Enabled = isUsingAuthV2

        // Also update the stored run type so the login item knows if tests are running
        dbpSettings.updateStoredRunType()

        // Freemium DBP
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)

        freemiumDBPFeature = DefaultFreemiumDBPFeature(privacyConfigurationManager: privacyConfigurationManager,
                                                       subscriptionManager: subscriptionAuthV1toV2Bridge,
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
        autoconsentStats = AutoconsentStats(keyValueStore: keyValueStore, isFeatureEnabled: { featureFlagger.isFeatureOn(.newTabPageAutoconsentStats) })
        PixelKit.configureExperimentKit(featureFlagger: featureFlagger, eventTracker: ExperimentEventTracker(store: UserDefaults.appConfiguration))

#if !APPSTORE
        crashReporter = CrashReporter(internalUserDecider: internalUserDecider)
#endif

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

        // AttributedMetric initialisation

        let errorHandler = AttributedMetricErrorHandler(pixelKit: PixelKit.shared)
        let attributedMetricDataStorage = AttributedMetricDataStorage(userDefaults: .appConfiguration,
                                                                      errorHandler: errorHandler)
        let settingsProvider = DefaultAttributedMetricSettingsProvider(privacyConfig: privacyConfigurationManager.privacyConfig)
        let subscriptionStateProvider = DefaultSubscriptionStateProvider(subscriptionManager: subscriptionAuthV1toV2Bridge)
        let defaultBrowserProvider = SystemDefaultBrowserProvider()
        self.attributedMetricManager = AttributedMetricManager(pixelKit: PixelKit.shared,
                                                               dataStoring: attributedMetricDataStorage,
                                                               featureFlagger: featureFlagger,
                                                               originProvider: AttributedMetricOriginFileProvider(),
                                                               defaultBrowserProviding: defaultBrowserProvider,
                                                               subscriptionStateProvider: subscriptionStateProvider,
                                                               settingsProvider: settingsProvider)
        self.attributedMetricManager.addNotificationsObserver()

        super.init()

        appContentBlocking?.userContentUpdating.userScriptDependenciesProvider = self
    }
    // swiftlint:enable cyclomatic_complexity

    func applicationWillFinishLaunching(_ notification: Notification) {
        APIRequest.Headers.setUserAgent(UserAgent.duckDuckGoUserAgent())

        stateRestorationManager = AppStateRestorationManager(fileStore: fileStore,
                                                             startupPreferences: startupPreferences,
                                                             tabsPreferences: tabsPreferences,
                                                             keyValueStore: keyValueStore,
                                                             sessionRestorePromptCoordinator: sessionRestorePromptCoordinator,
                                                             pixelFiring: PixelKit.shared)
#if APPSTORE
        if AppVersion.runType != .uiTests {
            updateController = AppStoreUpdateController()
        }
#elseif SPARKLE
        if AppVersion.runType != .uiTests {
            let updateController = SparkleUpdateController(
                internalUserDecider: internalUserDecider
            )
            self.updateController = updateController
            stateRestorationManager.subscribeToAutomaticAppRelaunching(using: updateController.willRelaunchAppPublisher)
        }
#endif

        appIconChanger = AppIconChanger(internalUserDecider: internalUserDecider, appearancePreferences: appearancePreferences)

        // Configure Event handlers
        let tunnelController = NetworkProtectionIPCTunnelController(ipcClient: vpnXPCClient)
        let vpnUninstaller = VPNUninstaller(ipcClient: vpnXPCClient)

        vpnSubscriptionEventHandler = VPNSubscriptionEventsHandler(subscriptionManager: subscriptionAuthV1toV2Bridge,
                                                                   tunnelController: tunnelController,
                                                                   vpnUninstaller: vpnUninstaller)

        // Freemium DBP
        freemiumDBPFeature.subscribeToDependencyUpdates()

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

        Task {
            await subscriptionManagerV1?.loadInitialData()
            await subscriptionManagerV2?.loadInitialData()

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
        }

        setupWebExtensions()

        vpnUpsellVisibilityManager.setup(isFirstLaunch: isFirstLaunch)

        AtbAndVariantCleanup.cleanup()
        DefaultVariantManager().assignVariantIfNeeded { _ in
            // MARK: perform first time launch logic here
        }

        #if SPARKLE
        dockCustomization = DockCustomizer()
        #endif

        let statisticsLoader = AppVersion.runType.requiresEnvironment ? StatisticsLoader.shared : nil
        statisticsLoader?.load()

        startupSync()

        if [.normal, .uiTests].contains(AppVersion.runType) {
            stateRestorationManager.applicationDidFinishLaunching()
        }
        let urlEventHandlerResult = urlEventHandler.applicationDidFinishLaunching()

        setUpAutoClearHandler()

        BWManager.shared.initCommunication()

        if case .normal = AppVersion.runType,
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

#if APPSTORE
        crashCollection.startAttachingCrashLogMessages { [weak self] pixelParameters, payloads, completion in

            pixelParameters.forEach { parameters in
                var params = parameters
                params[PixelKit.Parameters.appVersion] = CrashCollection.removeBuildNumber(from: params[PixelKit.Parameters.appVersion])
                let appIdentifier = CrashPixelAppIdentifier(params.removeValue(forKey: "bundle"))
                PixelKit.fire(
                    GeneralPixel.crash(appIdentifier: appIdentifier),
                    frequency: .dailyAndStandard,
                    withAdditionalParameters: params,
                    includeAppVersionParameter: false
                )
            }

            guard let lastPayload = payloads.last else {
                return
            }
            if self?.internalUserDecider.isInternalUser == true {
                completion()
            } else {
                Task { @MainActor in
                    if await CrashReportPromptPresenter().showPrompt(for: CrashDataPayload(data: lastPayload)) == .allow {
                        completion()
                    }
                }
            }
        }
#else
        Task {
            await crashReporter.checkForNewReports()
        }
#endif

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
            subscriptionManager: subscriptionAuthV1toV2Bridge,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager
        )

        DataBrokerProtectionAppEvents(featureGatekeeper: pirGatekeeper).applicationDidFinishLaunching()

        TipKitAppEventHandler(featureFlagger: featureFlagger).appDidFinishLaunching()

        setUpAutofillPixelReporter()

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

        PixelKit.fire(NonStandardEvent(GeneralPixel.launch))
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

        fireDailyActiveUserPixels()
        fireDailyFireWindowConfigurationPixels()

        fireAutoconsentDailyPixel()

        initializeSync()

        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let pirGatekeeper = DefaultDataBrokerProtectionFeatureGatekeeper(
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            subscriptionManager: subscriptionAuthV1toV2Bridge,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager
        )

        DataBrokerProtectionAppEvents(featureGatekeeper: pirGatekeeper).applicationDidBecomeActive()

        subscriptionManagerV1?.refreshCachedSubscriptionAndEntitlements { isSubscriptionActive in
            if isSubscriptionActive {
                PixelKit.fire(SubscriptionPixel.subscriptionActive(AuthVersion.v1), frequency: .legacyDaily)
            }
        }

        Task {
            await subscriptionAuthMigrator.migrateAuthV1toAuthV2IfNeeded()
        }

        Task { @MainActor in
            vpnAppEventsHandler.applicationDidBecomeActive()
        }

        defaultBrowserAndDockPromptService.applicationDidBecomeActive()

        Task { @MainActor in
            await autoconsentStatsPopoverCoordinator.checkAndShowDialogIfNeeded()
        }
    }

    private func fireDailyActiveUserPixels() {
        PixelKit.fire(NonStandardEvent(GeneralPixel.dailyActiveUser), frequency: .legacyDaily)
        PixelKit.fire(NonStandardEvent(GeneralPixel.dailyDefaultBrowser(isDefault: defaultBrowserPreferences.isDefault)), frequency: .daily)
#if SPARKLE
        PixelKit.fire(NonStandardEvent(GeneralPixel.dailyAddedToDock(isAddedToDock: DockCustomizer().isAddedToDock)), frequency: .daily)
#endif
    }

    private func fireDailyFireWindowConfigurationPixels() {
        PixelKit.fire(NonStandardEvent(GeneralPixel.dailyFireWindowConfigurationStartupFireWindowEnabled(
            startupFireWindow: startupPreferences.startupWindowType == .fireWindow
        )), frequency: .daily)

        PixelKit.fire(NonStandardEvent(GeneralPixel.dailyFireWindowConfigurationOpenFireWindowByDefaultEnabled(
            openFireWindowByDefault: dataClearingPreferences.shouldOpenFireWindowByDefault
        )), frequency: .daily)

        PixelKit.fire(NonStandardEvent(GeneralPixel.dailyFireWindowConfigurationFireAnimationEnabled(
            fireAnimationEnabled: dataClearingPreferences.isFireAnimationEnabled
        )), frequency: .daily)
    }

    private func fireAutoconsentDailyPixel() {
        guard featureFlagger.isFeatureOn(.newTabPageAutoconsentStats) else { return }

        Task {
            let dailyStats = await autoconsentStats.fetchAutoconsentDailyUsagePack().asPixelParameters()
            PixelKit.fire(AutoconsentPixel.usageStats(stats: dailyStats), frequency: .daily)
        }
    }

    private func initializeSync() {
        guard let syncService else { return }
        syncService.initializeIfNeeded()
        syncService.scheduler.notifyAppLifecycleEvent()
        SyncDiagnosisHelper(syncService: syncService).diagnoseAccountStatus()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Show quit survey for first-time quitters (new users within 14 days)
        let decider = QuitSurveyDecider(
            featureFlagger: featureFlagger,
            dataClearingPreferences: dataClearingPreferences,
            downloadManager: downloadManager,
            installDate: AppDelegate.firstLaunchDate,
            persistor: QuitSurveyUserDefaultsPersistor(keyValueStore: keyValueStore)
        )

        if decider.shouldShowQuitSurvey {
            let alert = NSAlert()
            alert.messageText = "Quit DuckDuckGo?"
            alert.informativeText = "This is your first time quitting the application."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Quit Now")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()

            // Mark as shown regardless of user choice
            decider.markQuitSurveyShown()

            if response == .alertSecondButtonReturn {
                // User clicked "Cancel"
                return .terminateCancel
            }
        }

        if !downloadManager.downloads.isEmpty {
            // if there‘re downloads without location chosen yet (save dialog should display) - ignore them
            let activeDownloads = Set(downloadManager.downloads.filter { $0.state.isDownloading })
            if !activeDownloads.isEmpty {
                let alert = NSAlert.activeDownloadsTerminationAlert(for: downloadManager.downloads)
                let downloadsFinishedCancellable = FileDownloadManager.observeDownloadsFinished(activeDownloads) {
                    // close alert and burn the window when all downloads finished
                    NSApp.stopModal(withCode: .OK)
                }
                let response = alert.runModal()
                downloadsFinishedCancellable.cancel()
                if response == .cancel {
                    return .terminateCancel
                }
            }
            downloadManager.cancelAll(waitUntilDone: true)
            downloadListCoordinator.sync()
        }

        // Cancel any active update tracking flow
        updateController?.handleAppTermination()

        stateRestorationManager?.applicationWillTerminate()

        // Handling of "Burn on quit"
        if let terminationReply = autoClearHandler.handleAppTermination() {
            return terminationReply
        }

        tearDownPrivacyStats()

        return .terminateNow
    }

    func tearDownPrivacyStats() {
        let condition = RunLoop.ResumeCondition()
        Task {
            await privacyStats.handleAppTermination()
            condition.resolve()
        }
        RunLoop.current.run(until: condition)
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
        if #available(macOS 15.4, *), featureFlagger.isFeatureOn(.webExtensions) {
            let webExtensionManager = WebExtensionManager()
            self.webExtensionManager = webExtensionManager

            Task {
                await webExtensionManager.loadInstalledExtensions()
            }
        } else {
            self.webExtensionManager = nil
        }
    }

    // MARK: - PixelKit

    static func configurePixelKit() {
#if DEBUG || REVIEW
            Self.setUpPixelKit(dryRun: true)
#else
            Self.setUpPixelKit(dryRun: false)
#endif
    }

    private static func setUpPixelKit(dryRun: Bool) {
#if APPSTORE
        let source = "browser-appstore"
#else
        let source = "browser-dmg"
#endif

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

#if DEBUG || REVIEW
        let environment = ServerEnvironment(
            UserDefaultsWrapper(key: .syncEnvironment, defaultValue: defaultEnvironment.description).wrappedValue
        ) ?? defaultEnvironment
#else
        let environment = defaultEnvironment
#endif
        let syncErrorHandler = SyncErrorHandler()
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
#if SPARKLE
        guard AppVersion.runType != .uiTests else { return }

        updateProgressCancellable = updateController.updateProgressPublisher
            .sink { [weak self] progress in
                (self?.updateController as? SparkleUpdateController)?.checkNewApplicationVersionIfNeeded(updateProgress: progress)
            }
#endif
    }

    private func emailDidSignInNotification(_ notification: Notification) {
        PixelKit.fire(NonStandardEvent(NonStandardPixel.emailEnabled))
        if AppDelegate.isNewUser {
            PixelKit.fire(GeneralPixel.emailEnabledInitial, frequency: .legacyInitial)
        }

        if let object = notification.object as? EmailManager, let emailManager = syncDataProviders?.settingsAdapter.emailManager, object !== emailManager {
            syncService?.scheduler.notifyDataChanged()
        }
    }

    private func emailDidSignOutNotification(_ notification: Notification) {
        PixelKit.fire(NonStandardEvent(NonStandardPixel.emailDisabled))
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
                                                stateRestorationManager: self.stateRestorationManager)
        self.autoClearHandler = autoClearHandler
        DispatchQueue.main.async {
            autoClearHandler.handleAppLaunch()
            autoClearHandler.onAutoClearCompleted = {
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
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
            passwordManager: PasswordManagerCoordinator.shared,
            installDate: AppDelegate.firstLaunchDate)

        _ = NotificationCenter.default.addObserver(forName: .autofillUserSettingsDidChange,
                                                   object: nil,
                                                   queue: nil) { [weak self] _ in
            self?.autofillPixelReporter?.updateAutofillEnabledStatus(AutofillPreferences().askToSaveUsernamesAndPasswords)
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

extension AppDelegate: UserScriptDependenciesProviding {
    @MainActor
    func makeNewTabPageActionsManager() -> NewTabPageActionsManager? {
        guard let contentBlocking = privacyFeatures.contentBlocking as? AppContentBlocking else {
            return nil
        }

        return NewTabPageActionsManager(
            appearancePreferences: appearancePreferences,
            visualizeFireAnimationDecider: visualizeFireSettingsDecider,
            customizationModel: newTabPageCustomizationModel,
            bookmarkManager: bookmarkManager,
            faviconManager: faviconManager,
            duckPlayerHistoryEntryTitleProvider: duckPlayer,
            contentBlocking: contentBlocking,
            trackerDataManager: contentBlocking.trackerDataManager,
            activeRemoteMessageModel: activeRemoteMessageModel,
            historyCoordinator: historyCoordinator,
            fireproofDomains: fireproofDomains,
            privacyStats: privacyStats,
            autoconsentStats: autoconsentStats,
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
            freemiumDBPPromotionViewCoordinator: freemiumDBPPromotionViewCoordinator,
            tld: tld,
            fire: { @MainActor in self.fireCoordinator.fireViewModel.fire },
            keyValueStore: keyValueStore,
            featureFlagger: featureFlagger,
            windowControllersManager: windowControllersManager,
            tabsPreferences: tabsPreferences,
            newTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProvider(aiChatMenuConfiguration: aiChatMenuConfiguration),
            winBackOfferPromotionViewCoordinator: winBackOfferPromotionViewCoordinator,
            protectionsReportModel: newTabPageProtectionsReportModel
        )
    }
}

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
