//
//  Connected.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Core
import Persistence
import FeatureFlags_iOS

/// Represents the state where the scene has been connected and is ready for initial setup.
/// - Usage:
///   - This state is typically associated with the `scene(_:willConnectTo:options:)` method in `SceneDelegate`.
///   - The app transitions to this state after launching, when the scene is first created and attached to the app session.
///   - During this state, initial scene-specific configurations and UI setups should be performed.
///   - As part of this state, the `MainViewController` is set as the `rootViewController` of the scene's `UIWindow`.
/// - Transitions:
///   - `Foreground`: Standard transition when the app completes its launch process and becomes active.
///   - `Background`: Occurs when the app is launched but transitions directly to the background, e.g:
///     - The app is protected by a FaceID lock mechanism (introduced in iOS 18.0). If the user opens the app
///       but does not authenticate and then leaves.
///     - The app is launched by the system for background execution but does not immediately become active.
/// - Notes:
///   - Avoid performing heavy or blocking operations during this phase to ensure smooth app startup.
@MainActor
struct Connected: ConnectedHandling {

    typealias Dependencies = SceneDependencies

    let appDependencies: AppDependencies
    let sceneDependencies: SceneDependencies
    let actionToHandle: AppAction?
    /// Draws the first screen at connect, or on the first foreground when that is deferred.
    private var initialView: InitialViewLoader
    /// Handed to the first foreground only. Only whether the page was drawn is passed on, not the outcome.
    private var drewIdleReturnNewTabPage: Bool { initialView.drewIdleReturnNewTabPage }
    private let lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>

    init(stateContext: Launching.StateContext, actionToHandle: AppAction?, window: UIWindow,
         lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>) {
        appDependencies = stateContext.appDependencies
        self.actionToHandle = actionToHandle
        self.lastBackgroundDateStorage = lastBackgroundDateStorage

        let mainCoordinator = appDependencies.mainCoordinator
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        isFloatingUIFeatureEnabledForCurrentLaunch: mainCoordinator.isFloatingUIFeatureEnabledForCurrentLaunch,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        aiChatAddressBarExperience: mainCoordinator.controller.aiChatAddressBarExperience,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClear = AutoClear(worker: mainCoordinator.controller.fireExecutor)
        let autoClearService = AutoClearService(autoClear: autoClear,
                                                overlayWindowManager: overlayWindowManager,
                                                aiChatSyncCleaner: appDependencies.services.syncService.aiChatSyncCleaner)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)

        let launchTaskManager = appDependencies.launchTaskManager
        launchTaskManager.register(task: ClearInteractionStateTask(autoClearService: autoClearService,
                                                                   interactionStateSource: mainCoordinator.interactionStateSource,
                                                                   tabManager: mainCoordinator.tabManager))
        initialView = Self.makeInitialViewLoader(appDependencies: appDependencies)
        sceneDependencies = SceneDependencies(screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)

        configure(window, with: mainCoordinator)
    }

    /// Temporary logic to handle cases where the window is disconnected and later reconnected.
    /// Ensures the main coordinator’s main view controller is reattached to the new window.
    /// This unfortunately happens for iOS 16 and lower. Remove this once we drop support for it.
    init(stateContext: Foreground.StateContext, actionToHandle: AppAction?, window: UIWindow,
         lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>) {
        appDependencies = stateContext.appDependencies
        initialView = Self.makeInitialViewLoader(appDependencies: stateContext.appDependencies, isReattachingWindow: true)
        self.actionToHandle = actionToHandle
        self.lastBackgroundDateStorage = lastBackgroundDateStorage

        let mainCoordinator = appDependencies.mainCoordinator
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        isFloatingUIFeatureEnabledForCurrentLaunch: mainCoordinator.isFloatingUIFeatureEnabledForCurrentLaunch,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        aiChatAddressBarExperience: mainCoordinator.controller.aiChatAddressBarExperience,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClear = AutoClear(worker: mainCoordinator.controller.fireExecutor)
        let autoClearService = AutoClearService(autoClear: autoClear,
                                                overlayWindowManager: overlayWindowManager,
                                                aiChatSyncCleaner: appDependencies.services.syncService.aiChatSyncCleaner)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)
        sceneDependencies = SceneDependencies(screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)
        configure(window, with: mainCoordinator)
    }

    /// Temporary logic to handle cases where the window is disconnected and later reconnected.
    /// Ensures the main coordinator’s main view controller is reattached to the new window.
    /// This unfortunately happens for iOS 16 and lower. Remove this once we drop support for it.
    init(stateContext: Background.StateContext, actionToHandle: AppAction?, window: UIWindow,
         lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>) {
        appDependencies = stateContext.appDependencies
        initialView = Self.makeInitialViewLoader(appDependencies: stateContext.appDependencies, isReattachingWindow: true)
        self.actionToHandle = actionToHandle
        self.lastBackgroundDateStorage = lastBackgroundDateStorage

        let mainCoordinator = appDependencies.mainCoordinator
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        isFloatingUIFeatureEnabledForCurrentLaunch: mainCoordinator.isFloatingUIFeatureEnabledForCurrentLaunch,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        aiChatAddressBarExperience: mainCoordinator.controller.aiChatAddressBarExperience,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClear = AutoClear(worker: mainCoordinator.controller.fireExecutor)
        let autoClearService = AutoClearService(autoClear: autoClear,
                                                overlayWindowManager: overlayWindowManager,
                                                aiChatSyncCleaner: appDependencies.services.syncService.aiChatSyncCleaner)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)
        sceneDependencies = SceneDependencies(screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)
        configure(window, with: mainCoordinator)
    }

    private mutating func configure(_ window: UIWindow, with mainCoordinator: MainCoordinator) {
        ThemeManager.shared.updateUserInterfaceStyle(window: window)
        window.rootViewController = mainCoordinator.controller
        // Before the window shows, so the first frame is this screen.
        initialView.loadAtConnection(hasLaunchAction: actionToHandle != nil)
        sceneDependencies.authenticationService.suspend()
        window.makeKeyAndVisible()
        window.accessibilityIdentifier = "Browser.Window.Main"
    }

    /// Makes the loader for this scene's first screen.
    private static func makeInitialViewLoader(appDependencies: AppDependencies, isReattachingWindow: Bool = false) -> InitialViewLoader {
        let mainCoordinator = appDependencies.mainCoordinator
        // Scene connection can't tell a user launch from a background one, so a deferred first screen
        // always waits for the first foreground.
        let defersUntilForeground = !isReattachingWindow
            && appDependencies.featureFlagger.isFeatureOn(.deferInitialViewUntilForeground)
        return InitialViewLoader(
            defersUntilForeground: defersUntilForeground,
            drawsIdleReturnNewTabPage: { hasLaunchAction in
                guard !isReattachingWindow else { return false }
                return appDependencies.idleReturnEvaluator.evaluateReturn()
                    .drawsNewTabPageAtLaunch(isFeatureOn: appDependencies.featureFlagger.isFeatureOn(.idleReturnNewTabPageAtLaunch),
                                             hasLaunchAction: hasLaunchAction,
                                             isAppLockEnabled: PrivacyUserDefaults().authenticationEnabled,
                                             hasPageToReplace: mainCoordinator.tabManager.currentTabsModel.currentTab?.link != nil)
            },
            start: { mainCoordinator.start(drawsIdleReturnNewTabPage: $0) })
    }

}

extension Connected {

    struct StateContext {

        let appDependencies: AppDependencies
        let sceneDependencies: SceneDependencies
        let drewIdleReturnNewTabPage: Bool
        /// Set when the first screen still waits for a foreground.
        let pendingInitialView: InitialViewLoader?

    }

    func makeStateContext(sceneDependencies: SceneDependencies) -> StateContext {
        .init(appDependencies: appDependencies,
              sceneDependencies: sceneDependencies,
              drewIdleReturnNewTabPage: drewIdleReturnNewTabPage,
              pendingInitialView: initialView.isPending ? initialView : nil)
    }

    func loadInitialViewIfPending(actionToHandle: AppAction?) -> any ConnectedHandling {
        var connected = self
        connected.initialView.loadIfPending(hasLaunchAction: actionToHandle != nil)
        return connected
    }

    func makeBackgroundState() -> any BackgroundHandling {
        Background(stateContext: makeStateContext(sceneDependencies: sceneDependencies),
                   lastBackgroundDateStorage: lastBackgroundDateStorage)
    }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        Foreground(stateContext: makeStateContext(sceneDependencies: sceneDependencies),
                   actionToHandle: actionToHandle,
                   lastBackgroundDateStorage: lastBackgroundDateStorage)
    }

}
