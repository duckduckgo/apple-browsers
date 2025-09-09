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
import os.log
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
}

extension DBPUIViewModel: DBPUIScanOps {
    func profileSaved() {
        agentInterface.profileSaved()
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
