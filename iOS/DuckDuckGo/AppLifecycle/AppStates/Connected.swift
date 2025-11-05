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

@MainActor
struct Connected: ConnectedHandling {

    typealias Dependencies = SceneDependencies

    let appDependencies: AppDependencies
    let sceneDependencies: SceneDependencies
    let didFinishLaunchingStartTime: CFAbsoluteTime

    init(stateContext: Launching.StateContext, actionToHandle: AppAction?, window: UIWindow) {
        appDependencies = stateContext.appDependencies
        didFinishLaunchingStartTime = stateContext.didFinishLaunchingStartTime
        let mainCoordinator = appDependencies.mainCoordinator
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        aiChatSettings: appDependencies.aiChatSettings)
        let autoClearService = AutoClearService(autoClear: AutoClear(worker: mainCoordinator.controller), overlayWindowManager: overlayWindowManager)
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
        logAppLaunchTime()
    }

    private func configure(_ window: UIWindow, with mainCoordinator: MainCoordinator) { ThemeManager.shared.updateUserInterfaceStyle(window: window)
        window.rootViewController = mainCoordinator.controller
        window.makeKeyAndVisible()
        mainCoordinator.start()
    }

    private func logAppLaunchTime() {
        let launchTime = CFAbsoluteTimeGetCurrent() - didFinishLaunchingStartTime
        Pixel.fire(pixel: .appDidFinishLaunchingTime(time: Pixel.Event.BucketAggregation(number: launchTime)),
                   withAdditionalParameters: [PixelParameters.time: String(launchTime)])
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
