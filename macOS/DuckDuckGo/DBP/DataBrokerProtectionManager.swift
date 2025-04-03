//
//  DataBrokerProtectionManager.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import PixelKit
import LoginItems
import Common
import Freemium
import NetworkProtectionIPC

public final class DataBrokerProtectionManager {

    static let shared = DataBrokerProtectionManager()

    private let pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels> = DataBrokerProtectionMacOSPixelsHandler()
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let fakeBrokerFlag: DataBrokerDebugFlag = DataBrokerDebugFlagFakeBroker()
    private let vpnBypassService: VPNBypassFeatureProvider

    private lazy var freemiumDBPFirstProfileSavedNotifier: FreemiumDBPFirstProfileSavedNotifier = {
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let freemiumDBPFirstProfileSavedNotifier = FreemiumDBPFirstProfileSavedNotifier(freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                                                                                        authenticationStateProvider: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        return freemiumDBPFirstProfileSavedNotifier
    }()

    lazy var dataManager: DataBrokerProtectionDataManager = {
        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)

        guard let pixelKit = PixelKit.shared else {
            fatalError("PixelKit not set up")
        }
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler)
        guard let vault = try? vaultFactory.makeVault(reporter: reporter) else {
            fatalError("Failed to make secure storage vault")
        }

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker, pixelHandler: sharedPixelsHandler, vault: vault)

        let dataManager = DataBrokerProtectionDataManager(database: database,
                                                          profileSavedNotifier: freemiumDBPFirstProfileSavedNotifier)

        dataManager.delegate = self
        return dataManager
    }()

    private lazy var ipcClient: DataBrokerProtectionIPCClient = {
        let loginItemStatusChecker = LoginItem.dbpBackgroundAgent
        return DataBrokerProtectionIPCClient(machServiceName: Bundle.main.dbpBackgroundAgentBundleId,
                                             pixelHandler: pixelHandler,
                                             loginItemStatusChecker: loginItemStatusChecker)
    }()

    lazy var loginItemInterface: DataBrokerProtectionLoginItemInterface = {
        return DefaultDataBrokerProtectionLoginItemInterface(ipcClient: ipcClient, pixelHandler: pixelHandler)
    }()

    private init() {
        self.authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(
            subscriptionManager: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        self.vpnBypassService = VPNBypassService()
    }

    public func isUserAuthenticated() -> Bool {
        authenticationManager.isUserAuthenticated
    }

    // MARK: - Debugging Features

    public func showAgentIPAddress() {
        ipcClient.openBrowser(domain: "https://www.whatismyip.com")
    }
}

extension DataBrokerProtectionManager: DataBrokerProtectionDataManagerDelegate {

    public func dataBrokerProtectionDataManagerDidUpdateData() {
        loginItemInterface.profileSaved()
    }

    public func dataBrokerProtectionDataManagerDidDeleteData() {
        loginItemInterface.dataDeleted()
    }

    public func dataBrokerProtectionDataManagerWillOpenSendFeedbackForm() {
        NotificationCenter.default.post(name: .OpenUnifiedFeedbackForm, object: nil, userInfo: UnifiedFeedbackSource.userInfo(source: .pir))
    }

    public func dataBrokerProtectionDataManagerWillApplyVPNBypassSetting(_ bypass: Bool) async {
        vpnBypassService.applyVPNBypass(bypass)
        try? await Task.sleep(interval: 0.1)
        try? await VPNControllerXPCClient.shared.command(.restartAdapter)
    }

    public func isAuthenticatedUser() -> Bool {
        isUserAuthenticated()
    }
}
