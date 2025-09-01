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

import Core
import UIKit

import BrowserServicesKit

/// Represents the transient state where the app is being prepared for user interaction after being launched by the system.
/// - Usage:
///   - This state is typically associated with the `application(_:didFinishLaunchingWithOptions:)` method.
///   - It is responsible for performing the app's initial setup, including configuring dependencies and preparing the UI.
///   - As part of this state, the `MainViewController` is created and set as the `rootViewController` of the app's primary `UIWindow`.
/// - Transitions:
///   - `Foreground`: Standard transition when the app completes its launch process and becomes active.
///   - `Background`: Occurs when the app is launched but transitions directly to the background, e.g:
///     - The app is protected by a FaceID lock mechanism (introduced in iOS 18.0). If the user opens the app
///       but does not authenticate and then leaves.
///     - The app is launched by the system for background execution but does not immediately become active.
/// - Notes:
///   - Avoid performing heavy or blocking operations during this phase to ensure smooth app startup.
@MainActor
struct Launching: LaunchingHandling {

    private let appSettings = AppDependencyProvider.shared.appSettings
    private let voiceSearchHelper = VoiceSearchHelper()
    private let fireproofing = UserDefaultsFireproofing.xshared
    private let featureFlagger = AppDependencyProvider.shared.featureFlagger
    private let contentScopeExperimentsManager = AppDependencyProvider.shared.contentScopeExperimentsManager
    private let aiChatSettings: AIChatSettings
    private let privacyConfigurationManager = ContentBlocking.shared.privacyConfigurationManager

    private let didFinishLaunchingStartTime = CFAbsoluteTimeGetCurrent()
    private let isAppLaunchedInBackground = UIApplication.shared.applicationState == .background
    private let window: UIWindow = UIWindow(frame: UIScreen.main.bounds)

    private let configuration = AppConfiguration()
    private let services: AppServices
    private let mainCoordinator: MainCoordinator
    private let launchTaskManager = LaunchTaskManager()

    // MARK: - Handle application(_:didFinishLaunchingWithOptions:) logic here

    init() throws {
        Logger.lifecycle.info("Launching: \(#function)")

        // MARK: - Application Setup
        // Handles one-time application setup during launch

        try configuration.start()

        // MARK: - Service Initialization
        // Create and initialize core services
        // These services are instantiated early in the app lifecycle for two main reasons:
        // 1. To begin their essential work immediately, without waiting for UI or other components
        // 2. To potentially complete their tasks before the app becomes visible to the user
        // This approach aims to optimize performance and ensure critical functionalities are ready ASAP

        let appKeyValueFileStoreService = try AppKeyValueFileStoreService()
        let autofillService = AutofillService()

        let dbpService = DBPService(appDependencies: AppDependencyProvider.shared)
        let configurationService = RemoteConfigurationService()
        let crashCollectionService = CrashCollectionService()
        let statisticsService = StatisticsService()
        let reportingService = ReportingService(fireproofing: fireproofing, featureFlagging: featureFlagger)
        let syncService = SyncService(bookmarksDatabase: configuration.persistentStoresConfiguration.bookmarksDatabase,
                                      keyValueStore: appKeyValueFileStoreService.keyValueFilesStore)
        reportingService.syncService = syncService
        autofillService.syncService = syncService
        let remoteMessagingService = RemoteMessagingService(bookmarksDatabase: configuration.persistentStoresConfiguration.bookmarksDatabase,
                                                            database: configuration.persistentStoresConfiguration.database,
                                                            appSettings: appSettings,
                                                            internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
                                                            configurationStore: AppDependencyProvider.shared.configurationStore,
                                                            privacyConfigurationManager: privacyConfigurationManager,
                                                            configurationURLProvider: AppDependencyProvider.shared.configurationURLProvider)
        let subscriptionService = SubscriptionService(privacyConfigurationManager: privacyConfigurationManager, featureFlagger: featureFlagger)
        let maliciousSiteProtectionService = MaliciousSiteProtectionService(featureFlagger: featureFlagger)
        let systemSettingsPiPTutorialService = SystemSettingsPiPTutorialService(featureFlagger: featureFlagger)
        let widePixelService = WidePixelService(
            widePixel: AppDependencyProvider.shared.widePixel,
            featureFlagger: featureFlagger,
            subscriptionBridge: AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge
        )

        let daxDialogs = configuration.onboardingConfiguration.daxDialogs

        // Service to display the Default Browser prompt.
        let defaultBrowserPromptService = DefaultBrowserPromptService(
            featureFlagger: featureFlagger,
            privacyConfigManager: privacyConfigurationManager,
            keyValueFilesStore: appKeyValueFileStoreService.keyValueFilesStore,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialService.manager,
            isOnboardingCompletedProvider: { !daxDialogs.isEnabled }
        )

        // Has to be intialised after configuration.start in case values need to be migrated
        aiChatSettings = AIChatSettings()

        // MARK: - Main Coordinator Setup
        // Initialize the main coordinator which manages the app's primary view controller
        // This step may take some time due to loading from nibs, etc.

        mainCoordinator = try MainCoordinator(syncService: syncService,
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
                                              maliciousSiteProtectionService: maliciousSiteProtectionService,
                                              customConfigurationURLProvider: AppDependencyProvider.shared.configurationURLProvider,
                                              didFinishLaunchingStartTime: isAppLaunchedInBackground ? nil : didFinishLaunchingStartTime,
                                              keyValueStore: appKeyValueFileStoreService.keyValueFilesStore,
                                              defaultBrowserPromptPresenter: defaultBrowserPromptService.presenter,
                                              systemSettingsPiPTutorialManager: systemSettingsPiPTutorialService.manager,
                                              daxDialogsManager: daxDialogs)

        // MARK: - UI-Dependent Services Setup
        // Initialize and configure services that depend on UI components

        systemSettingsPiPTutorialService.setPresenter(mainCoordinator)
        syncService.presenter = mainCoordinator.controller
        let vpnService = VPNService(mainCoordinator: mainCoordinator)
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appSettings,
                                                        voiceSearchHelper: voiceSearchHelper,
                                                        featureFlagger: featureFlagger,
                                                        aiChatSettings: aiChatSettings)
        let autoClearService = AutoClearService(autoClear: AutoClear(worker: mainCoordinator.controller), overlayWindowManager: overlayWindowManager)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)

        // MARK: - App Services aggregation
        // This object serves as a central hub for app-wide services that:
        // 1. Respond to lifecycle events
        // 2. Persist throughout the app's runtime
        // 3. Provide core functionality across different parts of the app

        services = AppServices(screenshotService: screenshotService,
                               authenticationService: authenticationService,
                               syncService: syncService,
                               vpnService: vpnService,
                               dbpService: dbpService,
                               autofillService: autofillService,
                               remoteMessagingService: remoteMessagingService,
                               configurationService: configurationService,
                               autoClearService: autoClearService,
                               reportingService: reportingService,
                               subscriptionService: subscriptionService,
                               crashCollectionService: crashCollectionService,
                               maliciousSiteProtectionService: maliciousSiteProtectionService,
                               statisticsService: statisticsService,
                               keyValueFileStoreService: appKeyValueFileStoreService,
                               defaultBrowserPromptService: defaultBrowserPromptService,
                               systemSettingsPiPTutorialService: systemSettingsPiPTutorialService,
                               widePixelService: widePixelService
        )

        // Register background tasks that run after app is ready
        launchTaskManager.register(task: ClearInteractionStateTask(autoClearService: autoClearService,
                                                                   interactionStateSource: mainCoordinator.interactionStateSource,
                                                                   tabManager: mainCoordinator.tabManager))
        
        // Clean up wide pixel data at launch
        launchTaskManager.register(task: WidePixelLaunchCleanupTask(widePixelService: widePixelService))

        // MARK: - Final Configuration
        // Complete the configuration process and set up the main window

        configuration.finalize(
            reportingService: reportingService,
            mainViewController: mainCoordinator.controller,
            launchTaskManager: launchTaskManager,
            keyValueStore: appKeyValueFileStoreService.keyValueFilesStore
        )

        setupWindow()
        logAppLaunchTime()

        // Keep this init method minimal and think twice before adding anything here.
        // - Use AppConfiguration for one-time setup.
        // - Use a service for functionality that persists throughout the app's lifecycle.
        // More details: https://app.asana.com/0/1202500774821704/1209445353536498/f
        // For a broader overview: https://app.asana.com/0/1202500774821704/1209445353536490/f
    }

    private func setupWindow() {
        ThemeManager.shared.updateUserInterfaceStyle(window: window)
        window.rootViewController = mainCoordinator.controller
        UIApplication.shared.setWindow(window)
        window.makeKeyAndVisible()
        mainCoordinator.start()
    }

    private func logAppLaunchTime() {
        let launchTime = CFAbsoluteTimeGetCurrent() - didFinishLaunchingStartTime
        Pixel.fire(pixel: .appDidFinishLaunchingTime(time: Pixel.Event.BucketAggregation(number: launchTime)),
                   withAdditionalParameters: [PixelParameters.time: String(launchTime)])
    }

    // MARK: -

    private var appDependencies: AppDependencies {
        .init(
            mainCoordinator: mainCoordinator,
            services: services,
            launchTaskManager: launchTaskManager
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

    func makeBackgroundState() -> any BackgroundHandling {
        Background(stateContext: makeStateContext())
    }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        Foreground(stateContext: makeStateContext(), actionToHandle: actionToHandle)
    }

}
