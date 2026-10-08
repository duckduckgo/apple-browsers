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
import Core

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var appStateMachine: AppStateMachine {
        // swiftlint:disable:next force_cast
        (UIApplication.shared.delegate as! AppDelegate).appStateMachine
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            self.window = window
            window.layer.speed = AppUserDefaults().slowAnimationsEnabled ? AppUserDefaults.slowAnimationsLayerSpeed : 1.0
            appStateMachine.handle(.willConnectToWindow(window: window))
#if DEBUG
            if SceneReconnectRepro.mode == .connected {
                simulateSecondWindowConnect(in: windowScene, replacing: window)
            }
#endif
        }

        if let shortcutItem = connectionOptions.shortcutItem {
            appStateMachine.handle(.handleShortcutItem(shortcutItem))
        } else if let urlContext = connectionOptions.urlContexts.first {
            // We should be supporting opening multiple URLs at once
            appStateMachine.handle(.openURL(urlContext.url))
        } else if let userActivity = connectionOptions.userActivities.first {
            appStateMachine.handle(.handleUserActivity(userActivity))
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        /// This should never be triggered in our single window configuration unless the user explicitly terminates the app.
        /// To support recovery in such cases, we temporarily allow transitions from `Foreground` and `Background`
        /// back to `Connected`, where:
        /// - The main view controller is reattached to the new window.
        /// - Services depending on the previous window are recreated.
        ///
        /// A tracking pixel is sent on consecutive reconnects to verify that this scenario occurs in practice.
        ///
        /// Update: On iOS 17 and later, this behaves as expected.
        /// However, on iOS 16 and below, we've confirmed that a connected scene *can* unexpectedly disconnect and later reconnect.
        /// Because of this, the recovery path must remain in place for older OS versions.
    }

    /// See: `Foreground.swift` -> `onTransition()`
    func sceneDidBecomeActive(_ scene: UIScene) {
        appStateMachine.handle(.didBecomeActive)
#if DEBUG
        if SceneReconnectRepro.mode == .foreground, !SceneReconnectRepro.didFire,
           let windowScene = scene as? UIWindowScene, let window {
            SceneReconnectRepro.didFire = true
            // Simulated event timeline for the repro, not a timing workaround.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.simulateSecondWindowConnect(in: windowScene, replacing: window)
            }
        }
#endif
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

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        appStateMachine.handle(.handleUserActivity(userActivity))
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

    /// Unified style exposes layout regions so browser chrome can share the window controls row.
    @available(iOS 26.0, *)
    func preferredWindowingControlStyle(for windowScene: UIWindowScene) -> UIWindowScene.WindowingControlStyle {
        WindowControlsRowLayout.isEnabled() ? .unified : .automatic
    }

}

#if DEBUG
/// Repro harness: `-sceneReconnectRepro connected|foreground` launch argument.
enum SceneReconnectRepro: String {
    case connected, foreground

    static let mode = UserDefaults.standard.string(forKey: "sceneReconnectRepro").flatMap(SceneReconnectRepro.init)
    static var didFire = false
}

extension SceneDelegate {

    /// Mimics iOS handing over a new window for the scene; the old window is hidden as if its scene went away.
    func simulateSecondWindowConnect(in windowScene: UIWindowScene, replacing oldWindow: UIWindow) {
        Logger.lifecycle.debug("[SceneRepro] second willConnectToWindow, mode=\(String(describing: SceneReconnectRepro.mode), privacy: .public)")
        oldWindow.isHidden = true
        let newWindow = UIWindow(windowScene: windowScene)
        window = newWindow
        appStateMachine.handle(.willConnectToWindow(window: newWindow))
        Logger.lifecycle.debug("[SceneRepro] after: newWindow.root=\(String(describing: newWindow.rootViewController), privacy: .public) isKey=\(newWindow.isKeyWindow, privacy: .public) hidden=\(newWindow.isHidden, privacy: .public)")
    }
}
#endif
