//
//  DebugDependencies.swift
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

import Foundation
import BrowserServicesKit
import Configuration
import DDGSync
import Persistence
import SystemSettingsPiPTutorial
import DataBrokerProtection_iOS

/// Dependencies passed through to individual debug screens
/// Individual debug screens (like SyncDebugViewController, CookieDebugViewController, etc.)
/// receive these dependencies to perform their specific debug operations
public protocol DebugDependenciesProviding {
    
    associatedtype TabManagerType
    associatedtype TipKitDebugOptionsUIActionHandlingType
    associatedtype FireproofingType
    associatedtype DaxDialogsManagingType
    
    var syncService: DDGSyncing { get }
    var bookmarksDatabase: CoreDataDatabase { get }
    var internalUserDecider: InternalUserDecider { get }
    var tabManager: TabManagerType { get }
    var tipKitUIActionHandler: TipKitDebugOptionsUIActionHandlingType { get }
    var fireproofing: FireproofingType { get }
    var customConfigurationURLProvider: CustomConfigurationURLProviding { get }
    var keyValueStore: ThrowingKeyValueStoring { get }
    var systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging { get }
    var daxDialogManager: DaxDialogsManagingType { get }
    var databaseDelegate: DBPIOSInterface.DatabaseDelegate? { get }
    var debuggingDelegate: DBPIOSInterface.DebuggingDelegate? { get }
    var runPrequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate? { get }
    
    var inspectableWebViewEnabled: Bool { get set }
    var postinspectableWebViewsToggled: () -> Void { get }
    var fetchRemoteMessagingConfiguration: () -> Void { get }
    var fetchPrivacyConfiguration: (@escaping (Bool) -> Void) -> Void { get }
}

public struct AnyDebugDependencies: DebugDependenciesProviding {
    
    public typealias TabManagerType = Any
    public typealias TipKitDebugOptionsUIActionHandlingType = Any
    public typealias FireproofingType = Any
    public typealias DaxDialogsManagingType = Any

    private let _syncService: () -> DDGSyncing
    private let _bookmarksDatabase: () -> CoreDataDatabase
    private let _internalUserDecider: () -> InternalUserDecider
    private let _tabManager: () -> Any
    private let _tipKitUIActionHandler: () -> Any
    private let _fireproofing: () -> Any
    private let _customConfigurationURLProvider: () -> CustomConfigurationURLProviding
    private let _keyValueStore: () -> ThrowingKeyValueStoring
    private let _systemSettingsPiPTutorialManager: () -> SystemSettingsPiPTutorialManaging
    private let _daxDialogManager: () -> Any
    private let _databaseDelegate: () -> DBPIOSInterface.DatabaseDelegate?
    private let _debuggingDelegate: () -> DBPIOSInterface.DebuggingDelegate?
    private let _runPrequisitesDelegate: () -> DBPIOSInterface.RunPrerequisitesDelegate?
    
    private let _inspectableWebViewEnabled: () -> Bool
    private var _setInspectableWebViewEnabled: (Bool) -> Void
    private let _postinspectableWebViewsToggled: () -> Void
    private let _fetchRemoteMessagingConfiguration: () -> Void
    private let _fetchPrivacyConfiguration: (@escaping (Bool) -> Void) -> Void

    public init<D: DebugDependenciesProviding>(_ deps: D) {
        var deps = deps
        _syncService = { deps.syncService }
        _bookmarksDatabase = { deps.bookmarksDatabase }
        _internalUserDecider = { deps.internalUserDecider }
        _tabManager = { deps.tabManager }
        _tipKitUIActionHandler = { deps.tipKitUIActionHandler }
        _fireproofing = { deps.fireproofing }
        _customConfigurationURLProvider = { deps.customConfigurationURLProvider }
        _keyValueStore = { deps.keyValueStore }
        _systemSettingsPiPTutorialManager = { deps.systemSettingsPiPTutorialManager }
        _daxDialogManager = { deps.daxDialogManager }
        _databaseDelegate = { deps.databaseDelegate }
        _debuggingDelegate = { deps.debuggingDelegate }
        _runPrequisitesDelegate = { deps.runPrequisitesDelegate }
        _inspectableWebViewEnabled = { deps.inspectableWebViewEnabled }
        _setInspectableWebViewEnabled = { deps.inspectableWebViewEnabled = $0 }
        _postinspectableWebViewsToggled = deps.postinspectableWebViewsToggled
        _fetchRemoteMessagingConfiguration = deps.fetchRemoteMessagingConfiguration
        _fetchPrivacyConfiguration = deps.fetchPrivacyConfiguration
    }

    public var syncService: DDGSyncing { _syncService() }
    public var bookmarksDatabase: CoreDataDatabase { _bookmarksDatabase() }
    public var internalUserDecider: InternalUserDecider { _internalUserDecider() }
    public var tabManager: Any { _tabManager() }
    public var tipKitUIActionHandler: Any { _tipKitUIActionHandler() }
    public var fireproofing: Any { _fireproofing() }
    public var customConfigurationURLProvider: CustomConfigurationURLProviding { _customConfigurationURLProvider() }
    public var keyValueStore: ThrowingKeyValueStoring { _keyValueStore() }
    public var systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging { _systemSettingsPiPTutorialManager() }
    public var daxDialogManager: Any { _daxDialogManager() }
    public var databaseDelegate: DBPIOSInterface.DatabaseDelegate? { _databaseDelegate() }
    public var debuggingDelegate: DBPIOSInterface.DebuggingDelegate? { _debuggingDelegate() }
    public var runPrequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate? { _runPrequisitesDelegate() }

    public var inspectableWebViewEnabled: Bool {
        get { _inspectableWebViewEnabled() }
        set { _setInspectableWebViewEnabled(newValue) }
    }
    public var postinspectableWebViewsToggled: () -> Void { _postinspectableWebViewsToggled }
    public var fetchRemoteMessagingConfiguration: () -> Void { _fetchRemoteMessagingConfiguration }
    public var fetchPrivacyConfiguration: (@escaping (Bool) -> Void) -> Void { _fetchPrivacyConfiguration }
}

