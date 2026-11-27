//
//  AIChatUserScript.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import ConcurrencyExtensions
import FoundationExtensions
import Foundation
import Persistence
import PixelKit
import UserScript
import WebKit

final class AIChatUserScript: NSObject, Subfeature {
    public let handler: AIChatUserScriptHandling
    public let featureName: String = "aiChat"
    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView? {
        didSet {
            if let webView {
                localModelRunPageID = ObjectIdentifier(webView)
            }
        }
    }
    private(set) var messageOriginPolicy: MessageOriginPolicy
    private(set) var messageDestinationPolicy: MessageOriginPolicy
    let messageFramePolicy: MessageFramePolicy
    private let customURLHostname: String?

    private var cancellables: Set<AnyCancellable> = []
    private let additionalClientToolPermissionSources = NSHashTable<AnyObject>.weakObjects()

    /// When true, the next two messages received from the page act as a readiness
    /// handshake: after the second message we push `submitOpenSettingsAction`. Mirrors
    /// the Windows two-phase TabId flag — by the second message the FE subscriptions
    /// are wired so the push won't be dropped.
    private(set) var pendingOpenSettingsAction = false
    private var openSettingsMessageCount = 0

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.browserTools?.register(self)
            self.localModelService?.register(self)
        }
    }

    /// Arms the two-phase open-settings handshake. Called when a Duck.ai tab is opened
    /// from Settings → AI Features so the FE's settings modal opens automatically once
    /// the page has wired up its subscriptions.
    func requestOpenSettingsAction() {
        pendingOpenSettingsAction = true
        openSettingsMessageCount = 0
    }

    private let browserTools: AIChatBrowserToolsService?
    private let localModelService: AIChatLocalModelServing?
    /// The page whose local runs this script ends when it goes, including runs a script it
    /// replaced started. `deinit` can't ask a web view that's already gone for its identity.
    private var localModelRunPageID: ObjectIdentifier?
    /// Nil uses the app's, which lives on the main actor and so can't be a default argument here.
    private let localModelAccessPrompt: LocalModelAccessAsking?
    private let bonusMessageLog: AIChatBonusMessageLogging?
    private let pixelFiring: PixelFiring?

    init(handler: AIChatUserScriptHandling,
         urlSettings: any KeyedStoring<AIChatDebugURLSettings>,
         browserTools: AIChatBrowserToolsService? = Application.appDelegate.aiChatBrowserToolsService,
         localModelService: AIChatLocalModelServing? = Application.appDelegate.localModelService,
         localModelAccessPrompt: LocalModelAccessAsking? = nil,
         bonusMessageLog: AIChatBonusMessageLogging? = nil,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.handler = handler
        self.pixelFiring = pixelFiring
        self.browserTools = browserTools
        self.localModelService = localModelService
        self.localModelAccessPrompt = localModelAccessPrompt
        self.bonusMessageLog = bonusMessageLog
        var originRules = [HostnameMatchingRule]()
        var destinationRules = [HostnameMatchingRule]()

        /// Default rule for DuckDuckGo AI Chat
        if let ddgDomain = URL.duckDuckGo.host {
            originRules.append(.exact(hostname: ddgDomain))
        }

        /// Default rule for standalone DuckDuckGo AI Chat
        if let duckAiDomain = URL.duckAi.host {
            originRules.append(.exact(hostname: duckAiDomain))
            destinationRules.append(.exact(hostname: duckAiDomain))
        }

        /// Check if a custom hostname is provided in the URL settings
        /// Custom hostnames are used for debugging purposes
        if let customURLHostname = urlSettings.customURLHostname {
            originRules.append(.exact(hostname: customURLHostname))
            destinationRules.append(.exact(hostname: customURLHostname))
        }

        self.messageOriginPolicy = .only(rules: originRules)
        self.messageDestinationPolicy = .only(rules: destinationRules)
        // A custom hostname may be a local http server, so only the main-frame part applies then.
        self.messageFramePolicy = urlSettings.customURLHostname == nil ? .secureMainFrame : .mainFrame
        self.customURLHostname = urlSettings.customURLHostname
        super.init()

        handler.aiChatNativePromptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prompt in
                self?.submitAIChatNativePrompt(prompt)
            }
            .store(in: &cancellables)

        handler.pageContextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageContext in
                self?.submitAIChatPageContext(pageContext)
            }
            .store(in: &cancellables)

        handler.selectionContextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selection in
                self?.submitAIChatSelectionContext(selection)
            }
            .store(in: &cancellables)

        handler.syncStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.submitSyncStatusChanged(status)
            }
            .store(in: &cancellables)

        handler.bonusRecordPayloadPublisher
            .sink { [weak self] payload in
                // The bonus service already delivers on the main queue, so push right away and keep the order of the changes.
                MainActor.assumeMainThread {
                    self?.submitBonusRecord(payload)
                }
            }
            .store(in: &cancellables)
    }

    private func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        guard let webView else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitAIChatNativePrompt.rawValue, params: prompt, for: self, into: webView)
    }

    private func submitAIChatPageContext(_ response: PageContextResponse) {
        guard let webView else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitAIChatPageContext.rawValue, params: response, for: self, into: webView)
    }

    private func submitAIChatSelectionContext(_ selection: AIChatSelectionContextData) {
        guard let webView else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitAIChatSelectionContext.rawValue, params: selection, for: self, into: webView)
    }

    private func submitOpenSettingsAction() {
        guard let webView,
              let host = webView.url?.host,
              messageDestinationPolicy.isAllowed(host) else {
            return
        }
        broker?.push(method: AIChatUserScriptMessages.submitOpenSettingsAction.rawValue, params: nil, for: self, into: webView)
    }

    private func submitSyncStatusChanged(_ status: AIChatSyncHandler.SyncStatus) {
        // Push only to websites matching origin policy
        guard let webView,
              let host = webView.url?.host,
              messageDestinationPolicy.isAllowed(host) else {
            return
        }

        broker?.push(method: AIChatUserScriptMessages.submitSyncStatusChanged.rawValue, params: status, for: self, into: webView)
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        let handler = resolveHandler(forMethodNamed: methodName)
        if handler != nil {
            advanceOpenSettingsHandshake()
        }
        return handler
    }

    private func advanceOpenSettingsHandshake() {
        guard pendingOpenSettingsAction else { return }
        openSettingsMessageCount += 1
        guard openSettingsMessageCount >= 2 else { return }
        pendingOpenSettingsAction = false
        openSettingsMessageCount = 0
        submitOpenSettingsAction()
    }

    /// Sync handlers expose sync secrets, so only Duck.ai's own main frame may call them,
    /// not any page that passes the duckduckgo.com origin policy.
    private func duckAIMainFrameOnly(_ handler: @escaping Subfeature.Handler) -> Subfeature.Handler {
        return { [customURLHostname] params, message in
            guard await message.isFromDuckAIMainFrame(customHostname: customURLHostname) else {
                return AIChatErrorResponse(reason: "sync unavailable")
            }
            return try await handler(params, message)
        }
    }

    private func resolveHandler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch AIChatUserScriptMessages(rawValue: methodName) {
        case .openAIChatSettings:
            return handler.openAIChatSettings
        case .getAIChatNativeConfigValues:
            return { @MainActor [weak self] params, message in
                guard let self else { return nil }
                return await self.getAIChatNativeConfigValues(params: params, message: message)
            }
        case .attachmentPrivacyShouldDisplay:
            return handler.attachmentPrivacyShouldDisplay
        case .closeAIChat:
            return handler.closeAIChat
        case .getAIChatNativePrompt:
            return handler.getAIChatNativePrompt
        case .openAIChat:
            return handler.openAIChat
        case .getAIChatNativeHandoffData:
            return handler.getAIChatNativeHandoffData
        case .recordChat:
            return handler.recordChat
        case .restoreChat:
            return handler.restoreChat
        case .removeChat:
            return handler.removeChat
        case .openSummarizationSourceLink:
            return handler.openSummarizationSourceLink
        case .openTranslationSourceLink:
            return handler.openTranslationSourceLink
        case .openAIChatLink:
            return handler.openAIChatLink
        case .getAIChatPageContext:
            return handler.getAIChatPageContext
        case .getAIChatSelectionContext:
            return handler.getAIChatSelectionContext
        case .getAIChatOpenTabs:
            return handler.getAIChatOpenTabs
        case .getAIChatTabContent:
            return handler.getAIChatTabContent

        // Client tools. The script stands for the chat in permission prompts, which the browser shows
        // and answers natively: the page has no message to answer them.
        case .executeClientTool:
            return { @MainActor [weak self] params, message in
                guard let self else { return nil }
                let prompter = self.isClientToolsPage(message.messageWebView?.url) ? self : nil
                return await self.handler.executeClientTool(params: params, message: message, permissionPrompter: prompter)
            }

        case .reportMetric:
            return handler.reportMetric
        case .togglePageContextTelemetry:
            return handler.togglePageContextTelemetry
        case .responseReceived:
            return handler.responseReceived
        case .storeMigrationData:
            return handler.storeMigrationData
        case .getMigrationDataByIndex:
            return handler.getMigrationDataByIndex
        case .getMigrationInfo:
            return handler.getMigrationInfo
        case .clearMigrationData:
            return handler.clearMigrationData
        case .getSyncStatus:
            return duckAIMainFrameOnly(handler.getSyncStatus)
        case .getScopedSyncAuthToken:
            return duckAIMainFrameOnly(handler.getScopedSyncAuthToken)
        case .encryptWithSyncMasterKey:
            return duckAIMainFrameOnly(handler.encryptWithSyncMasterKey)
        case .decryptWithSyncMasterKey:
            return duckAIMainFrameOnly(handler.decryptWithSyncMasterKey)
        case .sendToSetupSync:
            return duckAIMainFrameOnly(handler.sendToSetupSync)
        case .sendToSyncSettings:
            return duckAIMainFrameOnly(handler.sendToSyncSettings)
        case .setAIChatHistoryEnabled:
            return duckAIMainFrameOnly(handler.setAIChatHistoryEnabled)
        case .getAIChatBonusRecord:
            return handler.getAIChatBonusRecord
        case .getAIChatNewBonusRecord:
            return handler.getAIChatNewBonusRecord
        case .aiChatBonusRedeemOutcome:
            return handler.aiChatBonusRedeemOutcome
        case .aiChatBonusDismiss:
            return handler.aiChatBonusDismiss
        case .aiChatBonusEnd:
            return handler.aiChatBonusEnd
        case .voiceSessionStarted:
            return handler.voiceSessionStarted
        case .voiceSessionEnded:
            return handler.voiceSessionEnded
        case .voiceChatStartFailed:
            return handler.voiceChatStartFailed
        case .dictationStartFailed:
            return handler.dictationStartFailed
        case .customizeResponsesModalClosed:
            return handler.customizeResponsesModalClosed
        case .getAIChats:
            return handler.getAIChats
        case .askAboutPage:
            return handler.askAboutPage

        // Main-actor closures, so the reply isn't held up by a hop in the middle of the handler.
        case .startAIChatLocalRun:
            return { @MainActor [weak self] params, message in
                try self?.startAIChatLocalRun(params: params, message: message)
            }
        case .cancelAIChatLocalRun:
            return { @MainActor [weak self] params, _ in
                self?.cancelAIChatLocalRun(params: params)
            }
        case .requestAIChatLocalModelAccess:
            return { @MainActor [weak self] _, message in
                try await self?.requestAIChatLocalModelAccess(message: message)
            }

        default:
            return nil
        }
    }

    deinit {
        // Content-blocking updates replace every script while its page stays open. The page's runs
        // carry on and reach it through the new script, so only a page that's gone ends them.
        guard let localModelService, webView == nil, let pageID = localModelRunPageID else { return }
        Task { @MainActor in
            localModelService.cancelRuns(ownerID: pageID)
        }
    }
}

// MARK: - Local models

extension AIChatUserScript: AIChatLocalModelPushing {

    @MainActor
    func startAIChatLocalRun(params: Any, message: UserScriptMessage) throws -> Encodable? {
        guard let localModelService, isDuckAIPushDestination(message.messageWebView?.url) else {
            throw AIChatLocalModelRequestError.unavailable
        }
        guard let request: AIChatLocalRunRequest = DecodableHelper.decode(from: params) else {
            throw AIChatLocalModelRequestError.invalidArguments
        }
        let reply = try localModelService.startRun(request, for: self)
        localModelRunPageID = localModelPageID
        return reply
    }

    var localModelPage: AnyObject? {
        webView
    }

    /// A notification, but it also answers with `{}` in case the page sends it as a request.
    @MainActor
    func cancelAIChatLocalRun(params: Any) -> Encodable? {
        if let request: AIChatLocalRunCancelRequest = DecodableHelper.decode(from: params) {
            localModelService?.cancelRun(requestId: request.requestId, for: self)
        }
        return [String: String]()
    }

    /// Waits for the user's answer, so the page must not time it out.
    @MainActor
    func requestAIChatLocalModelAccess(message: UserScriptMessage) async throws -> Encodable? {
        guard let localModelService, isDuckAIPushDestination(message.messageWebView?.url) else {
            throw AIChatLocalModelRequestError.unavailable
        }
        let localModelAccessPrompt = localModelAccessPrompt ?? Application.appDelegate.localModelAccessPrompt
        let webView = message.messageWebView
        let result = try await localModelService.requestAccess { request in
            await localModelAccessPrompt.ask(from: webView, request: request)
        }
        return AIChatLocalModelAccessReply(result: result)
    }

    @MainActor
    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate) {
        pushToDuckAI(.submitAIChatLocalModelState, params: update)
    }

    @MainActor
    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk) {
        pushToDuckAI(.submitAIChatLocalRunChunk, params: chunk)
    }
}

// MARK: - Client tools

extension AIChatUserScript: ClientToolPermissionPrompting {

    @MainActor
    func presentClientToolPermissionPrompt(_ prompt: ClientToolPermissionPrompt) -> Bool {
        browserTools?.permissionPrompts.present(prompt, chatWebView: webView, prompter: self) ?? false
    }

    @MainActor
    func withdrawClientToolPermissionPrompt(requestID: String) {
        browserTools?.permissionPrompts.withdraw(requestID: requestID)
    }

    @MainActor
    func clientToolUseDidStart(requestID: String, toolName: String) {
        browserTools?.permissionPrompts.startUse(requestID: requestID, toolName: toolName, chatWebView: webView)
    }

    @MainActor
    func clientToolUseDidEnd(requestID: String, completed: Bool) {
        browserTools?.permissionPrompts.endUse(requestID: requestID, completed: completed)
    }

    /// The chat document is gone (navigated, reloaded or closed), so its pending calls finish as
    /// `cancelled`. Hiding the sidebar keeps the document, so it does not come here.
    @MainActor
    func cancelClientToolPermissionRequests() {
        browserTools?.clientToolPermissions.cancelRequests(from: self)
        for source in additionalClientToolPermissionSources.allObjects {
            guard let source = source as? AIChatClientToolPermissionCancellation else { continue }
            source.cancelClientToolPermissionRequests()
        }
        additionalClientToolPermissionSources.removeAllObjects()
    }

    @MainActor
    func registerClientToolPermissionCancellation(_ source: any AIChatClientToolPermissionCancellation) {
        additionalClientToolPermissionSources.add(source)
    }

    @MainActor
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable? {
        let response = await handler.getAIChatNativeConfigValues(params: params, message: message)
        guard var configValues = response as? AIChatNativeConfigValues else { return response }
        configValues.clientTools = clientToolsConfiguration(for: message)
        // Only where tools are offered, so Fire windows never send the answer metrics.
        configValues.supportsBrowserToolsAnswerMetrics = configValues.clientTools != nil
        // The model's state and text reach the page only through `pushToDuckAI`. A page it skips,
        // such as Duck.ai on duckduckgo.com, would wait for a summary that never arrives.
        if !isDuckAIPushDestination(message.messageWebView?.url) {
            configValues.localModel = nil
        }
        return configValues
    }

    @MainActor
    func isClientToolsDocumentReady(_ webView: WKWebView) -> Bool {
        self.webView === webView && webView.url != nil && !webView.isLoading && isClientToolsPage(webView.url)
    }

    /// Client tools are offered only to a Duck.ai chat outside Fire.
    @MainActor
    fileprivate func clientToolsConfiguration(for message: UserScriptMessage) -> ClientToolsConfiguration? {
        guard isClientToolsPage(message.messageWebView?.url),
              handler.isFireWindowProvider?() != true,
              let configuration = browserTools?.clientToolsConfiguration else { return nil }
        pixelFiring?.fire(BrowserToolsPixel.enabled, frequency: .daily)
        return configuration
    }

    @MainActor
    fileprivate func isClientToolsPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.isDuckAIURL { return true }
        guard let host = url.host else { return false }
        return messageDestinationPolicy.isAllowed(host)
    }
}

extension AIChatUserScript: AIChatBrowserToolsPushing {

    var pushTargetWebView: WKWebView? { webView }

    @MainActor
    func pushClientToolsChanged(_ data: ClientToolsChangedData) {
        guard handler.isFireWindowProvider?() != true,
              let webView, let broker,
              isClientToolsPage(webView.url) else { return }
        if data.clientTools != nil {
            pixelFiring?.fire(BrowserToolsPixel.enabled, frequency: .daily)
        }
        broker.push(method: AIChatUserScriptMessages.clientToolsChanged.rawValue, params: data, for: self, into: webView)
    }

    @MainActor
    func pushTabChanged(_ data: AIChatTabChangedData) {
        pushToDuckAI(.aiChatTabChanged, params: data)
    }

    /// Pushes the bonus record to this tab after it changes, so Duck.ai re-derives the offer state.
    private func submitBonusRecord(_ payload: AIChatBonusRecordPayload) {
        // Every tab has this script, so only a Duck.ai page gets it.
        guard let webView, let broker,
              let host = webView.url?.host,
              messageDestinationPolicy.isAllowed(host) else { return }
        broker.push(method: AIChatUserScriptMessages.submitAIChatBonusRecord.rawValue, params: payload, for: self, into: webView)
        bonusMessageLog?.record(.push, method: "\(AIChatUserScriptMessages.submitAIChatBonusRecord.rawValue) → \(host)", body: payload)
    }

    /// Only a Duck.ai page can receive these; every tab has this script, so the host is checked.
    private func pushToDuckAI(_ message: AIChatUserScriptMessages, params: Encodable?) {
        guard let webView, let broker, isDuckAIPushDestination(webView.url) else { return }
        broker.push(method: message.rawValue, params: params, for: self, into: webView)
    }

    fileprivate func isDuckAIPushDestination(_ url: URL?) -> Bool {
        guard let host = url?.host else { return false }
        return messageDestinationPolicy.isAllowed(host)
    }
}

@MainActor
protocol AIChatClientToolPermissionCancellation: AnyObject {
    func cancelClientToolPermissionRequests()
}
