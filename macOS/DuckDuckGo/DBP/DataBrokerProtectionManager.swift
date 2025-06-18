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
import Subscription

public final class DataBrokerProtectionManager {

    static let shared = DataBrokerProtectionManager()

    private let pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels> = DataBrokerProtectionMacOSPixelsHandler()
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let fakeBrokerFlag: DataBrokerDebugFlag = DataBrokerDebugFlagFakeBroker()
    private let vpnBypassService: VPNBypassFeatureProvider

    private var vaultInitializationFailureReported = false

    private lazy var freemiumDBPFirstProfileSavedNotifier: FreemiumDBPFirstProfileSavedNotifier = {
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let freemiumDBPFirstProfileSavedNotifier = FreemiumDBPFirstProfileSavedNotifier(freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                                                                                        authenticationStateProvider: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        return freemiumDBPFirstProfileSavedNotifier
    }()

    private lazy var sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>? = {
        guard let pixelKit = PixelKit.shared else {
            assertionFailure("PixelKit not set up")
            return nil
        }
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
        return sharedPixelsHandler
    }()

    lazy var dataManager: DataBrokerProtectionDataManager? = {
        guard let sharedPixelsHandler, let brokerUpdater else { return nil }

        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker,
                                                    pixelHandler: sharedPixelsHandler,
                                                    vaultMaker: makeSecureVault(),
                                                    localBrokerService: brokerUpdater)
        let dataManager = DataBrokerProtectionDataManager(database: database,
                                                          profileSavedNotifier: freemiumDBPFirstProfileSavedNotifier)

        dataManager.delegate = self
        return dataManager
    }()

    lazy var brokerUpdater: BrokerJSONServiceProvider? = {
        guard let sharedPixelsHandler else { return nil }

        let featureFlagger = DBPFeatureFlagger(featureFlagger: Application.appDelegate.featureFlagger)
        let localBrokerService = LocalBrokerJSONService(vaultMaker: makeSecureVault(),
                                                        pixelHandler: sharedPixelsHandler)
        let brokerUpdater = RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                                    settings: DataBrokerProtectionSettings(defaults: .dbp),
                                                    vaultMaker: makeSecureVault(),
                                                    authenticationManager: authenticationManager,
                                                    pixelHandler: sharedPixelsHandler,
                                                    localBrokerProvider: localBrokerService)
        return brokerUpdater
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

    private func makeSecureVault() -> () -> (any DataBrokerProtectionSecureVault)? {
        return { [weak self] in
            guard let self, let sharedPixelsHandler = self.sharedPixelsHandler else { return nil }

            let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
            let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
            let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler)

            do {
                let vault = try vaultFactory.makeVault(reporter: reporter)
                if vaultInitializationFailureReported {
                    pixelHandler.fire(.mainAppSetUpSecureVaultInitSucceeded)
                    vaultInitializationFailureReported = false
                }
                return vault
            } catch let error {
                pixelHandler.fire(.mainAppSetUpFailedSecureVaultInitFailed(error: error))
                vaultInitializationFailureReported = true
                return nil
            }
        }
    }

    private init() {
        self.authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(
            subscriptionManager: Application.appDelegate.subscriptionAuthV1toV2Bridge)
        self.vpnBypassService = VPNBypassService()
    }

    public func isUserAuthenticated() -> Bool {
        authenticationManager.isUserAuthenticated
    }

    public func checkForBrokerUpdates() {
        Task {
            try await brokerUpdater?.checkForUpdates()
        }
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
        DataBrokerProtectionSettings(defaults: .dbp).resetBrokerDeliveryData()
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
