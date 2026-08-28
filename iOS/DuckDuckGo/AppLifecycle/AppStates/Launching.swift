//
//  Launching.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckAiDataStore
import Persistence
import PrivacyConfig
import UIKit
import PixelKit
import BrowserServicesKit
import Subscription
import RemoteMessaging
import WebExtensions
import FeatureFlags_iOS

/// Represents the transient state where the app is being prepared for user interaction after being launched by the system.
/// - Usage:
///   - This state is typically associated with the `application(_:didFinishLaunchingWithOptions:)` method.
///   - It is responsible for performing the app's initial setup, including configuring dependencies and preparing the UI.
///   - As part of this state, the `MainViewController` is created.
/// - Transitions:
///   - `Connected`: Standard transition when the app completes its launch setup and the scene is connected.
/// - Notes:
///   - Avoid performing heavy or blocking operations during this phase to ensure smooth app startup.
@MainActor
struct Launching: LaunchingHandling {

    private let appSettings = AppDependencyProvider.shared.appSettings
    private let voiceSearchHelper = VoiceSearchHelper()
    private let fireproofing: Fireproofing = UserDefaultsFireproofing()
    private let favicons: Favicons
    private let featureFlagger = AppDependencyProvider.shared.featureFlagger
    private let contentScopeExperimentsManager = AppDependencyProvider.shared.contentScopeExperimentsManager
    private let aiChatSettings: AIChatSettings

    private let didFinishLaunchingStartTime = CFAbsoluteTimeGetCurrent()
    private let isAppLaunchedInBackground = UIApplication.shared.applicationState == .background

    private let configuration: AppConfiguration
    private let services: AppServices
    private let mainCoordinator: MainCoordinator
    private let launchTaskManager = LaunchTaskManager()
    private let launchSourceManager = LaunchSourceManager()
    private let lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>
    private let onboardingManager: OnboardingManager

    // MARK: - Handle application(_:didFinishLaunchingWithOptions:) logic here

    init() throws {
        Logger.lifecycle.info("Launching: \(#function)")

        // Wire the DesignSystem rebrand singleton to the live feature flag.
        // Consumed by `DesignSystemImages` accessors and the `Image(rebrandable:)` initializer
        // so call sites don't need to read the flag directly.
        AppRebrand.isAppRebranded = { [featureFlagger] in
            featureFlagger.isFeatureOn(.appRebranding)
        }

        // Temporary feature flag and wiring during rebrand rollout – used to enable color palette updates.
        DesignSystemRebrand.isAppRebranded = { [featureFlagger] in
            featureFlagger.isFeatureOn(.appRebranding)
        }

        DesignSystemPalette.current = featureFlagger.isFeatureOn(.appRebranding) ? .rebranded : .default

        favicons = Favicons(fireproofing: fireproofing)

        let appKeyValueFileStoreService = try AppKeyValueFileStoreService()
        lastBackgroundDateStorage = appKeyValueFileStoreService.keyValueFilesStore.throwingKeyedStoring()

        // Initialize configuration with the key-value store
        configuration = AppConfiguration(
            appKeyValueStore: appKeyValueFileStoreService.keyValueFilesStore,
            featureFlagger: featureFlagger
        )

        var isBookmarksDBFilePresent: Bool?
        if BoolFileMarker(name: .hasSuccessfullySetupBookmarksDatabaseBefore)?.isPresent ?? false {
            isBookmarksDBFilePresent = FileManager.default.fileExists(atPath: BookmarksDatabase.defaultDBFileURL.path)
        }

        // MARK: - Application Setup
        // Handles one-time application setup during launch
        try configuration.start(isBookmarksDBFilePresent: isBookmarksDBFilePresent)

        // Migrate existing fireproofed domains to eTLD+1 store
        fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded()

        // Set idleReturnNewUser at launch (before statistics load) so new vs existing users get the correct after-inactivity default.
        IdleReturnCohort.setCohortIfNeeded(
            storage: appKeyValueFileStoreService.keyValueFilesStore.throwingKeyedStoring(),
            statisticsStore: StatisticsUserDefaults()
        )

        // Pre-mark existing installs (before statistics load) so first_prompt_new_install can only fire on brand-new installs.
        DuckAIFirstPromptNewInstallCohort.assignIfNeeded(statisticsStore: StatisticsUserDefaults())

        // MARK: - Service Initialization (continued)
        // Create and initialize remaining core services
        // These services are instantiated early in the app lifecycle for two main reasons:
        // 1. To begin their essential work immediately, without waiting for UI or other components
        // 2. To potentially complete their tasks before the app becomes visible to the user
        // This approach aims to optimize performance and ensure critical functionalities are ready ASAP
        let autofillService = AutofillService(keyValueStore: appKeyValueFileStoreService.keyValueFilesStore)

        let contentBlocking = ContentBlocking.shared

        onboardingManager = OnboardingManager(appDefaults: appSettings, featureFlagger: featureFlagger, variantManager: configuration.atbAndVariantConfiguration.variantManager, tutorialSettings: DefaultTutorialSettings())

        // Construct the storage handler before SyncService so AIChatSyncCleaner has the
        // storage hook it needs to flush pending pin updates on each sync cycle.
        let duckAiNativeStorageHandler = Self.makeNativeStorageHandler(
            featureFlagger: featureFlagger,
            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore
        )

        let syncService = SyncService(bookmarksDatabase: configuration.persistentStoresConfiguration.bookmarksDatabase,
                                      privacyConfigurationManager: contentBlocking.privacyConfigurationManager,
                                      keyValueStore: appKeyValueFileStoreService.keyValueFilesStore,
                                      faviconStoring: favicons,
                                      duckAiNativeStorageHandler: duckAiNativeStorageHandler)

        let webExtensionManagerHolder = WebExtensionManagerHolder()
        let webExtensionAvailability = WebExtensionAvailability(
            featureFlagger: featureFlagger,
            webExtensionManagerProvider: {
                webExtensionManagerHolder.manager
            }
        )
        let fireModeStorageController = FireModeNativeStorageController(
            featureFlagger: featureFlagger,
            consentSeedSource: duckAiNativeStorageHandler,
            appConfigurationGroupName: Global.appConfigurationGroupName,
            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore
        )

        let adBlockingAvailabilityStorage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> = appKeyValueFileStoreService.keyValueFilesStore.throwingKeyedStoring()
        let adBlockingAvailability: AdBlockingAvailabilityProviding = AdBlockingAvailability(
            featureFlagger: featureFlagger,
            isEnabledByUserProvider: { [featureFlagger] in
                (try? adBlockingAvailabilityStorage.value(for: \.youTubeAdBlockingEnabled))
                    ?? featureFlagger.isFeatureOn(.adBlockingExtensionEnabledByDefault)
            }
        )

        let contentBlockingService = ContentBlockingService(appSettings: appSettings,
                                                            contentBlocking: contentBlocking,
                                                            sync: syncService.sync,
                                                            fireproofing: fireproofing,
                                                            contentScopeExperimentsManager: contentScopeExperimentsManager,
                                                            internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                                                            syncErrorHandler: syncService.syncErrorHandler,
                                                            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore,
                                                            webExtensionAvailability: webExtensionAvailability,
                                                            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
                                                            fireModeStorageController: fireModeStorageController,
                                                            adBlockingAvailability: adBlockingAvailability)

        // Constructed before MainCoordinator: its `eventHub` is threaded down to every tab.
        // EventHub gets its own store, matching macOS, so its period state never shares a file with app
        // settings. `try?` — an unopenable store degrades telemetry to in-memory rather than failing launch.
        let eventHubStore = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .flatMap { try? KeyValueFileStore(location: $0, name: "EventHubKeyValueStore") }
        let eventHubService = EventHubService(
            privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager,
            keyValueStore: eventHubStore,
            consentStore: appKeyValueFileStoreService.keyValueFilesStore
        )

        let freemiumPIRDebugSettings = FreemiumPIRDebugSettings(keyValueStore: appKeyValueFileStoreService.keyValueFilesStore)
        let dbpService = DBPService(appDependencies: AppDependencyProvider.shared,
                                    contentBlocking: contentBlockingService.common,
                                    freemiumPIRDebugSettings: freemiumPIRDebugSettings)
        let configurationService = RemoteConfigurationService()
        let crashCollectionService = CrashCollectionService(featureFlagger: featureFlagger)
        let launchTimeMetricsService = LaunchTimeMetricsService(featureFlagger: featureFlagger)
        let statisticsService = StatisticsService()

        let productSurfaceTelemetry = PixelProductSurfaceTelemetry(featureFlagger: featureFlagger, pixelFiring: PixelKit.shared)
        let reportingService = ReportingService(fireproofing: fireproofing,
                                                featureFlagging: featureFlagger,
                                                userDefaults: UserDefaults.app,
                                                pixelKit: PixelKit.shared,
                                                appDependencies: AppDependencyProvider.shared,
                                                privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager)

        reportingService.syncService = syncService
        autofillService.syncService = syncService

        let daxDialogs = configuration.onboardingConfiguration.daxDialogs

        let winBackOfferService = WinBackOfferFactory.makeService(keyValueFilesStore: appKeyValueFileStoreService.keyValueFilesStore,
                                                                  featureFlagger: featureFlagger,
                                                                  daxDialogs: daxDialogs)
        let freemiumPIREligibilityChecker = DefaultFreemiumPIREligibilityChecker(
            featureFlagger: featureFlagger,
            runPrerequisitesDelegate: dbpService.dbpIOSPublicInterface,
            subscriptionAuthenticationStateProvider: AppDependencyProvider.shared.subscriptionManager,
            freemiumPIRDebugSettings: freemiumPIRDebugSettings
        )

        let remoteMessagingImageLoader = RemoteMessagingImageLoader(
            dataProvider: RemoteMessagingImageLoader.defaultDataProvider,
            cache: RemoteMessagingImageLoader.defaultCache
        )
        let idleReturnEligibilityManager = IdleReturnEligibilityManager(
            featureFlagger: featureFlagger,
            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore,
            privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager,
            isStillOnboarding: { daxDialogs.isStillOnboarding() }
        )
        let remoteMessagingService = RemoteMessagingService(bookmarksDatabase: configuration.persistentStoresConfiguration.bookmarksDatabase,
                                                            database: configuration.persistentStoresConfiguration.database,
                                                            appSettings: appSettings,
                                                            internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                                                            configurationStore: AppDependencyProvider.shared.configurationStore,
                                                            privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager,
                                                            configurationURLProvider: AppDependencyProvider.shared.configurationURLProvider,
                                                            syncService: syncService.sync,
                                                            winBackOfferService: winBackOfferService,
                                                            freemiumPIREligibilityChecker: freemiumPIREligibilityChecker,
                                                            freemiumDBPUserStateManager: dbpService.freemiumDBPUserStateManager,
                                                            profileStateManager: dbpService.profileStateManager,
                                                            subscriptionDataReporter: reportingService.subscriptionDataReporter,
                                                            remoteMessagingImageLoader: remoteMessagingImageLoader,
                                                            idleReturnEligibilityManager: idleReturnEligibilityManager,
                                                            dbpRunPrerequisitesDelegate: dbpService.dbpIOSPublicInterface)
        let subscriptionService = SubscriptionService(privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager, featureFlagger: featureFlagger)
        let maliciousSiteProtectionService = MaliciousSiteProtectionService(featureFlagger: featureFlagger,
                                                                            privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager)
        let systemSettingsPiPTutorialService = SystemSettingsPiPTutorialService(featureFlagger: featureFlagger)
        let wideEventService = WideEventService(
            wideEvent: AppDependencyProvider.shared.wideEvent,
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager
        )

        // Service to display the Default Browser prompt.
        let defaultBrowserPromptService = DefaultBrowserPromptService(
            featureFlagger: featureFlagger,
            privacyConfigManager: contentBlockingService.common.privacyConfigurationManager,
            keyValueFilesStore: appKeyValueFileStoreService.keyValueFilesStore,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialService.manager
        )

        // Has to be initialised after configuration.start in case values need to be migrated
        let aiChatSettings = AIChatSettings()
        self.aiChatSettings = aiChatSettings

        // Create What's New repository for use in modal prompts and settings
        let whatsNewRepository = DefaultWhatsNewMessageRepository(
            remoteMessageStore: remoteMessagingService.remoteMessagingClient.store,
            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore
        )

        // Subscription promo for reinstallers / skipped-onboarding users
        let subscriptionPromoCoordinator = SubscriptionPromoCoordinator(
            featureFlagger: featureFlagger,
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager
        )
        let subscriptionPromoPresenter = SubscriptionPromoPresenter(coordinator: subscriptionPromoCoordinator)

        // Subscription promo for existing users (7+ days since install) who have never seen a subscription offer
        let subscriptionPromoExistingUserCoordinator = SubscriptionPromoExistingUserCoordinator(
            daxDialogs: daxDialogs,
            featureFlagger: featureFlagger,
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager
        )
        let subscriptionPromoExistingUserPresenter = SubscriptionPromoPresenter(coordinator: subscriptionPromoExistingUserCoordinator)

        // Initialise promo coordination
        let omniBarFocuser = OmniBarFocuserProvider()
        let promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
        let promoCoordinationService = PromoCoordinationFactory.makeService(
            dependency: .init(
                launchSourceManager: launchSourceManager,
                contextualOnboardingStatusProvider: daxDialogs,
                keyValueFileStoreService: appKeyValueFileStoreService.keyValueFilesStore,
                privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager,
                featureFlagger: featureFlagger,
                promoQueueLeaseArbiter: promoQueueLeaseArbiter,
                whatsNewRepository: whatsNewRepository,
                remoteMessagingActionHandler: remoteMessagingService.remoteMessagingActionHandler,
                remoteMessagingPixelReporter: remoteMessagingService.pixelReporter,
                remoteMessagingImageLoader: remoteMessagingImageLoader,
                appSettings: appSettings,
                aiChatSettings: aiChatSettings,
                experimentalAIChatManager: ExperimentalAIChatManager(),
                defaultBrowserPromptPresenter: defaultBrowserPromptService.presenter,
                winBackOfferPresenter: winBackOfferService.presenter,
                winBackOfferCoordinator: winBackOfferService.coordinator,
                subscriptionPromoPresenter: subscriptionPromoPresenter,
                subscriptionPromoCoordinator: subscriptionPromoCoordinator,
                subscriptionPromoExistingUserPresenter: subscriptionPromoExistingUserPresenter,
                subscriptionPromoExistingUserCoordinator: subscriptionPromoExistingUserCoordinator,
                userScriptsDependencies: contentBlockingService.userScriptsDependencies,
                omniBarFocuser: omniBarFocuser
            )
        )

        let mobileCustomization = MobileCustomization(
            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore,
            connectionStatusObserver: AppDependencyProvider.shared.connectionObserver,
            isDuckAIEnabled: { aiChatSettings.isAIChatEnabled })

        // MARK: - Main Coordinator Setup
        // Initialize the main coordinator which manages the app's primary view controller
        // This step may take some time due to loading from nibs, etc.

        mainCoordinator = try MainCoordinator(privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager,
                                              syncService: syncService,
                                              contentBlockingService: contentBlockingService,
                                              bookmarksDatabase: configuration.persistentStoresConfiguration.bookmarksDatabase,
                                              remoteMessagingService: remoteMessagingService,
                                              daxDialogs: configuration.onboardingConfiguration.daxDialogs,
                                              reportingService: reportingService,
                                              variantManager: configuration.atbAndVariantConfiguration.variantManager,
                                              subscriptionService: subscriptionService,
                                              voiceSearchHelper: voiceSearchHelper,
                                              featureFlagger: featureFlagger,
                                              contentScopeExperimentManager: contentScopeExperimentsManager,
                                              aiChatSettings: aiChatSettings,
                                              fireproofing: fireproofing,
                                              favicons: favicons,
                                              maliciousSiteProtectionService: maliciousSiteProtectionService,
                                              customConfigurationURLProvider: AppDependencyProvider.shared.configurationURLProvider,
                                              didFinishLaunchingStartTime: isAppLaunchedInBackground ? nil : didFinishLaunchingStartTime,
                                              isAppLaunchedInBackground: isAppLaunchedInBackground,
                                              keyValueStore: appKeyValueFileStoreService.keyValueFilesStore,
                                              systemSettingsPiPTutorialManager: systemSettingsPiPTutorialService.manager,
                                              daxDialogsManager: daxDialogs,
                                              dbpIOSPublicInterface: dbpService.dbpIOSPublicInterface,
                                              launchSourceManager: launchSourceManager,
                                              winBackOfferService: winBackOfferService,
                                              freemiumPIREligibilityChecker: freemiumPIREligibilityChecker,
                                              freemiumPIRDebugSettings: freemiumPIRDebugSettings,
                                              freemiumDBPUserStateManager: dbpService.freemiumDBPUserStateManager,
                                              profileStateManager: dbpService.profileStateManager,
                                              promoCoordinationService: promoCoordinationService,
                                              mobileCustomization: mobileCustomization,
                                              productSurfaceTelemetry: productSurfaceTelemetry,
                                              whatsNewRepository: whatsNewRepository,
                                              sharedSecureVault: configuration.persistentStoresConfiguration.sharedSecureVault,
                                              wideEvent: AppDependencyProvider.shared.wideEvent,
                                              onboardingManager: onboardingManager,
                                              eventHub: eventHubService.eventHub
        )

        // MARK: - UI-Dependent Services Setup
        // Initialize and configure services that depend on UI components

        webExtensionManagerHolder.manager = mainCoordinator.webExtensionManager
        systemSettingsPiPTutorialService.setPresenter(mainCoordinator)
        syncService.presenter = mainCoordinator.controller
        remoteMessagingService.messageNavigator = DefaultMessageNavigator(delegate: mainCoordinator.controller)
        omniBarFocuser.focuser = mainCoordinator.controller

        let inactivityStateStore = InactivityNotificationStateStore(
            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore
        )
        let notificationServiceManager = NotificationServiceManager(
            mainCoordinator: mainCoordinator,
            inactivityStateStore: inactivityStateStore
        )

        let vpnService = VPNService(mainCoordinator: mainCoordinator, notificationServiceManager: notificationServiceManager)
        let inactivityNotificationSchedulerService = InactivityNotificationSchedulerService(
            featureFlagger: featureFlagger,
            notificationServiceManager: notificationServiceManager,
            privacyConfigurationManager: contentBlockingService.common.privacyConfigurationManager,
            stateStore: inactivityStateStore
        )

        winBackOfferService.setURLHandler(mainCoordinator)

        // MARK: - App Services aggregation
        // This object serves as a central hub for app-wide services that:
        // 1. Respond to lifecycle events
        // 2. Persist throughout the app's runtime
        // 3. Provide core functionality across different parts of the app

        services = AppServices(contentBlockingService: contentBlockingService,
                               syncService: syncService,
                               vpnService: vpnService,
                               dbpService: dbpService,
                               autofillService: autofillService,
                               remoteMessagingService: remoteMessagingService,
                               configurationService: configurationService,
                               reportingService: reportingService,
                               subscriptionService: subscriptionService,
                               crashCollectionService: crashCollectionService,
                               launchTimeMetricsService: launchTimeMetricsService,
                               maliciousSiteProtectionService: maliciousSiteProtectionService,
                               statisticsService: statisticsService,
                               keyValueFileStoreService: appKeyValueFileStoreService,
                               defaultBrowserPromptService: defaultBrowserPromptService,
                               winBackOfferService: winBackOfferService,
                               systemSettingsPiPTutorialService: systemSettingsPiPTutorialService,
                               inactivityNotificationSchedulerService: inactivityNotificationSchedulerService,
                               wideEventService: wideEventService,
                               aiChatService: AIChatService(aiChatSettings: aiChatSettings),
                               eventHubService: eventHubService
        )

        // Clean up wide event data at launch
        launchTaskManager.register(task: WideEventLaunchCleanupTask(wideEventService: wideEventService))
        launchTaskManager.register(task: BlockLaunchTask(name: "Initialize PIR Secure Vault") { taskContext in
            Task {
                await dbpService.prepareSecureVaultResourcesAtLaunch()
                taskContext.finish()
            }
        })

        // MARK: - Final Configuration
        // Complete the configuration process and set up the main window

#if DEBUG || ALPHA
        mainCoordinator.controller.automationServer = configuration.finalize(
            reportingService: reportingService,
            mainViewController: mainCoordinator.controller,
            launchTaskManager: launchTaskManager
        )
#else
        _ = configuration.finalize(
            reportingService: reportingService,
            mainViewController: mainCoordinator.controller,
            launchTaskManager: launchTaskManager
        )
#endif

        logAppLaunchTime()

#if DEBUG
        if LaunchOptionsHandler().shouldOpenPIRDashboardForTesting {
            let mainCoordinator = mainCoordinator
            Task { @MainActor in
                mainCoordinator.presentDataBrokerProtectionDashboard()
            }
        }
#endif
        // Keep this init method minimal and think twice before adding anything here.
        // - Use AppConfiguration for one-time setup.
        // - Use a service for functionality that persists throughout the app's lifecycle.
        // More details: https://app.asana.com/0/1202500774821704/1209445353536498/f
        // For a broader overview: https://app.asana.com/0/1202500774821704/1209445353536490/f
    }

    private static func makeNativeStorageHandler(featureFlagger: FeatureFlagger,
                                                 keyValueStore: ThrowingKeyValueStoring) -> DuckAiNativeStorageHandling? {
        guard featureFlagger.isFeatureOn(.aiChatNativeStorage) else { return nil }

        let containerURL: URL
        if featureFlagger.isFeatureOn(.duckAINativeStoragePathMigration) {
            guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            containerURL = appSupportURL.appendingPathComponent(DuckAiNativeStorageHandler.defaultDirectoryName)

            if let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Global.appConfigurationGroupName) {
                let outcome = DuckAiNativeStorageContainerMigration(
                    oldURL: groupContainer.appendingPathComponent(DuckAiNativeStorageHandler.defaultDirectoryName),
                    newURL: containerURL,
                    migrationKey: "com.duckduckgo.duckai.nativeStorage.defaultMigratedFromAppGroup",
                    label: .default,
                    keyValueStore: keyValueStore,
                    pixelFiring: DuckAiNativeStorageContainerMigrationPixelAdapter(),
                    lockedLaunchFixEnabled: featureFlagger.isFeatureOn(.duckAINativeStorageMigrationLockedLaunchFix)
                ).run()
                if outcome == .skip {
                    return nil
                }
            }

            DuckAiNativeStorageContainerMigration.excludeFromBackup(containerURL,
                                                                    label: .default,
                                                                    pixelFiring: DuckAiNativeStorageContainerMigrationPixelAdapter())
        } else {
            // Path migration disabled: keep the legacy App Group container.
            guard let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Global.appConfigurationGroupName) else {
                return nil
            }
            containerURL = groupContainer.appendingPathComponent(DuckAiNativeStorageHandler.defaultDirectoryName)
        }

        let dbURL = containerURL.appendingPathComponent("chats.db")
        if !FileManager.default.fileExists(atPath: dbURL.path) {
            Logger.aiChat.info("[NativeStorage] DB does not exist yet, will be created at: \(dbURL.path)")
        }

        do {
            return try DuckAiNativeStorageHandler(
                .disk(path: containerURL,
                      keyStoreProvider: DuckAiKeyStoreProvider(accessGroup: Global.appConfigurationGroupName),
                      pixelFiring: DuckAiNativeStoragePixelAdapter())
            )
        } catch {
            Logger.aiChat.error("[NativeStorage] Handler init failed: \(error)")
            return nil
        }
    }

    private func logAppLaunchTime() {
        let launchTime = CFAbsoluteTimeGetCurrent() - didFinishLaunchingStartTime
        PixelKit.fire(Pixel.Event.appDidFinishLaunchingTime(time: Pixel.Event.BucketAggregation(number: launchTime)),
                      options: .parameters([PixelParameters.time: String(launchTime)]))
    }

    // MARK: -

    private var appDependencies: AppDependencies {
        .init(
            mainCoordinator: mainCoordinator,
            services: services,
            launchTaskManager: launchTaskManager,
            launchSourceManager: launchSourceManager,
            aiChatSettings: aiChatSettings,
            featureFlagger: featureFlagger,
            voiceSearchHelper: voiceSearchHelper,
            appSettings: appSettings,
            backgroundTaskManager: BackgroundTaskManager(featureFlagger: featureFlagger)
        )
    }

}

extension Launching {

    struct StateContext {

        let didFinishLaunchingStartTime: CFAbsoluteTime
        let appDependencies: AppDependencies

    }

    func makeStateContext() -> StateContext {
        .init(didFinishLaunchingStartTime: didFinishLaunchingStartTime,
              appDependencies: appDependencies)
    }

    func makeConnectedState(window: UIWindow, actionToHandle: AppAction?) -> any ConnectedHandling {
        Connected(stateContext: makeStateContext(), actionToHandle: actionToHandle, window: window,
                  lastBackgroundDateStorage: lastBackgroundDateStorage)
    }

}

struct DuckAiNativeStoragePixelAdapter: DuckAiNativeStoragePixelFiring {

    func fire(_ event: DuckAiNativeStorageEvent) {
        switch event {
        case .initSuccess:
            PixelKit.fire(Pixel.Event.duckAiNativeStorageInitSuccess)
        case .initError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageInitError.withError(error),
                          frequency: .dailyAndStandard)
        case .migrationDone(let key):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageMigrationDoneUnique(key: key), frequency: .legacyInitial)
            PixelKit.fire(Pixel.Event.duckAiNativeStorageMigrationDoneCount(key: key))
        case .migrationDoneBlankKey:
            PixelKit.fire(Pixel.Event.duckAiNativeStorageMigrationDoneBlankCount)
        case .migrationStarted:
            PixelKit.fire(Pixel.Event.duckAiNativeStorageMigrationStarted)
        case .migrationAlreadyDone:
            PixelKit.fire(Pixel.Event.duckAiNativeStorageMigrationAlreadyDone)
        case .migrationError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageMigrationError.withError(error))
        case .settingsPutError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageSettingsPutError.withError(error),
                          frequency: .dailyAndStandard)
        case .settingsGetError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageSettingsGetError.withError(error),
                          frequency: .dailyAndStandard)
        case .settingsDeleteError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageSettingsDeleteError.withError(error),
                          frequency: .dailyAndStandard)
        case .chatPutError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageChatPutError.withError(error),
                          frequency: .dailyAndStandard)
        case .chatGetError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageChatGetError.withError(error),
                          frequency: .dailyAndStandard)
        case .chatDeleteError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageChatDeleteError.withError(error),
                          frequency: .dailyAndStandard)
        case .filePutError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageFilePutError.withError(error),
                          frequency: .dailyAndStandard)
        case .fileGetError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageFileGetError.withError(error),
                          frequency: .dailyAndStandard)
        case .fileListError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageFileListError.withError(error),
                          frequency: .dailyAndStandard)
        case .fileDeleteError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageFileDeleteError.withError(error),
                          frequency: .dailyAndStandard)
        case .lastUsedModelParseError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageLastUsedModelParseError.withError(error),
                          frequency: .dailyAndStandard)
        case .lastUsedReasoningModeParseError(let error):
            PixelKit.fire(Pixel.Event.duckAiNativeStorageLastUsedReasoningModeParseError.withError(error),
                          frequency: .dailyAndStandard)
        }
    }
}
