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
import PixelKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private lazy var lifecycleInstrumentation = SceneLifecycleInstrumentation()

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
        lifecycleInstrumentation.sceneDidDisconnect(in: appStateMachine.currentState)
    }

    /// See: `Foreground.swift` -> `onTransition()`
    func sceneDidBecomeActive(_ scene: UIScene) {
        appStateMachine.handle(.didBecomeActive)
        lifecycleInstrumentation.sceneDidBecomeActive(windows: (scene as? UIWindowScene)?.windows ?? [], in: appStateMachine.currentState)
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

enum SceneLifecyclePixel: PixelKit.Event {

    case activeWithoutMainUI
    case sceneDidDisconnect(appState: String)

    var name: String {
        switch self {
        case .activeWithoutMainUI: return "app-lifecycle_active-without-main-ui"
        case .sceneDidDisconnect: return "app-lifecycle_scene-did-disconnect"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .activeWithoutMainUI: return nil
        case .sceneDidDisconnect(let appState): return ["state": appState]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
    var namePrefix: PixelKitNamePrefix { .none }

}

/// Instrumentation for the black screen after a scene reconnects during launch.
@MainActor
struct SceneLifecycleInstrumentation {

    private let pixelFiring: (any PixelKitFiring)?
    private let isAppUI: (UIViewController?) -> Bool

    /// App UI is the main UI or one of the overlays shown over it: the authentication screen hides the main window
    /// while the app is locked, and the blank snapshot covers it while data is cleared.
    init(pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         isAppUI: @escaping (UIViewController?) -> Bool = {
             $0 is MainViewController || $0 is AuthenticationViewController || $0 is BlankSnapshotViewController
         }) {
        self.pixelFiring = pixelFiring
        self.isAppUI = isAppUI
    }

    /// The scene became active but none of its visible windows shows app UI, so the user sees a black screen.
    /// Skipped while terminating (the critical alert has its own root) and in the test host, where the main UI is not expected.
    func sceneDidBecomeActive(windows: [UIWindow], in state: AppState) {
        switch state {
        case .terminating, .simulated: return
        case .initializing, .launching, .connected, .foreground, .background: break
        }
        guard !windows.contains(where: { !$0.isHidden && isAppUI($0.rootViewController) }) else { return }
        pixelFiring?.fire(SceneLifecyclePixel.activeWithoutMainUI, frequency: .daily)
    }

    func sceneDidDisconnect(in state: AppState) {
        pixelFiring?.fire(SceneLifecyclePixel.sceneDidDisconnect(appState: state.name), frequency: .dailyAndCount)
    }

}
