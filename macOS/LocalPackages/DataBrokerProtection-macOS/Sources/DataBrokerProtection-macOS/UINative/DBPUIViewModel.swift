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
    @MainActor private var freeScanEntryPoint: String?
    @MainActor private var lastHandshakeFreeScanEntryPoint: String?
#if DEBUG
    @MainActor private var needsYouUpdates: Task<Void, Never>?
    @MainActor private var lastNeedsYou: DBPUINeedsYouList?
#endif

    public init(dataManager: DataBrokerProtectionDataManaging?,
                agentInterface: DataBrokerProtectionAppToAgentInterface,
                vpnBypassService: VPNBypassServiceProvider? = nil,
                webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                privacyConfig: PrivacyConfigurationManaging? = nil,
                prefs: ContentScopeProperties? = nil,
                webView: WKWebView? = nil) {
        self.dataManager = dataManager
        self.agentInterface = agentInterface
        self.vpnBypassService = vpnBypassService
        self.webUISettings = webUISettings
        self.pixelHandler = pixelHandler
        self.privacyConfig = privacyConfig
        self.prefs = prefs
        self.webView = webView
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
                                                      webUISettings: webUISettings,
                                                      vpnBypassService: vpnBypassService)
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

#if DEBUG
extension DBPUIViewModel: DBPUINeedsYouDelegate {
    public func getNeedsYou() async -> DBPUINeedsYouList? {
        do {
            return try await agentInterface.getNeedsYou()
        } catch {
            Logger.dataBrokerProtection.error("DBPUIViewModel getNeedsYou error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func openNeedsYouItem(id: String) async -> Bool {
        (try? await agentInterface.openNeedsYouItem(id: id)) ?? false
    }

    /// The agent can't message the app, so poll it while the dashboard is open and push changes to the page.
    @MainActor func startNeedsYouUpdates(in webView: WKWebView) {
        needsYouUpdates?.cancel()
        needsYouUpdates = Task { @MainActor [weak self, weak webView] in
            while !Task.isCancelled {
                // Strong references only for one poll, so closing the dashboard frees the view model and ends the loop.
                do {
                    guard let self, let webView else { return }
                    if webView.window != nil, let list = await self.getNeedsYou(), list != self.lastNeedsYou {
                        self.lastNeedsYou = list
                        self.communicationLayer?.sendNeedsYouDidChange(list, into: webView)
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
#endif
