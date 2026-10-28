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

import Combine
import UIKit
import Common
import PrivacyConfig
import Persistence

@UIApplicationMain class AppDelegate: UIResponder, UIApplicationDelegate {

    let appStateMachine: AppStateMachine = AppStateMachine(initialState: .initializing(Initializing()))

    private var mainMenuController: MainMenuController?
    private var mainMenuBookmarks: MainMenuBookmarks?
    private var mainMenuChatObservation: AnyCancellable?
    private var mainMenuChatHistory: (@escaping ([MainMenuSpec.Menu]) -> Void) -> Void = { $0([]) }

    func configureMainMenu(featureFlagger: FeatureFlagger, voiceSearchHelper: VoiceSearchHelperProtocol,
                           fireModeCapability: FireModeCapable, bookmarksDatabase: CoreDataDatabase, appSettings: AppSettings,
                           mainViewController: MainViewController) {
        let bookmarks = MainMenuBookmarks(database: bookmarksDatabase, appSettings: appSettings)
        mainMenuBookmarks = bookmarks
        mainMenuChatHistory = { [weak mainViewController] completion in
            guard let mainViewController else { completion([]); return }
            mainViewController.loadMainMenuChats(completion: completion)
        }
        mainMenuController = MainMenuController(featureFlagger: featureFlagger, contextProvider: { [weak self, weak mainViewController] in
            guard let self, let mainViewController else { return .init() }
            if mainViewController.menuNativeChatsAvailable, mainMenuChatObservation == nil {
                mainMenuChatObservation = mainViewController.mainMenuAIChats.updatesPublisher
                    .sink { [weak self] in self?.mainMenuController?.requestRebuild() }
            } else if !mainViewController.menuNativeChatsAvailable {
                mainMenuChatObservation = nil
            }
            return .init(voiceSearchEnabled: voiceSearchHelper.isVoiceSearchEnabled, fireModeEnabled: fireModeCapability.isFireModeEnabled,
                  favorites: bookmarks.favorites, aiChatEnabled: mainViewController.aiChatSettings.isAIChatEnabled,
                  nativeChatsAvailable: mainViewController.menuNativeChatsAvailable)
        }, bookmarksDatabase: bookmarksDatabase)
        mainMenuController?.requestRebuild()
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        let spec = mainMenuController?.spec ?? MainMenuSpec(isEnabled: false)
        if !spec.ownsKeyCommands { mainMenuChatObservation = nil }
        MainMenuBuilder(chatHistory: mainMenuChatHistory, bookmarkChildren: { [weak self] in self?.mainMenuBookmarks?.children(of: $0) ?? [] })
            .build(spec, with: builder)
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
