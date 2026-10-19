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

import BrowserServicesKit
import Common
import ConcurrencyExtensions
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Foundation
import FoundationExtensions
import Freemium
import LoginItems
import NetworkProtectionIPC
import PixelKit
import Subscription
#if DEBUG
import os.log
#endif

public final class DataBrokerProtectionManager {

    static let shared = DataBrokerProtectionManager()

#if DEBUG
    @MainActor private var debugLaunchTask: Task<Void, Never>?
#endif

    private let pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels> = DataBrokerProtectionMacOSPixelsHandler()
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let fakeBrokerFlag: DataBrokerDebugFlag = DataBrokerDebugFlagFakeBroker()
    private let vpnBypassService: VPNBypassFeatureProvider
    private let freeTrialConversionService: FreeTrialConversionInstrumentationService

    private lazy var freemiumDBPFirstProfileSavedNotifier: FreemiumDBPFirstProfileSavedNotifier = {
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let freemiumDBPFirstProfileSavedNotifier = FreemiumDBPFirstProfileSavedNotifier(freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                                                                                        authenticationStateProvider: Application.appDelegate.subscriptionManager)
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

    private lazy var vault: (any DataBrokerProtectionSecureVault)? = {
        guard let sharedPixelsHandler else { return nil }

        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
        let privacyConfigManager = Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager
        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler, privacyConfigManager: privacyConfigManager)

        let vault: DefaultDataBrokerProtectionSecureVault<DefaultDataBrokerProtectionDatabaseProvider>
        do {
            vault = try vaultFactory.makeVault(reporter: reporter)
        } catch let error {
            pixelHandler.fire(.mainAppSetUpFailedSecureVaultInitFailed(error: error))
            return nil
        }

        return vault
    }()

    lazy var dataManager: DataBrokerProtectionDataManager? = {
        guard let vault, let sharedPixelsHandler, let brokerUpdater else { return nil }

        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker,
                                                    pixelHandler: sharedPixelsHandler,
                                                    vault: vault,
                                                    localBrokerService: brokerUpdater)
        let dataManager = DataBrokerProtectionDataManager(
            database: database,
            profileSavedNotifier: freemiumDBPFirstProfileSavedNotifier,
            onProfileSaved: { [weak self] in
                self?.freeTrialConversionService.markPIRActivated()
            }
        )

        dataManager.delegate = self
        return dataManager
    }()

    lazy var brokerUpdater: BrokerJSONServiceProvider? = {
        guard let vault, let sharedPixelsHandler else { return nil }

        let settings = DataBrokerProtectionSettings(defaults: .dbp)
        let featureFlagger = DBPFeatureFlagger(featureFlagger: Application.appDelegate.featureFlagger)
        let localBrokerService = LocalBrokerJSONService(resources: FileResources(runTypeProvider: settings),
                                                        vault: vault,
                                                        pixelHandler: sharedPixelsHandler,
                                                        runTypeProvider: settings,
                                                        isAuthenticatedUser: { [authenticationManager] in await authenticationManager.isUserAuthenticated },
                                                        optOutRetryErrorFeatureFlagger: featureFlagger)
        let brokerUpdater = RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                                    settings: settings,
                                                    vault: vault,
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

    private init() {
        self.authenticationManager = DataBrokerAuthenticationManagerBuilder.buildAuthenticationManager(
            subscriptionManager: Application.appDelegate.subscriptionManager)
        self.vpnBypassService = VPNBypassService()
        self.freeTrialConversionService = Application.appDelegate.freeTrialConversionService
    }

    public func isUserAuthenticated() async -> Bool {
        return await authenticationManager.isUserAuthenticated
    }

    // MARK: - Debugging Features

    public func showAgentIPAddress() {
        ipcClient.openBrowser(domain: "https://www.whatismyip.com")
    }
}

extension DataBrokerProtectionManager: DataBrokerProtectionDataManagerDelegate {

    public func dataBrokerProtectionDataManagerDidUpdateData() {
        Task {
            await loginItemInterface.profileSaved()
        }
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

    public func isAuthenticatedUser() async -> Bool {
        return await isUserAuthenticated()
    }

    /// Returns whether the current user is eligible for a free trial of Data Broker Protection
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise
    public func isUserEligibleForFreeTrial() -> Bool {
        authenticationManager.isUserEligibleForFreeTrial
    }
}

#if DEBUG
@MainActor
extension DataBrokerProtectionManager {
    private enum DebugLaunchError: Error {
        case unavailableDataManager
        case missingProfile
        case agentDidNotStop
        case agentNotReady
        case commandFailed
        case commandTimedOut
    }

    private final class DebugLaunchReply {
        var value: Bool?
    }

    func handleDebugLaunch(_ optionsHandler: LaunchOptionsHandler) -> Bool {
        do {
            guard let options = try optionsHandler.pirDebugLaunchOptions() else { return false }
            guard debugLaunchTask == nil else { return true }
            debugLaunchTask = Task {
                do {
                    try await runDebugLaunch(options)
                    Logger.dataBrokerProtection.log("PIR debug launch completed; agent event delivered.")
                } catch {
                    let failure = error as NSError
                    Logger.dataBrokerProtection.error("PIR debug launch failed: \(failure.domain, privacy: .public), code \(failure.code, privacy: .public).")
                }
            }
        } catch {
            Logger.dataBrokerProtection.error("PIR debug launch options rejected: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    func waitForDebugLaunch() async {
        await debugLaunchTask?.value
    }

    private func runDebugLaunch(_ options: PIRDebugLaunchOptions) async throws {
        Logger.dataBrokerProtection.log("PIR debug launch: reading stored profile.")
        guard let dataManager else { throw DebugLaunchError.unavailableDataManager }
        let existingProfile = try dataManager.fetchProfile()
        let profileToSave: DataBrokerProtectionProfile?
        let shouldReset: Bool
        switch options.profileSetup {
        case .seedIfMissing(let profile):
            profileToSave = existingProfile == nil ? profile : nil
            shouldReset = false
            if existingProfile != nil {
                Logger.dataBrokerProtection.log("PIR debug launch: preserving existing profile and history; fixture skipped.")
            }
        case .resetAndSeed(let profile):
            profileToSave = profile
            shouldReset = true
        case nil:
            profileToSave = nil
            shouldReset = false
        }
        guard existingProfile != nil || profileToSave != nil else {
            Logger.dataBrokerProtection.error("PIR debug launch: server requires a saved profile or valid fixture.")
            throw DebugLaunchError.missingProfile
        }

        Logger.dataBrokerProtection.log("PIR debug launch: stopping background agent.")
        try await stopDebugAgent()
        let freemiumState = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        if shouldReset {
            Logger.dataBrokerProtection.log("PIR debug launch: resetting PIR data and Freemium state.")
            try dataManager.removeAllDataForDebugLaunch()
            DataBrokerProtectionSettings(defaults: .dbp).resetBrokerDeliveryData()
            freemiumState.resetAllState()
            NotificationCenter.default.post(name: .freemiumDBPResetForDebugLaunch, object: nil)
        }
        if let profileToSave {
            Logger.dataBrokerProtection.log("PIR debug launch: saving fixture.")
            if !(await authenticationManager.isUserAuthenticated) {
                freemiumState.didActivate = true
            }
            try await dataManager.saveProfile(profileToSave)
        }

        Logger.dataBrokerProtection.log("PIR debug launch: enabling background agent.")
        try await LoginItem.dbpBackgroundAgent.enable()
        NotificationCenter.default.post(name: .dbpLoginItemEnabled, object: nil)
        try await waitForDebugAgentReady()
        if options.startServer {
            Logger.dataBrokerProtection.log("PIR debug launch: starting debug server.")
            guard try await debugReply({ ipcClient.performDebugLaunchCommand(.startServer, completion: $0) }) else {
                throw DebugLaunchError.commandFailed
            }
        }
        Logger.dataBrokerProtection.log("PIR debug launch: delivering agent event.")
        let delivered = try await debugReply { completion in
            if profileToSave != nil {
                ipcClient.profileSaved { completion($0 == nil) }
            } else {
                ipcClient.appLaunched { completion($0 == nil) }
            }
        }
        guard delivered else { throw DebugLaunchError.commandFailed }
    }

    private func stopDebugAgent() async throws {
        let agent = LoginItem.dbpBackgroundAgent
        let status = await agent.status()
        if status == .notRegistered || status == .notFound {
            if let application = agent.application, !application.terminate() {
                throw DebugLaunchError.agentDidNotStop
            }
        } else {
            try await agent.disable()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while agent.isRunning {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw DebugLaunchError.agentDidNotStop }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        NotificationCenter.default.post(name: .dbpLoginItemDisabled, object: nil)
    }

    private func waitForDebugAgentReady() async throws {
        Logger.dataBrokerProtection.log("PIR debug launch: waiting for agent readiness.")
        for _ in 0..<10 {
            do {
                if try await debugReply(timeout: 1, { ipcClient.performDebugLaunchCommand(.readiness, completion: $0) }) {
                    return
                }
            } catch DebugLaunchError.commandTimedOut {
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw DebugLaunchError.agentNotReady
    }

    private func debugReply(timeout: TimeInterval = 5, _ request: (@escaping (Bool) -> Void) -> Void) async throws -> Bool {
        let reply = DebugLaunchReply()
        request { value in
            Task { @MainActor in
                if reply.value == nil { reply.value = value }
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            try Task.checkCancellation()
            if let value = reply.value { return value }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw DebugLaunchError.commandTimedOut }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
#endif
