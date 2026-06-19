//
//  DebugScreen.swift
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

import AIChat
import DDGSync
import Persistence
import PrivacyConfig
import Core
import SwiftUI
import UIKit
import Configuration
import SystemSettingsPiPTutorial
import DataBrokerProtection_iOS
import Subscription
import WebExtensions
import DeferredReadingCore

protocol RemoteMessagingDebugHandling {
    func refreshRemoteMessages()
}

enum DebugScreen: Identifiable {

    struct Dependencies {

        let syncService: DDGSyncing
        let syncAutoRestoreHandler: SyncAutoRestoreHandling
        let bookmarksDatabase: CoreDataDatabase
        let internalUserDecider: InternalUserDecider
        let tabManager: TabManager
        let tipKitUIActionHandler: TipKitDebugOptionsUIActionHandling
        let fireproofing: Fireproofing
        let customConfigurationURLProvider: CustomConfigurationURLProviding
        let keyValueStore: ThrowingKeyValueStoring
        let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging
        let daxDialogManager: DaxDialogsManaging
        let databaseDelegate: DBPIOSInterface.DatabaseDelegate?
        let debuggingDelegate: DBPIOSInterface.DebuggingDelegate?
        let runPrequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
        let freemiumPIRDebugSettings: FreemiumPIRDebugSettings
        let freemiumDBPUserStateManager: FreemiumDBPUserStateManaging
        let subscriptionDataReporter: SubscriptionDataReporting
        let remoteMessagingDebugHandler: RemoteMessagingDebugHandling
        let webExtensionManager: WebExtensionManaging?
        let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
        let deferredReadingController: DeferredReadingController?

        init(syncService: DDGSyncing,
             syncAutoRestoreHandler: SyncAutoRestoreHandling,
             bookmarksDatabase: CoreDataDatabase,
             internalUserDecider: InternalUserDecider,
             tabManager: TabManager,
             tipKitUIActionHandler: TipKitDebugOptionsUIActionHandling,
             fireproofing: Fireproofing,
             customConfigurationURLProvider: CustomConfigurationURLProviding,
             keyValueStore: ThrowingKeyValueStoring,
             systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
             daxDialogManager: DaxDialogsManaging,
             databaseDelegate: DBPIOSInterface.DatabaseDelegate?,
             debuggingDelegate: DBPIOSInterface.DebuggingDelegate?,
             runPrequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?,
             freemiumPIRDebugSettings: FreemiumPIRDebugSettings,
             freemiumDBPUserStateManager: FreemiumDBPUserStateManaging,
             subscriptionDataReporter: SubscriptionDataReporting,
             remoteMessagingDebugHandler: RemoteMessagingDebugHandling,
             webExtensionManager: WebExtensionManaging?,
             duckAiNativeStorageHandler: DuckAiNativeStorageHandling?,
             deferredReadingController: DeferredReadingController? = nil) {
            self.syncService = syncService
            self.syncAutoRestoreHandler = syncAutoRestoreHandler
            self.bookmarksDatabase = bookmarksDatabase
            self.internalUserDecider = internalUserDecider
            self.tabManager = tabManager
            self.tipKitUIActionHandler = tipKitUIActionHandler
            self.fireproofing = fireproofing
            self.customConfigurationURLProvider = customConfigurationURLProvider
            self.keyValueStore = keyValueStore
            self.systemSettingsPiPTutorialManager = systemSettingsPiPTutorialManager
            self.daxDialogManager = daxDialogManager
            self.databaseDelegate = databaseDelegate
            self.debuggingDelegate = debuggingDelegate
            self.runPrequisitesDelegate = runPrequisitesDelegate
            self.freemiumPIRDebugSettings = freemiumPIRDebugSettings
            self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
            self.subscriptionDataReporter = subscriptionDataReporter
            self.remoteMessagingDebugHandler = remoteMessagingDebugHandler
            self.webExtensionManager = webExtensionManager
            self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
            self.deferredReadingController = deferredReadingController
        }

    }

    case controller(title: String, (Dependencies) -> UIViewController)
    case view(title: String, (Dependencies) -> any View)
    case action(title: String, (Dependencies) -> Void)

    var isAction: Bool {
        if case .action = self {
            return true
        }
        return false
    }

    var id: String {
        return title
    }

    var title: String {
        switch self {
        case .controller(let title, _):
            return title

        case .view(let title, _):
            return title

        case .action(let title, _):
            return title
        }
    }

}
