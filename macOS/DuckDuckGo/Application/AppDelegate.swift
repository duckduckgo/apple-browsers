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
import Bookmarks
import BrokenSitePrompt
import BrowserServicesKit
import Cocoa
import Combine
import Common
import Configuration
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
import VPN
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
import VPNAppState
import WebKit
import ContentScopeScripts

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
    private let crashReporter = CrashReporter()
#endif

    let keyValueStore: ThrowingKeyValueStoring

    let faviconManager: FaviconManager
    let pinnedTabsManager = PinnedTabsManager()
    let pinnedTabsManagerProvider: PinnedTabsManagerProviding!
    private(set) var stateRestorationManager: AppStateRestorationManager!
    private var grammarFeaturesManager = GrammarFeaturesManager()
    let internalUserDecider: InternalUserDecider
    private var isInternalUserSharingCancellable: AnyCancellable?
    let featureFlagger: FeatureFlagger
    let visualizeFireAnimationDecider: VisualizeFireAnimationDecider
    let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    let featureFlagOverridesPublishingHandler = FeatureFlagOverridesPublishingHandler<FeatureFlag>()
    private var appIconChanger: AppIconChanger!
    private var autoClearHandler: AutoClearHandler!
    private(set) var autofillPixelReporter: AutofillPixelReporter?

    private(set) var syncDataProviders: SyncDataProviders!
    private(set) var syncService: DDGSyncing?
    private var isSyncInProgressCancellable: AnyCancellable?
    private var syncFeatureFlagsCancellable: AnyCancellable?
    private var screenLockedCancellable: AnyCancellable?
    private var emailCancellables = Set<AnyCancellable>()
    var privacyDashboardWindow: NSWindow?

    let windowControllersManager: WindowControllersManager
    let subscriptionNavigationCoordinator: SubscriptionNavigationCoordinator

    let appearancePreferences: AppearancePreferences
    let dataClearingPreferences: DataClearingPreferences
    let startupPreferences: StartupPreferences

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

    private var updateProgressCancellable: AnyCancellable?

    private(set) lazy var newTabPageCoordinator: NewTabPageCoordinator = NewTabPageCoordinator(
        appearancePreferences: appearancePreferences,
        customizationModel: newTabPageCustomizationModel,
        bookmarkManager: bookmarkManager,
        faviconManager: faviconManager,
        activeRemoteMessageModel: activeRemoteMessageModel,
        historyCoordinator: historyCoordinator,
        contentBlocking: privacyFeatures.contentBlocking,
        fireproofDomains: fireproofDomains,
        privacyStats: privacyStats,
        freemiumDBPPromotionViewCoordinator: freemiumDBPPromotionViewCoordinator,
        tld: tld,
        fireCoordinator: fireCoordinator,
        keyValueStore: keyValueStore,
        visualizeFireAnimationDecider: visualizeFireAnimationDecider,
        featureFlagger: featureFlagger
    )

    private(set) lazy var aiChatTabOpener: AIChatTabOpening = AIChatTabOpener(
        promptHandler: AIChatPromptHandler.shared,
        addressBarQueryExtractor: AIChatAddressBarPromptExtractor(),
        windowControllersManager: windowControllersManager
    )
    let aiChatSidebarProvider: AIChatSidebarProviding

    let privacyStats: PrivacyStatsCollecting
    let activeRemoteMessageModel: ActiveRemoteMessageModel
    let newTabPageCustomizationModel: NewTabPageCustomizationModel
    let remoteMessagingClient: RemoteMessagingClient!
    let onboardingContextualDialogsManager: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater
    let defaultBrowserAndDockPromptPresenter: DefaultBrowserAndDockPromptPresenter
    let defaultBrowserAndDockPromptKeyValueStore: DefaultBrowserAndDockPromptStorage
    let defaultBrowserAndDockPromptFeatureFlagger: DefaultBrowserAndDockPromptFeatureFlagger
    let visualStyle: VisualStyleProviding
    private let visualStyleDecider: VisualStyleDecider

    let isUsingAuthV2: Bool
    var subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge
    let subscriptionManagerV1: (any SubscriptionManager)?
    let subscriptionManagerV2: (any SubscriptionManagerV2)?
    let subscriptionAuthMigrator: AuthMigrator

    public let subscriptionUIHandler: SubscriptionUIHandling
    private let subscriptionCookieManager: any SubscriptionCookieManaging
    private var subscriptionCookieManagerFeatureFlagCancellable: AnyCancellable?

    // MARK: - Freemium DBP
    public let freemiumDBPFeature: FreemiumDBPFeature
    public let freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator
    private var freemiumDBPScanResultPolling: FreemiumDBPScanResultPolling?

    var configurationStore = ConfigurationStore()
    var configurationManager: ConfigurationManager

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

    // MARK: - DBP

    private lazy var dataBrokerProtectionSubscriptionEventHandler: DataBrokerProtectionSubscriptionEventHandler = {
        let authManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(subscriptionManager: subscriptionAuthV1toV2Bridge)
        return DataBrokerProtectionSubscriptionEventHandler(featureDisabler: DataBrokerProtectionFeatureDisabler(),
                                                            authenticationManager: authManager,
                                                            pixelHandler: DataBrokerProtectionMacOSPixelsHandler())
    }()

    private var didFinishLaunching = false

#if SPARKLE
    var updateController: UpdateController!
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

    // swiftlint:disable cyclomatic_complexity
    @MainActor
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
        aiChatSidebarProvider = AIChatSidebarProvider()

        let internalUserDeciderStore = InternalUserDeciderStore(fileStore: fileStore)
        internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)

        if AppVersion.runType.requiresEnvironment {
            Self.configurePixelKit()
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

        pinnedTabsManagerProvider = PinnedTabsManagerProvider()

#if DEBUG || REVIEW
        let defaultBrowserAndDockPromptDebugStore = DefaultBrowserAndDockPromptDebugStore()
        let defaultBrowserAndDockPromptDateProvider: () -> Date = { defaultBrowserAndDockPromptDebugStore.simulatedTodayDate }
#else
        let defaultBrowserAndDockPromptDateProvider: () -> Date = Date.init
#endif

        // MARK: - Subscription configuration

        subscriptionUIHandler = SubscriptionUIHandler(windowControllersManagerProvider: {
            return Application.appDelegate.windowControllersManager
        })

        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)

        // Configuring V2 for migration
        let keychainType = KeychainType.dataProtection(.named(subscriptionAppGroup))
        let authService = DefaultOAuthService(baseURL: subscriptionEnvironment.authEnvironment.url,
                                              apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: UserAgent.duckDuckGoUserAgent()))
        let tokenStorage = SubscriptionTokenKeychainStorageV2(keychainType: keychainType) { accessType, error in
            PixelKit.fire(PrivacyProErrorPixel.privacyProKeychainAccessError(accessType: accessType,
                                                                             accessError: error,
                                                                             source: KeychainErrorSource.shared,
                                                                             authVersion: KeychainErrorAuthVersion.v2),
                          frequency: .legacyDailyAndCount)
        }
        let legacyTokenStorage = SubscriptionTokenKeychainStorage(keychainType: keychainType)
        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            legacyTokenStorage: legacyTokenStorage,
                                            authService: authService)
        let pixelHandler: SubscriptionPixelHandler = AuthV2PixelHandler(source: .mainApp)
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
                case .usePrivacyProUSARegionOverride:
                    return (featureFlagger.internalUserDecider.isInternalUser &&
                            subscriptionEnvironment.serviceEnvironment == .staging &&
                            subscriptionUserDefaults.storefrontRegionOverride == .usa)
                case .usePrivacyProROWRegionOverride:
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
                        try await DeadTokenRecoverer.attemptRecoveryFromPastPurchase(subscriptionManager: subscriptionManager, restoreFlow: restoreFlow)
                }
            } else {
                subscriptionManager.tokenRecoveryHandler = {
                    try await DeadTokenRecoverer.reportDeadRefreshToken()
                }
            }

            subscriptionCookieManager = SubscriptionCookieManagerV2(subscriptionManager: subscriptionManager, currentCookieStore: {
                WKHTTPCookieStoreWrapper(store: WKWebsiteDataStore.default().httpCookieStore)
            }, eventMapping: SubscriptionCookieManageEventPixelMapping())
            subscriptionManagerV2 = subscriptionManager
            subscriptionManagerV1 = nil
            subscriptionAuthV1toV2Bridge = subscriptionManager
        } else {
            Logger.general.log("Configuring Subscription V1")
            let subscriptionManager = DefaultSubscriptionManager(featureFlagger: featureFlagger)
            subscriptionCookieManager = SubscriptionCookieManager(tokenProvider: subscriptionManager, currentCookieStore: {
                WKHTTPCookieStoreWrapper(store: WKWebsiteDataStore.default().httpCookieStore)
            }, eventMapping: SubscriptionCookieManageEventPixelMapping())
            subscriptionManagerV1 = subscriptionManager
            subscriptionManagerV2 = nil
            subscriptionAuthV1toV2Bridge = subscriptionManager
        }

        VPNAppState(defaults: .netP).isAuthV2Enabled = isUsingAuthV2

        let windowControllersManager = WindowControllersManager(
            pinnedTabsManagerProvider: pinnedTabsManagerProvider,
            subscriptionFeatureAvailability: DefaultSubscriptionFeatureAvailability(
                privacyConfigurationManager: privacyConfigurationManager,
                purchasePlatform: subscriptionAuthV1toV2Bridge.currentEnvironment.purchasePlatform, paidAIChatFlagStatusProvider: { featureFlagger.isFeatureOn(.paidAIChat) }
            ),
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger
        )
        self.windowControllersManager = windowControllersManager

        let subscriptionNavigationCoordinator = SubscriptionNavigationCoordinator(
            tabShower: windowControllersManager,
            subscriptionManager: subscriptionAuthV1toV2Bridge
        )
        self.subscriptionNavigationCoordinator = subscriptionNavigationCoordinator

        self.visualStyleDecider = DefaultVisualStyleDecider(featureFlagger: featureFlagger, internalUserDecider: internalUserDecider)
        visualStyle = visualStyleDecider.style

#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            fireproofDomains = FireproofDomains(store: FireproofDomainsStore(database: database.db, tableName: "FireproofDomains"), tld: tld)
            faviconManager = FaviconManager(cacheType: .standard(database.db), bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains)
            permissionManager = PermissionManager(store: LocalPermissionStore(database: database.db))
        } else {
            fireproofDomains = FireproofDomains(store: FireproofDomainsStore(context: nil), tld: tld)
            faviconManager = FaviconManager(cacheType: .inMemory, bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains)
            permissionManager = PermissionManager(store: LocalPermissionStore(database: nil))
        }
#else
        fireproofDomains = FireproofDomains(store: FireproofDomainsStore(database: database.db, tableName: "FireproofDomains"), tld: tld)
        faviconManager = FaviconManager(cacheType: .standard(database.db), bookmarkManager: bookmarkManager, fireproofDomains: fireproofDomains)
        permissionManager = PermissionManager(store: LocalPermissionStore(database: database.db))
#endif

        webCacheManager = WebCacheManager(fireproofDomains: fireproofDomains)

        dataClearingPreferences = DataClearingPreferences(
            fireproofDomains: fireproofDomains,
            faviconManager: faviconManager,
            windowControllersManager: windowControllersManager,
            featureFlagger: featureFlagger,
            pixelFiring: PixelKit.shared
        )
        visualizeFireAnimationDecider = DefaultVisualizeFireAnimationDecider(featureFlagger: featureFlagger, dataClearingPreferences: dataClearingPreferences)
        startupPreferences = StartupPreferences(appearancePreferences: appearancePreferences)
        newTabPageCustomizationModel = NewTabPageCustomizationModel(visualStyle: visualStyle, appearancePreferences: appearancePreferences)

        fireCoordinator = FireCoordinator(tld: tld)

#if DEBUG
        if AppVersion.runType.requiresEnvironment {
            privacyFeatures = AppPrivacyFeatures(
                contentBlocking: AppContentBlocking(
                    privacyConfigurationManager: privacyConfigurationManager,
                    internalUserDecider: internalUserDecider,
                    configurationStore: configurationStore,
                    contentScopeExperimentsManager: self.contentScopeExperimentsManager,
                    onboardingNavigationDelegate: windowControllersManager,
                    appearancePreferences: appearancePreferences,
                    startupPreferences: startupPreferences,
                    bookmarkManager: bookmarkManager,
                    historyCoordinator: historyCoordinator,
                    fireproofDomains: fireproofDomains,
                    fireCoordinator: fireCoordinator,
                    tld: tld
                ),
                database: database.db
            )
        } else {
            // runtime mock-replacement for Unit Tests, to be redone when we‘ll be doing Dependency Injection
            privacyFeatures = AppPrivacyFeatures(contentBlocking: ContentBlockingMock(), httpsUpgradeStore: HTTPSUpgradeStoreMock())
        }
#else
        privacyFeatures = AppPrivacyFeatures(
            contentBlocking: AppContentBlocking(
                privacyConfigurationManager: privacyConfigurationManager,
                internalUserDecider: internalUserDecider,
                configurationStore: configurationStore,
                contentScopeExperimentsManager: self.contentScopeExperimentsManager,
                onboardingNavigationDelegate: windowControllersManager,
                appearancePreferences: appearancePreferences,
                startupPreferences: startupPreferences,
                bookmarkManager: bookmarkManager,
                historyCoordinator: historyCoordinator,
                fireproofDomains: fireproofDomains,
                fireCoordinator: fireCoordinator,
                tld: tld
            ),
            database: database.db
        )
#endif

        configurationManager = ConfigurationManager(
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
        defaultBrowserAndDockPromptKeyValueStore = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStore)
        DefaultBrowserAndDockPromptStoreMigrator(
            oldStore: DefaultBrowserAndDockPromptLegacyStore(),
            newStore: defaultBrowserAndDockPromptKeyValueStore
        ).migrateIfNeeded()

        defaultBrowserAndDockPromptFeatureFlagger = DefaultBrowserAndDockPromptFeatureFlag(
            privacyConfigManager: privacyConfigurationManager,
            featureFlagger: featureFlagger
        )

        let defaultBrowserAndDockPromptDecider = DefaultBrowserAndDockPromptTypeDecider(
            featureFlagger: defaultBrowserAndDockPromptFeatureFlagger,
            store: defaultBrowserAndDockPromptKeyValueStore,
            installDateProvider: { LocalStatisticsStore().installDate },
            dateProvider: defaultBrowserAndDockPromptDateProvider
        )
        let coordinator = DefaultBrowserAndDockPromptCoordinator(
            promptTypeDecider: defaultBrowserAndDockPromptDecider,
            store: defaultBrowserAndDockPromptKeyValueStore,
            isOnboardingCompleted: { onboardingManager.state == .onboardingCompleted },
            dateProvider: defaultBrowserAndDockPromptDateProvider
        )
        let statusUpdateNotifier = DefaultBrowserAndDockPromptStatusUpdateNotifier()
        defaultBrowserAndDockPromptPresenter = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, statusUpdateNotifier: statusUpdateNotifier)

        if AppVersion.runType.requiresEnvironment {
            remoteMessagingClient = RemoteMessagingClient(
                remoteMessagingDatabase: RemoteMessagingDatabase().db,
                bookmarksDatabase: bookmarkDatabase.db,
                database: database.db,
                appearancePreferences: appearancePreferences,
                pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                internalUserDecider: internalUserDecider,
                configurationStore: configurationStore,
                remoteMessagingAvailabilityProvider: PrivacyConfigurationRemoteMessagingAvailabilityProvider(
                    privacyConfigurationManager: privacyConfigurationManager
                ),
                subscriptionManager: subscriptionAuthV1toV2Bridge,
                featureFlagger: self.featureFlagger,
                visualStyle: self.visualStyle
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
                                                                                  freemiumDBPFeature: freemiumDBPFeature)

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
        PixelKit.configureExperimentKit(featureFlagger: featureFlagger, eventTracker: ExperimentEventTracker(store: UserDefaults.appConfiguration))

#if !APPSTORE && WEB_EXTENSIONS_ENABLED
        if #available(macOS 15.4, *) {
            Task { @MainActor in
                await WebExtensionManager.shared.loadInstalledExtensions()
            }
        }
#endif
    }
    // swiftlint:enable cyclomatic_complexity

    func applicationWillFinishLaunching(_ notification: Notification) {
#if DEBUG
        // Workaround for Xcode 26 crash: https://developer.apple.com/forums/thread/787365?answerId=846043022#846043022
        // This is a known issue in Xcode 26 betas 1 and 2, if the issue is fixed in beta 3 onward then this can be removed
        nw_tls_create_options()
#endif

        APIRequest.Headers.setUserAgent(UserAgent.duckDuckGoUserAgent())
        Configuration.setURLProvider(AppConfigurationURLProvider(
            privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
            featureFlagger: featureFlagger
        ))

        stateRestorationManager = AppStateRestorationManager(fileStore: fileStore, startupPreferences: startupPreferences)

#if SPARKLE
        if AppVersion.runType != .uiTests {
            updateController = UpdateController(internalUserDecider: internalUserDecider)
            stateRestorationManager.subscribeToAutomaticAppRelaunching(using: updateController.willRelaunchAppPublisher)
        }
#endif

        appIconChanger = AppIconChanger(internalUserDecider: internalUserDecider)

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
        _ = DownloadListCoordinator.shared
        _ = RecentlyClosedCoordinator.shared

        if LocalStatisticsStore().atb == nil {
            AppDelegate.firstLaunchDate = Date()
        }
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

        let privacyConfigurationManager = privacyFeatures.contentBlocking.privacyConfigurationManager

        // Enable subscriptionCookieManager if feature flag is present
        if privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.setAccessTokenCookieForSubscriptionDomains) {
            subscriptionCookieManager.enableSettingSubscriptionCookie()
        }

        // Keep track of feature flag changes
        subscriptionCookieManagerFeatureFlagCancellable = privacyConfigurationManager.updatesPublisher
            .sink { [weak self, weak privacyConfigurationManager] in
                guard let self, let privacyConfigurationManager else { return }

                let isEnabled = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.setAccessTokenCookieForSubscriptionDomains)

                Task { @MainActor [weak self] in
                    if isEnabled {
                        self?.subscriptionCookieManager.enableSettingSubscriptionCookie()
                    } else {
                        await self?.subscriptionCookieManager.disableSettingSubscriptionCookie()
                    }
                }
            }

        if [.normal, .uiTests].contains(AppVersion.runType) {
            stateRestorationManager.applicationDidFinishLaunching()
        }

        setUpAutoClearHandler()

        BWManager.shared.initCommunication()

        if WindowsManager.windows.first(where: { $0 is MainWindow }) == nil,
           case .normal = AppVersion.runType {
            WindowsManager.openNewWindow(lazyLoadTabs: true)
        }

        grammarFeaturesManager.manage()

        applyPreferredTheme()

#if APPSTORE
        crashCollection.startAttachingCrashLogMessages { pixelParameters, payloads, completion in
            pixelParameters.forEach { parameters in
                PixelKit.fire(GeneralPixel.crash, withAdditionalParameters: parameters, includeAppVersionParameter: false)
                PixelKit.fire(GeneralPixel.crashDaily, frequency: .legacyDailyNoSuffix)
            }

            guard let lastPayload = payloads.last else {
                return
            }
            DispatchQueue.main.async {
                CrashReportPromptPresenter().showPrompt(for: CrashDataPayload(data: lastPayload), userDidAllowToReport: completion)
            }
        }
#else
        crashReporter.checkForNewReports()
#endif

        if visualStyleDecider.shouldFirePixel(style: visualStyle) {
            PixelKit.fire(VisualStylePixel.visualUpdatesEnabled, frequency: .uniqueByName)
        }

        urlEventHandler.applicationDidFinishLaunching()

        subscribeToEmailProtectionStatusNotifications()
        subscribeToDataImportCompleteNotification()
        subscribeToInternalUserChanges()
        subscribeToUpdateControllerChanges()

        fireFailedCompilationsPixelIfNeeded()

        UserDefaultsWrapper<Any>.clearRemovedKeys()

        vpnSubscriptionEventHandler?.registerForSubscriptionAccountManagerEvents()

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

        fireAppLaunchPixel()

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
                PixelKit.fire(PrivacyProPixel.privacyProSubscriptionActive, frequency: .legacyDaily)
            }
        }

        Task {
            await subscriptionAuthMigrator.migrateAuthV1toAuthV2IfNeeded()
        }

        Task { @MainActor in
            vpnAppEventsHandler.applicationDidBecomeActive()
            await subscriptionCookieManager.refreshSubscriptionCookie()
        }
    }

    private func fireAppLaunchPixel() {
#if SPARKLE
        PixelKit.fire(NonStandardEvent(GeneralPixel.launch(isDefault: DefaultBrowserPreferences().isDefault, isAddedToDock: DockCustomizer().isAddedToDock)), frequency: .legacyDaily)
#else
        PixelKit.fire(NonStandardEvent(GeneralPixel.launch(isDefault: DefaultBrowserPreferences().isDefault, isAddedToDock: nil)), frequency: .legacyDaily)
#endif
    }

    private func initializeSync() {
        guard let syncService else { return }
        syncService.initializeIfNeeded()
        syncService.scheduler.notifyAppLifecycleEvent()
        SyncDiagnosisHelper(syncService: syncService).diagnoseAccountStatus()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !FileDownloadManager.shared.downloads.isEmpty {
            // if there‘re downloads without location chosen yet (save dialog should display) - ignore them
            let activeDownloads = Set(FileDownloadManager.shared.downloads.filter { $0.state.isDownloading })
            if !activeDownloads.isEmpty {
                let alert = NSAlert.activeDownloadsTerminationAlert(for: FileDownloadManager.shared.downloads)
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
            FileDownloadManager.shared.cancelAll(waitUntilDone: true)
            DownloadListCoordinator.shared.sync()
        }
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
            WindowsManager.openNewWindow()
            return true
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return ApplicationDockMenu(internalUserDecider: internalUserDecider)
    }

    func application(_ sender: NSApplication, openFiles files: [String]) {
        urlEventHandler.handleFiles(files)
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

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let trimmedOSVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        let userAgent = UserAgent.duckDuckGoUserAgent(systemVersion: trimmedOSVersion)

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

    private func startupSync() {
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
        let syncDataProviders = SyncDataProviders(
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
                self?.updateController.checkNewApplicationVersionIfNeeded(updateProgress: progress)
            }
#endif
    }

    private func emailDidSignInNotification(_ notification: Notification) {
        PixelKit.fire(NonStandardEvent(NonStandardPixel.emailEnabled))
        if AppDelegate.isNewUser {
            PixelKit.fire(GeneralPixel.emailEnabledInitial, frequency: .legacyInitial)
        }

        if let object = notification.object as? EmailManager, let emailManager = syncDataProviders.settingsAdapter.emailManager, object !== emailManager {
            syncService?.scheduler.notifyDataChanged()
        }
    }

    private func emailDidSignOutNotification(_ notification: Notification) {
        PixelKit.fire(NonStandardEvent(NonStandardPixel.emailDisabled))
        if let object = notification.object as? EmailManager, let emailManager = syncDataProviders.settingsAdapter.emailManager, object !== emailManager {
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

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.banner)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
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
