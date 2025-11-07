//
//  AppDelegate.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

// ┌─────────────────────────────────────────────────────────────────────────────────────┐
// │ 🚨 TO DISABLE SCENES IN EMERGENCY:                                                  │
// │ 1. Change `#if true` to `#if false` below to exclude these methods from compilation │
// │ 2. Info.plist → Remove UIApplicationSceneManifest key                               │
// └─────────────────────────────────────────────────────────────────────────────────────┘

@UIApplicationMain class AppDelegate: UIResponder, UIApplicationDelegate {

    let appStateMachine: AppStateMachine = AppStateMachine(initialState: .initializing(Initializing()))

#if true
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
#endif

    @available(*, deprecated, message: "This var should not be used. window is going to be part of SceneDelegate")
    var window: UIWindow?

    /// See: `Launching.swift`
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let isTesting: Bool = ProcessInfo().arguments.contains("testing")
        appStateMachine.handle(.didFinishLaunching(isTesting: isTesting))
        if !Bundle.main.supportsScenes {
            let window = UIWindow(frame: UIScreen.main.bounds)
            self.window = window
            appStateMachine.handle(.willConnectToWindow(window: window))
        }
        return true
    }

    /// See: `Foreground.swift` -> `onTransition()`
    func applicationDidBecomeActive(_ application: UIApplication) {
        appStateMachine.handle(.didBecomeActive)
    }

    /// See: `Foreground.swift` -> `willLeave()`
    func applicationWillResignActive(_ application: UIApplication) {
        appStateMachine.handle(.willResignActive)
    }

    /// See: `Background.swift` -> `willLeave()`
    func applicationWillEnterForeground(_ application: UIApplication) {
        appStateMachine.handle(.willEnterForeground)
    }

    /// See: `Background.swift` -> `onTransition()`
    func applicationDidEnterBackground(_ application: UIApplication) {
        appStateMachine.handle(.didEnterBackground)
    }

    /// See: `LaunchActionHandler.swift` -> `handleShortcutItem(_:)`
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        appStateMachine.handle(.handleShortcutItem(shortcutItem))
    }

    /// See: `LaunchActionHandler.swift` -> `openURL(_:)`
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        appStateMachine.handle(.openURL(url))
        return true
    }

    func application(_ application: UIApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        true
    }

    // MARK: - Debug
    /// These are public to allow access via Debug menu. Otherwise they shouldn't be called from outside.
    /// Avoid abusing this pattern. Inject dependencies where needed instead of relying on global access.
    var debugSubscriptionDataReporter: SubscriptionDataReporting? {
        if case .foreground(let foregroundHandling) = appStateMachine.currentState {
            return (foregroundHandling as? Foreground)?.services.reportingService.subscriptionDataReporter
        }
        return nil
    }

    func debugRefreshRemoteMessages() {
        if case .foreground(let foregroundHandling) = appStateMachine.currentState {
            (foregroundHandling as? Foreground)?.services.remoteMessagingService.refreshRemoteMessages()
        }
    }

}

extension Bundle {

    var supportsScenes: Bool {
        guard let infoDict = self.infoDictionary else { return false }
        guard infoDict["UIApplicationSceneManifest"] is [String: Any] else {
            return false
        }
        return true
    }

}
