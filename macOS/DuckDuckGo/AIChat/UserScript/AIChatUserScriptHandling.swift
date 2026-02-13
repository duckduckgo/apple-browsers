//
//  AIChatUserScriptHandling.swift
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
import AppKit
import Combine
import Common
import Foundation
import PixelKit
import Subscription
import UserScript
import OSLog
import PrivacyConfig
import DDGSync

protocol AIChatMetricReportingHandling {
    func didReportMetric(_ metric: AIChatMetric, completion: (() -> Void)?)
}

// swiftlint:disable inclusive_language
protocol AIChatUserScriptHandling {
    @MainActor func openAIChatSettings(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable?
    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable?
    @MainActor func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable?
    func recordChat(params: Any, message: UserScriptMessage) -> Encodable?
    func restoreChat(params: Any, message: UserScriptMessage) -> Encodable?
    func removeChat(params: Any, message: UserScriptMessage) -> Encodable?
    @MainActor func openSummarizationSourceLink(params: Any, message: UserScriptMessage) async -> Encodable?
    @MainActor func openTranslationSourceLink(params: Any, message: UserScriptMessage) async -> Encodable?
    @MainActor func openAIChatLink(params: Any, message: UserScriptMessage) async -> Encodable?
    var aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never> { get }

    func getAIChatPageContext(params: Any, message: UserScriptMessage) -> Encodable?
    var pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never> { get }
    var pageContextRequestedPublisher: AnyPublisher<Void, Never> { get }
    var chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never> { get }
    var syncStatusPublisher: AnyPublisher<AIChatSyncHandler.SyncStatus, Never> { get }

    var messageHandling: AIChatMessageHandling { get }
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt)
    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?)

    func togglePageContextTelemetry(params: Any, message: UserScriptMessage) -> Encodable?
    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable?
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
    public let messageHandling: AIChatMessageHandling
    public let aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never>
    public let pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never>
    public let pageContextRequestedPublisher: AnyPublisher<Void, Never>
    public let chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never>
    public let syncStatusPublisher: AnyPublisher<AIChatSyncHandler.SyncStatus, Never>

    private let aiChatNativePromptSubject = PassthroughSubject<AIChatNativePrompt, Never>()
    private let pageContextSubject = PassthroughSubject<AIChatPageContextData?, Never>()
    private let pageContextRequestedSubject = PassthroughSubject<Void, Never>()
    private let chatRestorationDataSubject = PassthroughSubject<AIChatRestorationData?, Never>()
    private let syncStatusSubject = PassthroughSubject<AIChatSyncHandler.SyncStatus, Never>()
    private var syncObserverCancellable: AnyCancellable?
    private let storage: AIChatPreferencesStorage
    private let windowControllersManager: WindowControllersManagerProtocol
    private let notificationCenter: NotificationCenter
    private let pixelFiring: PixelFiring?
    private let statisticsLoader: StatisticsLoader?
    private let syncServiceProvider: () -> DDGSyncing?
    private let featureFlagger: FeatureFlagger
    private let freeTrialConversionService: FreeTrialConversionInstrumentationService
    private let migrationStore = AIChatMigrationStore()

    init(
        storage: AIChatPreferencesStorage,
        messageHandling: AIChatMessageHandling = AIChatMessageHandler(),
        windowControllersManager: WindowControllersManagerProtocol,
        pixelFiring: PixelFiring?,
        statisticsLoader: StatisticsLoader?,
        syncServiceProvider: @escaping () -> DDGSyncing?,
        featureFlagger: FeatureFlagger,
        freeTrialConversionService: FreeTrialConversionInstrumentationService = Application.appDelegate.freeTrialConversionService,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage
        self.messageHandling = messageHandling
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
        self.statisticsLoader = statisticsLoader
        self.syncServiceProvider = syncServiceProvider
        self.notificationCenter = notificationCenter
        self.featureFlagger = featureFlagger
        self.freeTrialConversionService = freeTrialConversionService
        self.aiChatNativePromptPublisher = aiChatNativePromptSubject.eraseToAnyPublisher()
        self.pageContextPublisher = pageContextSubject.eraseToAnyPublisher()
        self.pageContextRequestedPublisher = pageContextRequestedSubject.eraseToAnyPublisher()
        self.chatRestorationDataPublisher = chatRestorationDataSubject.eraseToAnyPublisher()
        self.syncStatusPublisher = syncStatusSubject.eraseToAnyPublisher()

        setUpSyncStatusObserverIfNeeded()
    }

    enum AIChatKeys {
        static let aiChatPayload = "aiChatPayload"
        static let serializedChatData = "serializedChatData"
    }

    @MainActor public func openAIChatSettings(params: Any, message: UserScriptMessage) async -> Encodable? {
        windowControllersManager.showTab(with: .settings(pane: .aiChat))
        return nil
    }

    public func getAIChatNativeConfigValues(params: Any, message: UserScriptMessage) async -> Encodable? {
        messageHandling.getDataForMessageType(.nativeConfigValues)
    }

    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        let isSidebar = await message.messageWebView?.url?.hasAIChatSidebarPlacementParameter == true

        if isSidebar {
            await windowControllersManager.mainWindowController?.mainViewController.aiChatSidebarPresenter.collapseSidebar(withAnimation: true)
        } else {
            await windowControllersManager.mainWindowController?.mainViewController.closeTab(nil)
        }
        return nil
    }

    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable? {
        messageHandling.getDataForMessageType(.nativePrompt)
    }

    func getAIChatPageContext(params: Any, message: any UserScriptMessage) -> Encodable? {
        guard let payload: GetPageContext = DecodableHelper.decode(from: params) else {
            return nil
        }

        let pageContext = messageHandling.getDataForMessageType(.pageContext) as? AIChatPageContextData

        if pageContext == nil, payload.reason == "userAction" {
            pageContextRequestedSubject.send()
        }

        return PageContextResponse(pageContext: pageContext)
    }

    @MainActor
    func openAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        var payload: AIChatPayload?
        if let paramsDict = params as? AIChatPayload {
            payload = paramsDict[AIChatKeys.aiChatPayload] as? AIChatPayload
        }

        notificationCenter.post(name: .aiChatNativeHandoffData, object: payload, userInfo: nil)
        return nil
    }

    public func getAIChatNativeHandoffData(params: Any, message: UserScriptMessage) -> Encodable? {
       messageHandling.getDataForMessageType(.nativeHandoffData)
    }

    public func recordChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        guard let params = params as? [String: String],
              let data = params[AIChatKeys.serializedChatData]
        else { return nil }

        messageHandling.setData(data, forMessageType: .chatRestorationData)
        chatRestorationDataSubject.send(data)
        return nil
    }

    public func restoreChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        guard let data = messageHandling.getDataForMessageType(.chatRestorationData) as? String
        else { return nil }

        return [AIChatKeys.serializedChatData: data]
    }

    public func removeChat(params: Any, message: any UserScriptMessage) -> (any Encodable)? {
        messageHandling.setData(nil, forMessageType: .chatRestorationData)
        chatRestorationDataSubject.send(nil)
        return nil
    }

    @MainActor func openSummarizationSourceLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        var modifiedParams = params as? [String: Any] ?? [:]
        modifiedParams["name"] = "summarization"
        return await openAIChatLink(params: modifiedParams, message: message)
    }

    @MainActor func openTranslationSourceLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        var modifiedParams = params as? [String: Any] ?? [:]
        modifiedParams["name"] = "translation"
        return await openAIChatLink(params: modifiedParams, message: message)
    }

    @MainActor func openAIChatLink(params: Any, message: any UserScriptMessage) async -> (any Encodable)? {
        guard let openLinkParams: OpenLink = DecodableHelper.decode(from: params), let url = openLinkParams.url.url
        else { return nil }

        let isSidebar = message.messageWebView?.url?.hasAIChatSidebarPlacementParameter == true

        switch openLinkParams.target {
        case .sameTab where isSidebar == false: // for same tab outside of sidebar we force opening new tab to keep the AI chat tab
            windowControllersManager.show(url: url, source: .switchToOpenTab, newTab: true, selected: true)
        default:
            windowControllersManager.open(url, source: .link, target: nil, event: NSApp.currentEvent)
        }

        // Fire appropriate pixel based on the name parameter
        if let name = openLinkParams.name {
            switch name {
            case .summarization:
                pixelFiring?.fire(AIChatPixel.aiChatSummarizeSourceLinkClicked, frequency: .dailyAndStandard)
            case .translation:
                pixelFiring?.fire(AIChatPixel.aiChatTranslationSourceLinkClicked, frequency: .dailyAndStandard)
            case .pageContext:
                pixelFiring?.fire(AIChatPixel.aiChatPageContextSourceLinkClicked, frequency: .dailyAndStandard)
            }
        }

        return nil
    }

    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        aiChatNativePromptSubject.send(prompt)
    }

    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?) {
        pageContextSubject.send(pageContext)
    }

    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable? {
        if let paramsDict = params as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict, options: []) {

            let decoder = JSONDecoder()
            do {
                let metric = try decoder.decode(AIChatMetric.self, from: jsonData)
                didReportMetric(metric, completion: nil)
            } catch {
                Logger.aiChat.debug("Failed to decode metric JSON in AIChatUserScript: \(error)")
            }
        }
        return nil
    }

    func togglePageContextTelemetry(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let payload: TogglePageContextTelemetry = DecodableHelper.decode(from: params) else {
            return nil
        }
        let pixel: PixelKitEvent = {
            if payload.enabled {
                return AIChatPixel.aiChatPageContextAdded(automaticEnabled: storage.shouldAutomaticallySendPageContext)
            }
            return AIChatPixel.aiChatPageContextRemoved(automaticEnabled: storage.shouldAutomaticallySendPageContext)
        }()
        pixelFiring?.fire(pixel, frequency: .dailyAndStandard)
        return nil
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

    private func setUpSyncStatusObserverIfNeeded(syncService: DDGSyncing? = nil) {
        guard syncObserverCancellable == nil else { return }
        guard let syncService = syncService ?? syncServiceProvider() else { return }

        syncObserverCancellable = syncService.authStatePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSyncStatusChanged()
            }
    }

    private func handleSyncStatusChanged() {
        guard let syncHandler = makeSyncHandler() else { return }
        do {
            let status = try syncHandler.getSyncStatus(featureAvailable: featureFlagger.isFeatureOn(.aiChatSync))
            syncStatusSubject.send(status)
        } catch {
            return
        }
    }

    func getSyncStatus(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            guard let syncHandler = makeSyncHandler() else {
                return AIChatErrorResponse(reason: "internal error")
            }
            return AIChatPayloadResponse(payload: try syncHandler.getSyncStatus(featureAvailable: featureFlagger.isFeatureOn(.aiChatSync)))
        } catch {
            return AIChatErrorResponse(reason: "internal error")
        }
    }

    @MainActor func getScopedSyncAuthToken(params: Any, message: UserScriptMessage) async -> Encodable? {
        guard featureFlagger.isFeatureOn(.aiChatSync) else {
            return AIChatErrorResponse(reason: "sync unavailable")
        }

        func makeErrorResponse(_ reason: String) -> AIChatErrorResponse {
            pixelFiring?.fire(AIChatPixel.aiChatSyncScopedSyncTokenError(reason: reason), frequency: .dailyAndStandard)
            return AIChatErrorResponse(reason: reason)
        }

        do {
            guard let syncHandler = makeSyncHandler() else {
                return makeErrorResponse("internal error")
            }
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
            return makeErrorResponse(reason)
        }
    }

    func encryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? {
        guard featureFlagger.isFeatureOn(.aiChatSync) else {
            return AIChatErrorResponse(reason: "sync unavailable")
        }

        guard let syncHandler = makeSyncHandler(), syncHandler.isSyncTurnedOn() else {
            return AIChatErrorResponse(reason: "sync off")
        }

        guard let dict = params as? [String: Any], let data = dict["data"] as? String else {
            pixelFiring?.fire(AIChatPixel.aiChatSyncEncryptionError(reason: "invalid parameters"), frequency: .dailyAndStandard)
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
            pixelFiring?.fire(AIChatPixel.aiChatSyncEncryptionError(reason: reason), frequency: .dailyAndStandard)
            return AIChatErrorResponse(reason: reason)
        }
    }

    func decryptWithSyncMasterKey(params: Any, message: UserScriptMessage) -> Encodable? {
        guard featureFlagger.isFeatureOn(.aiChatSync) else {
            return AIChatErrorResponse(reason: "sync unavailable")
        }

        guard let syncHandler = makeSyncHandler(), syncHandler.isSyncTurnedOn() else {
            return AIChatErrorResponse(reason: "sync off")
        }

        guard let dict = params as? [String: Any], let data = dict["data"] as? String else {
            pixelFiring?.fire(AIChatPixel.aiChatSyncDecryptionError(reason: "invalid parameters"), frequency: .dailyAndStandard)
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        do {
            return AIChatPayloadResponse(payload: try syncHandler.decrypt(data))
        } catch {
            let reason = error.localizedDescription
            pixelFiring?.fire(AIChatPixel.aiChatSyncDecryptionError(reason: reason), frequency: .dailyAndStandard)
            return AIChatErrorResponse(reason: "internal error")
        }
    }

    public func sendToSyncSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        Task { @MainActor [weak self] in
            self?.windowControllersManager.showTab(with: .settings(pane: .sync))
        }
        return AIChatOKResponse()
    }

    public func sendToSetupSync(params: Any, message: UserScriptMessage) -> Encodable? {
        guard featureFlagger.isFeatureOn(.aiChatSync), let syncHandler = makeSyncHandler() else {
            return AIChatErrorResponse(reason: "setup disabled")
        }

        guard syncHandler.isSyncTurnedOn() == false else {
            return AIChatErrorResponse(reason: "sync already on")
        }

        Task { @MainActor in
            DeviceSyncCoordinator()?.startDeviceSyncFlow(source: .aiChat, completion: nil)
        }
        return AIChatOKResponse()
    }

    func setAIChatHistoryEnabled(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let enabled = dict["enabled"] as? Bool else {
            pixelFiring?.fire(AIChatPixel.aiChatSyncHistoryEnabledError(reason: "invalid parameters"), frequency: .dailyAndStandard)
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        syncServiceProvider()?.setAIChatHistoryEnabled(enabled)
        return nil
    }

    private func makeSyncHandler() -> AIChatSyncHandler? {
        guard let sync = syncServiceProvider() else {
            return nil
        }
        setUpSyncStatusObserverIfNeeded(syncService: sync)
        guard sync.authState != .initializing else {
            return nil
        }
        return AIChatSyncHandler(sync: sync)
    }
}
// swiftlint:enable inclusive_language

extension NSNotification.Name {
    static let aiChatNativeHandoffData: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.aiChatNativeHandoffData")
}

extension AIChatUserScriptHandler {

    struct OpenLink: Codable, Equatable {
        let url: String
        let target: OpenTarget
        let name: Name?

        enum OpenTarget: String, Codable, Equatable {
            case sameTab = "same-tab"
            case newTab = "new-tab"
            case newWindow = "new-window"
        }

        enum Name: String, Codable, Equatable {
            case summarization
            case translation
            case pageContext
        }
    }

    struct GetPageContext: Codable, Equatable {
        let reason: String
    }

    struct TogglePageContextTelemetry: Codable, Equatable {
        let enabled: Bool
    }
}

extension AIChatUserScriptHandler: AIChatMetricReportingHandling {

    func didReportMetric(_ metric: AIChatMetric, completion: (() -> Void)? = nil) {
        switch metric.metricName {
        case .userDidSubmitFirstPrompt:
            notificationCenter.post(name: .aiChatUserDidSubmitPrompt, object: nil)
            markDuckAIActivatedIfNeeded(metric)
            pixelFiring?.fire(AIChatPixel.aiChatMetricStartNewConversation, frequency: .standard)
            DispatchQueue.main.async { [self] in
                refreshAtbs(completion: completion)
            }
        case .userDidSubmitPrompt:
            notificationCenter.post(name: .aiChatUserDidSubmitPrompt, object: nil)
            markDuckAIActivatedIfNeeded(metric)
            pixelFiring?.fire(AIChatPixel.aiChatMetricSentPromptOngoingChat, frequency: .standard)
            DispatchQueue.main.async { [self] in
                refreshAtbs(completion: completion)
            }
        default:
            completion?()
            return
        }
    }

    private func refreshAtbs(completion: (() -> Void)? = nil) {
        statisticsLoader?.refreshRetentionAtbOnDuckAiPromptSubmition {
            completion?()
        }
    }

    private func markDuckAIActivatedIfNeeded(_ metric: AIChatMetric) {
        guard let tier = metric.modelTier, case .plus = tier else { return }
        freeTrialConversionService.markDuckAIActivated()
    }

}
