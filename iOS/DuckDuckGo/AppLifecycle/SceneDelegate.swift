//
//  SceneDelegate.swift
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

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var appStateMachine: AppStateMachine {
        (UIApplication.shared.delegate as! AppDelegate).appStateMachine
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            appStateMachine.handle(.willConnectToWindow(window: window))
        }

        if let shortcutItem = connectionOptions.shortcutItem {
            appStateMachine.handle(.handleShortcutItem(shortcutItem))
        } else if let urlContext = connectionOptions.urlContexts.first {
            // We should be supporting opening multiple URLs at once
            appStateMachine.handle(.openURL(urlContext.url))
        }

    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    /// See: `Foreground.swift` -> `onTransition()`
    func sceneDidBecomeActive(_ scene: UIScene) {
        appStateMachine.handle(.didBecomeActive)
    }

    /// See: `Foreground.swift` -> `willLeave()`
    func sceneWillResignActive(_ scene: UIScene) {
        appStateMachine.handle(.willResignActive)
    }

    /// See: `Background.swift` -> `willLeave()`
    func sceneWillEnterForeground(_ scene: UIScene) {
        appStateMachine.handle(.willEnterForeground)
    }

    /// See: `Background.swift` -> `onTransition()`
    func sceneDidEnterBackground(_ scene: UIScene) {
        appStateMachine.handle(.didEnterBackground)
    }

    func scene(_ scene: UIScene, willContinueUserActivity userActivity: NSUserActivity) -> Bool {
        true
    }

    /// See: `LaunchActionHandler.swift` -> `openURL(_:)`
    func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        // We should be supporting opening multiple URLs at once
        if let urlContext = urlContexts.first {
            appStateMachine.handle(.openURL(urlContext.url))
        }
    }

    /// See: `LaunchActionHandler.swift` -> `handleShortcutItem(_:)`
    @MainActor
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        appStateMachine.handle(.handleShortcutItem(shortcutItem))
        return true
    }

}
