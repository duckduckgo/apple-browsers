//
//  AIChatUserScriptHandling.swift
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

import UserScript
import Foundation
import PrivacyConfig
import RemoteMessaging
import AIChat
import OSLog
import WebKit
import Common
import DDGSync
import Core

/// The current display mode of the AI Chat interface.
enum AIChatDisplayMode {
    case fullTab
    case contextual
}

// MARK: - Response Types

/// Response structure for openKeyboard request
struct OpenKeyboardResponse: Encodable {
    let success: Bool
    let error: String?

    init(success: Bool, error: String? = nil) {
        self.success = success
        self.error = error
    }
}

protocol AIChatMetricReportingHandling: AnyObject {
    func didReportMetric(_ metric: AIChatMetric)
}

// swiftlint:disable inclusive_language
protocol AIChatUserScriptHandling: AnyObject {
    var displayMode: AIChatDisplayMode? { get set }
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) -> Encodable?
    func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable?
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func setPayloadHandler(_ payloadHandler: (any AIChatConsumableDataHandling)?)
    func setAIChatInputBoxHandler(_ inputBoxHandler: (any AIChatInputBoxHandling)?)
    func setMetricReportingHandler(_ metricHandler: (any AIChatMetricReportingHandling)?)
    func getResponseState(params: Any, message: UserScriptMessage) async -> Encodable?
    func hideChatInput(params: Any, message: UserScriptMessage) async -> Encodable?
    func showChatInput(params: Any, message: UserScriptMessage) async -> Encodable?
    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable?
    func openKeyboard(params: Any, message: UserScriptMessage, webView: WKWebView?) async -> Encodable?
    func storeMigrationData(params: Any, message: UserScriptMessage) -> Encodable?
    func getMigrationDataByIndex(params: Any, message: UserScriptMessage) -> Encodable?
    func getMigrationInfo(params: Any, message: UserScriptMessage) -> Encodable?
    func clearMigrationData(params: Any, message: UserScriptMessage) -> Encodable?

    // Sync
    func getSyncStatus(params: Any, message: UserScriptMessage) -> Encodable?
    func getScopedSyncAuthToken(params: Any, message: UserScriptMessage) async -> Encodable?
    func encryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable?
    func decryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable?
    func sendToSyncSettings(params: Any, message: UserScriptMessage) -> Encodable?
    func sendToSetupSync(params: Any, message: UserScriptMessage) -> Encodable?
    func setAIChatHistoryEnabled(params: Any, message: UserScriptMessage) -> Encodable?
}

final class AIChatUserScriptHandler: AIChatUserScriptHandling {

    private var payloadHandler: (any AIChatConsumableDataHandling)?
    private var inputBoxHandler: (any AIChatInputBoxHandling)?
    private weak var metricReportingHandler: (any AIChatMetricReportingHandling)?
    private let experimentalAIChatManager: ExperimentalAIChatManager
    private let syncHandler: AIChatSyncHandling
    private let featureFlagger: FeatureFlagger
    private let migrationStore = AIChatMigrationStore()
    private let aichatFullModeFeature: AIChatFullModeFeatureProviding
    private let aichatContextualModeFeature: AIChatContextualModeFeatureProviding
    
    /// Set externally via `AIChatContentHandler.setup()`.
    var displayMode: AIChatDisplayMode?

    init(experimentalAIChatManager: ExperimentalAIChatManager,
         syncHandler: AIChatSyncHandling,
         featureFlagger: FeatureFlagger,
         aichatFullModeFeature: AIChatFullModeFeatureProviding = AIChatFullModeFeature(),
         aichatContextualModeFeature: AIChatContextualModeFeatureProviding = AIChatContextualModeFeature()) {
        self.experimentalAIChatManager = experimentalAIChatManager
        self.syncHandler = syncHandler
        self.featureFlagger = featureFlagger
        self.aichatFullModeFeature = aichatFullModeFeature
        self.aichatContextualModeFeature = aichatContextualModeFeature
    }

    enum AIChatKeys {
        static let aiChatPayload = "aiChatPayload"
    }

    /// Invoked by the front-end code when it intends to open the AI Chat interface.
    /// The front-end can provide a payload that will be used the next time the AI Chat view is displayed.
    /// This function stores the payload and triggers a notification to handle the AI Chat opening process.
    @MainActor
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        var payload: AIChatPayload?
        if let paramsDict = params as? AIChatPayload {
            payload = paramsDict[AIChatKeys.aiChatPayload] as? AIChatPayload
        }

        NotificationCenter.default.post(
            name: .urlInterceptAIChat,
            object: payload,
            userInfo: nil
        )

        return nil
    }

    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable? {
        if let paramsDict = params as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict, options: []) {

            let decoder = JSONDecoder()
            do {
                let metric = try decoder.decode(AIChatMetric.self, from: jsonData)
                metricReportingHandler?.didReportMetric(metric)
            } catch {
                Logger.aiChat.debug("Failed to decode metric JSON in AIChatUserScript: \(error)")
            }
        }
        return nil
    }

    public func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) -> Encodable? {
        let defaults = AIChatNativeConfigValues.defaultValues

        let supportsFullMode: Bool
        let supportsContextualMode: Bool

        switch displayMode {
        case .fullTab:
            supportsFullMode = aichatFullModeFeature.isAvailable
            supportsContextualMode = false
        case .contextual:
            supportsFullMode = false
            supportsContextualMode = aichatContextualModeFeature.isAvailable
        case .none:
            supportsFullMode = aichatFullModeFeature.isAvailable || defaults.supportsAIChatFullMode
            supportsContextualMode = aichatContextualModeFeature.isAvailable || defaults.supportsAIChatContextualMode
        }

        return AIChatNativeConfigValues(
            isAIChatHandoffEnabled: defaults.isAIChatHandoffEnabled,
            supportsClosingAIChat: defaults.supportsClosingAIChat,
            supportsOpeningSettings: defaults.supportsOpeningSettings,
            supportsNativePrompt: defaults.supportsNativePrompt,
            supportsStandaloneMigration: experimentalAIChatManager.isStandaloneMigrationSupported,
            supportsNativeChatInput: defaults.supportsNativeChatInput,
            supportsURLChatIDRestoration: aichatFullModeFeature.isAvailable ? true : defaults.supportsURLChatIDRestoration,
            supportsFullChatRestoration: defaults.supportsFullChatRestoration,
            supportsPageContext: aichatContextualModeFeature.isAvailable ? true : defaults.supportsPageContext,
            supportsAIChatFullMode: aichatFullModeFeature.isAvailable ? true : defaults.supportsAIChatFullMode,
            supportsAIChatContextualMode: aichatContextualModeFeature.isAvailable ? true : defaults.supportsAIChatContextualMode,
            appVersion: AppVersion.shared.versionAndBuildNumber,
            supportsHomePageEntryPoint: defaults.supportsHomePageEntryPoint,
            supportsOpenAIChatLink: defaults.supportsOpenAIChatLink,
            supportsAIChatSync: featureFlagger.isFeatureOn(.aiChatSync)
        )
    }

    @MainActor
    public func getResponseState(params: Any, message: UserScriptMessage) async -> Encodable? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: params, options: [])
            let decodedStatus = try JSONDecoder().decode(AIChatStatus.self, from: jsonData)
            inputBoxHandler?.aiChatStatus = decodedStatus.status
            return nil
        } catch {
            return nil
        }
    }

    @MainActor
    func hideChatInput(params: Any, message: UserScriptMessage) async -> Encodable? {
        inputBoxHandler?.aiChatInputBoxVisibility = .hidden
        return nil
    }

    @MainActor
    func showChatInput(params: Any, message: UserScriptMessage) async -> Encodable? {
        inputBoxHandler?.aiChatInputBoxVisibility = .visible
        return nil
    }

    public func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable? {
        AIChatNativeHandoffData.defaultValuesWithPayload(payloadHandler?.consumeData() as? AIChatPayload)
    }

    func setPayloadHandler(_ payloadHandler: (any AIChatConsumableDataHandling)?) {
        self.payloadHandler = payloadHandler
    }

    func setAIChatInputBoxHandler(_ inputBoxHandler: (any AIChatInputBoxHandling)?) {
        self.inputBoxHandler = inputBoxHandler
    }

    func setMetricReportingHandler(_ metricHandler: (any AIChatMetricReportingHandling)?) {
        self.metricReportingHandler = metricHandler
    }

    // Workaround for WKWebView: see https://app.asana.com/1/137249556945/task/1211361207345641/comment/1211365575147531?focus=true
    func openKeyboard(params: Any, message: UserScriptMessage, webView: WKWebView?) async -> Encodable? {
        guard let paramsDict = params as? [String: Any] else {
            Logger.aiChat.error("Invalid params format for openKeyboard")
            return OpenKeyboardResponse(success: false, error: "Invalid parameters format")
        }
        guard let cssSelector = paramsDict["selector"] as? String, !cssSelector.isEmpty else {
            Logger.aiChat.error("Missing or empty CSS selector for openKeyboard")
            return OpenKeyboardResponse(success: false, error: "Missing or empty CSS selector")
        }

        guard let webView = webView else {
            Logger.aiChat.error("WebView not available for openKeyboard")
            return OpenKeyboardResponse(success: false, error: "WebView not available")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let javascript = """
                (function() {
                    try {
                        const element = document.querySelector('\(cssSelector)');
                        element?.focus?.();
                        return true;
                    } catch (error) {
                        console.error('Error focusing element:', error);
                        return false;
                    }
                })();
                """

                webView.evaluateJavaScript(javascript) { _, error in
                    if let error = error {
                        Logger.aiChat.error("Failed to execute openKeyboard JavaScript: \(error.localizedDescription)")
                        continuation.resume(returning: OpenKeyboardResponse(success: false, error: "JavaScript execution failed"))
                    } else {
                        continuation.resume(returning: OpenKeyboardResponse(success: true))
                    }
                }
            }
        }
    }

    func storeMigrationData(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any] else {
            return AIChatErrorResponse(reason: "invalid_params")
        }
        guard dict.keys.contains(AIChatMigrationParamKeys.serializedMigrationFile) else {
            return AIChatErrorResponse(reason: "invalid_params")
        }
        let serialized = dict[AIChatMigrationParamKeys.serializedMigrationFile] as? String
        return migrationStore.store(serialized)
    }

    func getMigrationDataByIndex(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any] else {
            return migrationStore.item(at: nil)
        }
        let index = dict[AIChatMigrationParamKeys.index] as? Int
        return migrationStore.item(at: index)
    }

    func getMigrationInfo(params: Any, message: UserScriptMessage) -> Encodable? {
        return migrationStore.info()
    }

    func clearMigrationData(params: Any, message: UserScriptMessage) -> Encodable? {
        return migrationStore.clear()
    }

    // MARK: - Sync

    func getSyncStatus(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            return AIChatPayloadResponse(payload: try syncHandler.getSyncStatus(featureAvailable: featureFlagger.isFeatureOn(.aiChatSync)))
        } catch {
            return AIChatErrorResponse(reason: "internal error")
        }
    }

    @MainActor func getScopedSyncAuthToken(params: Any, message: UserScriptMessage) async -> Encodable? {
        guard featureFlagger.isFeatureOn(.aiChatSync) else {
            return AIChatErrorResponse(reason: "sync disabled")
        }

        do {
            return AIChatPayloadResponse(payload: try await syncHandler.getScopedToken())
        } catch {
            let reason: String
            switch error {
            case SyncError.accountNotFound:
                reason = "sync off"
            case SyncError.noToken:
                reason = "token unavailable"
            case SyncError.invalidDataInResponse:
                reason = "invalid response"
            case SyncError.unexpectedStatusCode:
                reason = "unexpected status code"
            case AIChatSyncHandler.Errors.emptyResponse:
                reason = "empty response"
            default:
                reason = "internal error"
            }

            DailyPixel.fireDailyAndCount(pixel: .aiChatSyncScopedSyncTokenError, withAdditionalParameters: ["reason": reason])
            return AIChatErrorResponse(reason: reason)
        }
    }

    func encryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? {
        guard featureFlagger.isFeatureOn(.aiChatSync) else {
            return AIChatErrorResponse(reason: "sync disabled")
        }

        guard syncHandler.isSyncTurnedOn() else {
            return AIChatErrorResponse(reason: "sync off")
        }

        guard let dict = params as? [String: Any], let data = dict["data"] as? String else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSyncEncryptionError, withAdditionalParameters: ["reason": "invalid parameters"])
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        do {
            return AIChatPayloadResponse(payload: try syncHandler.encrypt(data))
        } catch {
            let reason: String
            switch error {
            case SyncError.failedToEncryptValue:
                reason = "encryption failed"
            default:
                reason = "internal error"
            }
            DailyPixel.fireDailyAndCount(pixel: .aiChatSyncEncryptionError, withAdditionalParameters: ["reason": reason])
            return AIChatErrorResponse(reason: reason)
        }
    }

    func decryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? {
        guard featureFlagger.isFeatureOn(.aiChatSync) else {
            return AIChatErrorResponse(reason: "sync disabled")
        }

        guard syncHandler.isSyncTurnedOn() else {
            return AIChatErrorResponse(reason: "sync off")
        }

        guard let dict = params as? [String: Any], let data = dict["data"] as? String else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSyncDecryptionError, withAdditionalParameters: ["reason": "invalid parameters"])
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        do {
            return AIChatPayloadResponse(payload: try syncHandler.decrypt(data))
        } catch {
            let reason = error.localizedDescription
            DailyPixel.fireDailyAndCount(pixel: .aiChatSyncDecryptionError, withAdditionalParameters: ["reason": reason])
            return AIChatErrorResponse(reason: "internal error")
        }
    }

    public func sendToSyncSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        return AIChatOKResponse()
    }

    public func sendToSetupSync(params: Any, message: UserScriptMessage) -> Encodable? {
        return AIChatOKResponse()
    }

    func setAIChatHistoryEnabled(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let enabled = dict["enabled"] as? Bool else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSyncHistoryEnabledError, withAdditionalParameters: ["reason": "invalid parameters"])
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        syncHandler.setAIChatHistoryEnabled(enabled)
        return nil
    }
}
// swiftlint:enable inclusive_language
