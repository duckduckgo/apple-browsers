//
//  DBPUIViewModel.swift
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
import Combine
import WebKit
import BrowserServicesKit
import Common
import FoundationExtensions
import os.log
import PrivacyConfig
import DataBrokerProtectionCore
import enum UserScript.UserScriptError

protocol DBPUIScanOps: AnyObject {
    func updateCacheWithCurrentScans() async
    func assistedOptOutDataDidChange()
    func getBackgroundAgentMetadata() async -> DBPBackgroundAgentMetadata?
}

public final class DBPUIViewModel {
    private let dataManager: DataBrokerProtectionDataManaging?
    private let agentInterface: DataBrokerProtectionAppToAgentInterface
    private let vpnBypassService: VPNBypassServiceProvider?

    private let privacyConfig: PrivacyConfigurationManaging?
    private let prefs: ContentScopeProperties?
    private var communicationLayer: DBPUICommunicationLayer?
    private var webView: WKWebView?
    private let webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let userAssistanceFlagger: UserAssistanceFeatureFlagging?
    @MainActor private var assistedOptOutsPolling: Task<Void, Never>?
    /// The list last sent to the dashboard. Polling pushes only when it changes, and a failed fetch falls back to it.
    @MainActor private var lastAssistedOptOuts: AssistedOptOutList?
    private let dbpSettings: DataBrokerProtectionSettings
    @MainActor private var freeScanEntryPoint: String?
    @MainActor private var lastHandshakeFreeScanEntryPoint: String?

    public init(dataManager: DataBrokerProtectionDataManaging?,
                agentInterface: DataBrokerProtectionAppToAgentInterface,
                vpnBypassService: VPNBypassServiceProvider? = nil,
                webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                privacyConfig: PrivacyConfigurationManaging? = nil,
                prefs: ContentScopeProperties? = nil,
                webView: WKWebView? = nil,
                dbpSettings: DataBrokerProtectionSettings = DataBrokerProtectionSettings(defaults: .dbp),
                userAssistanceFlagger: UserAssistanceFeatureFlagging? = nil) {
        self.dataManager = dataManager
        self.agentInterface = agentInterface
        self.vpnBypassService = vpnBypassService
        self.webUISettings = webUISettings
        self.pixelHandler = pixelHandler
        self.privacyConfig = privacyConfig
        self.prefs = prefs
        self.webView = webView
        self.dbpSettings = dbpSettings
        self.userAssistanceFlagger = userAssistanceFlagger
    }

    deinit {
        assistedOptOutsPolling?.cancel()
    }

    @MainActor func setupCommunicationLayer() -> WKWebViewConfiguration? {
        guard let privacyConfig = privacyConfig else { return nil }
        guard let prefs = prefs else { return nil }
        guard let dataManager = dataManager else { return nil }

        let configuration = WKWebViewConfiguration()
        do {
            try configuration.applyDBPUIConfiguration(privacyConfig: privacyConfig,
                                                      prefs: prefs,
                                                      delegate: dataManager.communicator,
                                                      handshakeDelegate: self,
                                                      assistedOptOutsDelegate: self,
                                                      webUISettings: webUISettings,
                                                      vpnBypassService: vpnBypassService,
                                                      dbpSettings: dbpSettings)
        } catch {
            if case let UserScriptError.failedToLoadJS(jsFile, error) = error {
                pixelHandler.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                Thread.sleep(forTimeInterval: 1.0) // give time for the pixel to be sent
            }
            fatalError("Failed to apply DBPUI configuration: \(error)")
        }
        dataManager.communicator.scanDelegate = self
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        if let dbpUIContentController = configuration.userContentController as? DBPUIUserContentController {
            communicationLayer = dbpUIContentController.dbpUIUserScripts.dbpUICommunicationLayer
        }

        return configuration
    }

    /// The handshake carries the value and runs once per document load, so an already-loaded UI
    /// needs a reload to see a new entry point.
    @MainActor func setFreeScanEntryPoint(_ entryPoint: String?, in webView: WKWebView?) {
        guard freeScanEntryPoint != entryPoint else { return }
        freeScanEntryPoint = entryPoint

        guard lastHandshakeFreeScanEntryPoint != entryPoint, let webView, webView.url != nil else { return }
        webView.reload()
    }
}

extension DBPUIViewModel: DBPUIHandshakeDelegate {
    @MainActor public func getHandshakeUserData() async -> DBPUIHandshakeUserData? {
        let entryPoint = freeScanEntryPoint
        lastHandshakeFreeScanEntryPoint = entryPoint
        let userData = await dataManager?.communicator.getHandshakeUserData()
        return DBPUIHandshakeUserData(isAuthenticatedUser: userData?.isAuthenticatedUser ?? true,
                                      isUserEligibleForFreeTrial: userData?.isUserEligibleForFreeTrial ?? false,
                                      freeScanEntryPoint: entryPoint)
    }
}

extension DBPUIViewModel: DBPUIScanOps {
    func assistedOptOutDataDidChange() {
        agentInterface.assistedOptOutDataDidChange()
    }

    func profileSaved() {
        Task {
            await agentInterface.profileSaved()
        }
    }

    func updateCacheWithCurrentScans() async {
        do {
            try dataManager?.prepareBrokerProfileQueryDataCache()
        } catch {
            Logger.dataBrokerProtection.error("DBPUIViewModel error: updateCacheWithCurrentScans, error: \(error.localizedDescription, privacy: .public)")
            pixelHandler.fire(.databaseError(error: error, functionOccurredIn: "DBPUIViewModel.updateCacheWithCurrentScans"))
        }
    }

    func getBackgroundAgentMetadata() async -> DBPBackgroundAgentMetadata? {
        return await agentInterface.getDebugMetadata()
    }
}

extension DBPUIViewModel: DBPUIAssistedOptOutsDelegate {
    public var isUserAssistanceEnabled: Bool {
        userAssistanceFlagger?.isUserAssistanceOn == true
    }

    public func getAssistedOptOuts() async -> AssistedOptOutList {
        let list = isUserAssistanceEnabled
            ? await agentInterface.getAssistedOptOuts() : AssistedOptOutList(optOuts: [])
        return await MainActor.run {
            let currentList = isUserAssistanceEnabled ? (list ?? lastAssistedOptOuts ?? AssistedOptOutList(optOuts: [])) : AssistedOptOutList(optOuts: [])
            lastAssistedOptOuts = currentList
            return currentList
        }
    }

    public func startAssistedOptOut(id: String) async {
        guard isUserAssistanceEnabled else { return }
        agentInterface.startAssistedOptOut(id: id)
    }

    /// Keeps the dashboard's Needs you list current while it's open, since attempts start and finish in the agent process.
    @MainActor func startAssistedOptOutsPolling(in webView: WKWebView) {
        stopAssistedOptOutsPolling()
        assistedOptOutsPolling = Task { @MainActor [weak self, weak webView] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard let webView else { return }
                await self?.pollAssistedOptOuts(in: webView)
            }
        }
    }

    @MainActor func stopAssistedOptOutsPolling() {
        assistedOptOutsPolling?.cancel()
        assistedOptOutsPolling = nil
    }

    @MainActor func pollAssistedOptOuts(in webView: WKWebView) async {
        guard webView.window?.occlusionState.contains(.visible) == true else { return }
        let list = isUserAssistanceEnabled
            ? await agentInterface.getAssistedOptOuts() : AssistedOptOutList(optOuts: [])
        let currentList = isUserAssistanceEnabled ? list : AssistedOptOutList(optOuts: [])
        guard !Task.isCancelled, let currentList, currentList != lastAssistedOptOuts else { return }
        lastAssistedOptOuts = currentList
        communicationLayer?.sendAssistedOptOutsDidChange(currentList, into: webView)
    }
}
