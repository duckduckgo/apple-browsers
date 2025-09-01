//
//  UserContentUpdating.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Foundation
import Combine
import Common
import BrowserServicesKit
import History
import NewTabPage
import UserScript
import Configuration

extension ContentBlockerRulesIdentifier.Difference {
    static let notification = ContentBlockerRulesIdentifier.Difference(rawValue: 1 << 8)
}

protocol UserScriptDependenciesProviding: AnyObject {
    @MainActor
    func makeNewTabPageActionsManager() -> NewTabPageActionsManager?
}

final class UserContentUpdating {

    private typealias Update = ContentBlockerRulesManager.UpdateEvent
    struct NewContent: UserContentControllerNewContent {
        let rulesUpdate: ContentBlockerRulesManager.UpdateEvent
        let sourceProvider: ScriptSourceProviding

        var makeUserScripts: @MainActor (ScriptSourceProviding) -> UserScripts {
            { sourceProvider in
                UserScripts(with: sourceProvider)
            }
        }
    }

    @Published private var bufferedValue: NewContent?
    private var cancellable: AnyCancellable?

    private(set) var userContentBlockingAssets: AnyPublisher<UserContentUpdating.NewContent, Never>!

    weak var userScriptDependenciesProvider: UserScriptDependenciesProviding? {
        didSet {
            isDependenciesProviderInitialized = true
        }
    }

    /// This property is used to avoid race condition upon app initialization.
    ///
    /// `makeValue` closure in the initializer requires `userScriptDependenciesProvider`
    /// (that initializes `newTabPageActionsManager`), but the dependencies provider
    /// is only set after the initializer returns. In the rare case when
    /// `AppDelegate.init` takes too long, and content blocking rules get updated
    /// before dependencies provider is assigned, `makeValue` would use nil
    /// `newTabPageActionsManager`. By halting `updatesStream` until this property
    /// is `true` we ensure that `ScriptSourceProvider` is initialized with a correct
    /// value of `newTabPageActionsManager`.
    @Published private var isDependenciesProviderInitialized: Bool = false

    @MainActor
    private lazy var newTabPageActionsManager: NewTabPageActionsManager? = userScriptDependenciesProvider?.makeNewTabPageActionsManager()

    @MainActor
    init(contentBlockerRulesManager: ContentBlockerRulesManagerProtocol,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         trackerDataManager: TrackerDataManager,
         configStorage: ConfigurationStoring,
         webTrackingProtectionPreferences: WebTrackingProtectionPreferences,
         experimentManager: @autoclosure @escaping () -> ContentScopeExperimentsManaging,
         tld: TLD,
         onboardingNavigationDelegate: OnboardingNavigating,
         appearancePreferences: AppearancePreferences,
         startupPreferences: StartupPreferences,
         windowControllersManager: WindowControllersManagerProtocol,
         bookmarkManager: BookmarkManager & HistoryViewBookmarksHandling,
         historyCoordinator: HistoryDataSource,
         fireproofDomains: DomainFireproofStatusProviding,
         fireCoordinator: FireCoordinator
    ) {
        func onNotificationWithInitial(_ name: Notification.Name) -> AnyPublisher<Notification, Never> {
            return NotificationCenter.default.publisher(for: name)
                .prepend([Notification(name: .init(rawValue: "initial"))])
                .eraseToAnyPublisher()
        }

        func combine(_ update: Update, _ notification: Notification) -> Update {
            var changes = update.changes
            changes[notification.name.rawValue] = .notification
            return Update(rules: update.rules, changes: changes, completionTokens: update.completionTokens)
        }

        // 2. Publish ContentBlockingAssets(Rules+Scripts) for WKUserContentController per subscription
        self.userContentBlockingAssets = $bufferedValue
            .compactMap { $0 } // drop initial nil
            .eraseToAnyPublisher()

        let makeValue: (Update) async -> NewContent = { [weak self] rulesUpdate in
            let sourceProvider = ScriptSourceProvider(configStorage: configStorage,
                                                      privacyConfigurationManager: privacyConfigurationManager,
                                                      webTrackingProtectionPreferences: webTrackingProtectionPreferences,
                                                      contentBlockingManager: contentBlockerRulesManager,
                                                      trackerDataManager: trackerDataManager,
                                                      experimentManager: experimentManager(),
                                                      tld: tld,
                                                      onboardingNavigationDelegate: onboardingNavigationDelegate,
                                                      appearancePreferences: appearancePreferences,
                                                      startupPreferences: startupPreferences,
                                                      windowControllersManager: windowControllersManager,
                                                      bookmarkManager: bookmarkManager,
                                                      historyCoordinator: historyCoordinator,
                                                      fireproofDomains: fireproofDomains,
                                                      fireCoordinator: fireCoordinator,
                                                      newTabPageActionsManager: self?.newTabPageActionsManager)
            return NewContent(rulesUpdate: rulesUpdate, sourceProvider: sourceProvider)
        }

        let updatesStream = AsyncStream { continuation in
            // 1. Collect updates from ContentBlockerRulesManager and generate UserScripts based on its output
            let cancellable = contentBlockerRulesManager.updatesPublisher
            // regenerate UserScripts on gpcEnabled preference updated
                .combineLatest(webTrackingProtectionPreferences.$isGPCEnabled)
                .map { $0.0 } // drop gpcEnabled value: $0.1
                .combineLatest(onNotificationWithInitial(.autofillUserSettingsDidChange), combine)
                .combineLatest(onNotificationWithInitial(.autofillScriptDebugSettingsDidChange), combine)
                .combineLatest($isDependenciesProviderInitialized.removeDuplicates())
                .filter { (_, isInitialized) in isInitialized } // only proceed if provider was initialized
                .sink { (value, _) in
                    continuation.yield(value)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
            .map { await makeValue($0) }

        updatesTask = Task {
            // DefaultScriptSourceProvider instance should be created once per rules/config change and fed into UserScripts initialization
            for await value in updatesStream {
                bufferedValue = value
            }
        }
    }

    private var updatesTask: Task<Void, Never>?

    deinit {
        updatesTask?.cancel()
    }
}
