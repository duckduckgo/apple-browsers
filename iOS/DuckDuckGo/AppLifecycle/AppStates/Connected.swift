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
    let didFinishLaunchingStartTime: CFAbsoluteTime

    init(stateContext: Launching.StateContext, actionToHandle: AppAction?, window: UIWindow) {
        appDependencies = stateContext.appDependencies
        didFinishLaunchingStartTime = stateContext.didFinishLaunchingStartTime
        self.actionToHandle = actionToHandle

        let mainCoordinator = appDependencies.mainCoordinator
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClearService = AutoClearService(autoClear: AutoClear(worker: mainCoordinator.controller),
                                                overlayWindowManager: overlayWindowManager,
                                                keyValueStore: appDependencies.services.keyValueFileStoreService.keyValueFilesStore)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)

        let launchTaskManager = appDependencies.launchTaskManager
        launchTaskManager.register(task: ClearInteractionStateTask(autoClearService: autoClearService,
                                                                   interactionStateSource: mainCoordinator.interactionStateSource,
                                                                   tabManager: mainCoordinator.tabManager))
        sceneDependencies = SceneDependencies(screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)

        configure(window, with: mainCoordinator)
    }

    /// Temporary logic to handle cases where the window is disconnected and later reconnected.
    /// Ensures the main coordinator’s main view controller is reattached to the new window.
    /// This unfortunately happens for iOS 16 and lower. Remove this once we drop support for it.
    init(stateContext: Foreground.StateContext, actionToHandle: AppAction?, window: UIWindow) {
        appDependencies = stateContext.appDependencies
        didFinishLaunchingStartTime = 0
        self.actionToHandle = actionToHandle

        let mainCoordinator = appDependencies.mainCoordinator
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClearService = AutoClearService(autoClear: AutoClear(worker: mainCoordinator.controller),
                                                overlayWindowManager: overlayWindowManager,
                                                keyValueStore: appDependencies.services.keyValueFileStoreService.keyValueFilesStore)
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
    init(stateContext: Background.StateContext, actionToHandle: AppAction?, window: UIWindow) {
        appDependencies = stateContext.appDependencies
        didFinishLaunchingStartTime = 0
        self.actionToHandle = actionToHandle

        let mainCoordinator = appDependencies.mainCoordinator
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClearService = AutoClearService(autoClear: AutoClear(worker: mainCoordinator.controller),
                                                overlayWindowManager: overlayWindowManager,
                                                keyValueStore: appDependencies.services.keyValueFileStoreService.keyValueFilesStore)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)
        sceneDependencies = SceneDependencies(screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)
        configure(window, with: mainCoordinator)
    }

    private func configure(_ window: UIWindow, with mainCoordinator: MainCoordinator) {
        ThemeManager.shared.updateUserInterfaceStyle(window: window)
        window.rootViewController = mainCoordinator.controller
        window.makeKeyAndVisible()
        mainCoordinator.start()
    }

}

extension Connected {

    struct StateContext {

        let didFinishLaunchingStartTime: CFAbsoluteTime
        let appDependencies: AppDependencies
        let sceneDependencies: SceneDependencies

    }

    func makeStateContext(sceneDependencies: SceneDependencies) -> StateContext {
        .init(didFinishLaunchingStartTime: didFinishLaunchingStartTime,
              appDependencies: appDependencies,
              sceneDependencies: sceneDependencies)
    }

    func makeBackgroundState() -> any BackgroundHandling {
        Background(stateContext: makeStateContext(sceneDependencies: sceneDependencies))
    }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        Foreground(stateContext: makeStateContext(sceneDependencies: sceneDependencies),
                   actionToHandle: actionToHandle)
    }

}
