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
import Common

@UIApplicationMain class AppDelegate: UIResponder, UIApplicationDelegate {

    let appStateMachine: AppStateMachine = AppStateMachine(initialState: .initializing(Initializing()))

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        // UIKit can request menus before normal launch setup or during simulated launches.
        // Access the shared provider only after launch setup has initialized it, even when the menu flag is enabled.
        switch appStateMachine.currentState {
        case .launching, .connected, .foreground, .background:
            if let service = AppDependencyProvider.shared.mainMenuService {
                service.buildMenu(with: builder)
                return
            }
        case .initializing, .simulated, .terminating:
            break
        }
        MainMenuBuilder().build(MainMenuSpec(isEnabled: false), with: builder)
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    /// See: `Launching.swift`
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // SwiftUI Previews run without the app group container, so skip app initialization to avoid crashing.
        guard AppVersion.runType != .xcPreviews else { return true }

        let isTesting: Bool = ProcessInfo().arguments.contains("testing")
        appStateMachine.handle(.didFinishLaunching(isTesting: isTesting))
        return true
    }

}
