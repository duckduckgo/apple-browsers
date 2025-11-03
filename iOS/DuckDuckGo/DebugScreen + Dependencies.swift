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

import DDGSync
import Persistence
import BrowserServicesKit
import Core
import SwiftUI
import UIKit
import Configuration
import SystemSettingsPiPTutorial
import DataBrokerProtection_iOS
import Debug

struct DebugDependencies: DebugDependenciesProviding {

    typealias TabManagerType = TabManager
    typealias TipKitDebugOptionsUIActionHandlingType = TipKitDebugOptionsUIActionHandling
    typealias FireproofingType = Fireproofing
    typealias DaxDialogsManagingType = DaxDialogsManaging
    
    // For the computed property, we'll use a getter/setter pattern
    private let _inspectableWebViewEnabled: () -> Bool
    private let _setInspectableWebViewEnabled: (Bool) -> Void
    
    public var inspectableWebViewEnabled: Bool {
        get { _inspectableWebViewEnabled() }
        set { _setInspectableWebViewEnabled(newValue) }
    }
    
    let syncService: DDGSyncing
    let bookmarksDatabase: CoreDataDatabase
    let internalUserDecider: InternalUserDecider
    let tabManager: TabManagerType
    let tipKitUIActionHandler: TipKitDebugOptionsUIActionHandlingType
    let fireproofing: FireproofingType
    let customConfigurationURLProvider: CustomConfigurationURLProviding
    let keyValueStore: ThrowingKeyValueStoring
    let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging
    let daxDialogManager: DaxDialogsManagingType
    let databaseDelegate: DBPIOSInterface.DatabaseDelegate?
    let debuggingDelegate: DBPIOSInterface.DebuggingDelegate?
    let runPrequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
    
    let fetchRemoteMessagingConfiguration: () -> Void
    let postinspectableWebViewsToggled: () -> Void
    let fetchPrivacyConfiguration: (@escaping (Bool) -> Void) -> Void
    
    public init(
        syncService: DDGSyncing,
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
        runPrequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
    ) {
        self.syncService = syncService
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
        
        // Implementation for inspectableWebViewEnabled
        self._inspectableWebViewEnabled = {
            return AppUserDefaults().inspectableWebViewEnabled
        }
        
        self._setInspectableWebViewEnabled = { newValue in
            let defaults = AppUserDefaults()
            let oldValue = defaults.inspectableWebViewEnabled
            defaults.inspectableWebViewEnabled = newValue
            
            if oldValue != newValue {
                NotificationCenter.default.post(
                    Notification(name: AppUserDefaults.Notifications.inspectableWebViewsToggled)
                )
            }
        }
        
        // Implementation for postInspectableWebViewsToggled
        self.postinspectableWebViewsToggled = {
            NotificationCenter.default.post(
                Notification(name: AppUserDefaults.Notifications.inspectableWebViewsToggled)
            )
        }
        
        // Implementation for fetchRemoteMessagingConfiguration
        self.fetchRemoteMessagingConfiguration = {
            (UIApplication.shared.delegate as? AppDelegate)?.debugRefreshRemoteMessages()
        }
        
        // Implementation for fetchPrivacyConfiguration
        self.fetchPrivacyConfiguration = { completion in
            AppConfigurationFetch().start(isDebug: true, forceRefresh: true) { result in
                switch result {
                case .assetsUpdated(let protectionsUpdated):
                    if protectionsUpdated {
                        ContentBlocking.shared.contentBlockingManager.scheduleCompilation()
                    }
                    DispatchQueue.main.async {
                        completion(true)
                    }
                case .noData:
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        }
    }
}
