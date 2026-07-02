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
import FoundationExtensions
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

enum AIChatUserScriptErrorFailureReason: String {
    case keyNotFound = "key_not_found"
    case typeMismatch = "type_mismatch"
    case valueNotFound = "value_not_found"
    case dataCorrupted = "data_corrupted"
    case unknownDecodingError = "unknown_decoding_error"

    init(error: Error) {
        switch error {
        case DecodingError.keyNotFound(_, _):
            self = .keyNotFound
        case DecodingError.typeMismatch(_, _):
            self = .typeMismatch
        case DecodingError.valueNotFound(_, _):
            self = .valueNotFound
        case DecodingError.dataCorrupted(_):
            self = .dataCorrupted
        default:
            self = .unknownDecodingError
        }
    }
}

enum AIChatUserScriptErrorEvent: Equatable {
    case reportMetricDecodingFailed(error: Error?, failureReason: AIChatUserScriptErrorFailureReason)

    static func == (lhs: AIChatUserScriptErrorEvent, rhs: AIChatUserScriptErrorEvent) -> Bool {
        switch (lhs, rhs) {
        case (.reportMetricDecodingFailed, .reportMetricDecodingFailed):
            return true
        }
    }
}

final class AIChatUserScriptErrorEventMapper: EventMapping<AIChatUserScriptErrorEvent> {

    init(pixelFiring: PixelFiring?) {
        super.init { event, _, _, _ in
            switch event {
            case .reportMetricDecodingFailed(let error, let failureReason):
                let nsError = error.map { $0 as NSError }
                pixelFiring?.fire(
                    AIChatPixel.aiChatReportMetricDecodeError(nsError, failureReason: failureReason),
                    frequency: .dailyAndCount
                )
            }
        }
    }

    @available(*, unavailable, message: "Use init(pixelFiring:) instead")
    override init(mapping: @escaping EventMapping<AIChatUserScriptErrorEvent>.Mapping) {
        fatalError("Use init(pixelFiring:) instead")
    }
}

// swiftlint:disable inclusive_language
protocol AIChatUserScriptHandling: AnyObject {
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

    @MainActor func getAIChatPageContext(params: Any, message: UserScriptMessage) async -> Encodable?
    func getAIChatSelectionContext(params: Any, message: UserScriptMessage) -> Encodable?
    var pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never> { get }
    var selectionContextPublisher: AnyPublisher<AIChatSelectionContextData, Never> { get }
    var pageContextRequestedPublisher: AnyPublisher<Void, Never> { get }
    var pageContextConsumedPublisher: AnyPublisher<Void, Never> { get }
    var pageContextRemovedPublisher: AnyPublisher<Void, Never> { get }
    var chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never> { get }
    var syncStatusPublisher: AnyPublisher<AIChatSyncHandler.SyncStatus, Never> { get }

    var messageHandling: AIChatMessageHandling { get }

    var isFireWindowProvider: (() -> Bool)? { get set }

    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt)
    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?)
    func submitAIChatSelectionContext(_ selection: AIChatSelectionContextData)

    @MainActor func getAIChatOpenTabs(params: Any, message: UserScriptMessage) async -> Encodable?
    @MainActor func getAIChatTabContent(params: Any, message: UserScriptMessage) async -> Encodable?
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

    /// Voice-session lifecycle messages from Duck.ai. Native rebroadcasts them as
    /// `aiChatVoiceSessionStarted` / `aiChatVoiceSessionEnded` notifications carrying the
    /// source `WKWebView` as `object`, so observers (`VoiceSessionTracker`) can map back
    /// to the owning `Tab` and decide whether to focus it instead of opening a new one.
    @MainActor func voiceSessionStarted(params: Any, message: UserScriptMessage) async -> Encodable?
    @MainActor func voiceSessionEnded(params: Any, message: UserScriptMessage) async -> Encodable?

    /// Posted by Duck.ai when `getUserMedia()` rejects while starting voice chat. Native uses
    /// the carried `reason` (the JS error name, e.g. `"NotAllowedError"`) to decide whether
    /// to surface a system-permission remediation prompt.
    @MainActor func voiceChatStartFailed(params: Any, message: UserScriptMessage) async -> Encodable?

    /// Posted by Duck.ai when `getUserMedia()` rejects while starting dictation. Mirrors
    /// `voiceChatStartFailed` but surfaces dictation-specific remediation copy.
    @MainActor func dictationStartFailed(params: Any, message: UserScriptMessage) async -> Encodable?
}

final class AIChatUserScriptHandler: AIChatUserScriptHandling {
    public let messageHandling: AIChatMessageHandling
    public let aiChatNativePromptPublisher: AnyPublisher<AIChatNativePrompt, Never>
    public let pageContextPublisher: AnyPublisher<AIChatPageContextData?, Never>
    public let selectionContextPublisher: AnyPublisher<AIChatSelectionContextData, Never>
    public let pageContextRequestedPublisher: AnyPublisher<Void, Never>
    public let pageContextConsumedPublisher: AnyPublisher<Void, Never>
    public let pageContextRemovedPublisher: AnyPublisher<Void, Never>
    public let chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never>
    public let syncStatusPublisher: AnyPublisher<AIChatSyncHandler.SyncStatus, Never>

    private let aiChatNativePromptSubject = PassthroughSubject<AIChatNativePrompt, Never>()
    private let pageContextSubject = PassthroughSubject<AIChatPageContextData?, Never>()
    private let selectionContextSubject = PassthroughSubject<AIChatSelectionContextData, Never>()
    private let pageContextRequestedSubject = PassthroughSubject<Void, Never>()
    private let pageContextConsumedSubject = PassthroughSubject<Void, Never>()
    private let pageContextRemovedSubject = PassthroughSubject<Void, Never>()
    private let chatRestorationDataSubject = PassthroughSubject<AIChatRestorationData?, Never>()
    private let syncStatusSubject = PassthroughSubject<AIChatSyncHandler.SyncStatus, Never>()
    private var syncObserverCancellable: AnyCancellable?
    private var storage: AIChatPreferencesStorage
    private let windowControllersManager: WindowControllersManagerProtocol
    private let notificationCenter: NotificationCenter
    private let pixelFiring: PixelFiring?
    private let aiChatUserScriptErrorEventMapper: EventMapping<AIChatUserScriptErrorEvent>
    private let statisticsLoader: StatisticsLoader?
    private let syncServiceProvider: () -> DDGSyncing?
    private let syncErrorHandler: SyncErrorHandling
    private let featureFlagger: FeatureFlagger
    private let freeTrialConversionService: FreeTrialConversionInstrumentationService
    private let migrationStore = AIChatMigrationStore()
    private let voiceChatFailureHandler: DuckAiVoiceChatFailureHandling

    var isFireWindowProvider: (() -> Bool)?

    init(
        storage: AIChatPreferencesStorage,
        messageHandling: AIChatMessageHandling = AIChatMessageHandler(),
        windowControllersManager: WindowControllersManagerProtocol,
        pixelFiring: PixelFiring?,
        statisticsLoader: StatisticsLoader?,
        syncServiceProvider: @escaping () -> DDGSyncing?,
        syncErrorHandler: SyncErrorHandling,
        featureFlagger: FeatureFlagger,
        aiChatUserScriptErrorEventMapper: EventMapping<AIChatUserScriptErrorEvent>? = nil,
        freeTrialConversionService: FreeTrialConversionInstrumentationService = Application.appDelegate.freeTrialConversionService,
        notificationCenter: NotificationCenter = .default,
        voiceChatFailureHandler: DuckAiVoiceChatFailureHandling? = nil
    ) {
        self.storage = storage
        self.messageHandling = messageHandling
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
        self.aiChatUserScriptErrorEventMapper = aiChatUserScriptErrorEventMapper ?? AIChatUserScriptErrorEventMapper(pixelFiring: pixelFiring)
        self.statisticsLoader = statisticsLoader
        self.syncServiceProvider = syncServiceProvider
        self.syncErrorHandler = syncErrorHandler
        self.notificationCenter = notificationCenter
        self.featureFlagger = featureFlagger
        self.freeTrialConversionService = freeTrialConversionService
        self.voiceChatFailureHandler = voiceChatFailureHandler ?? DuckAiVoiceChatFailureHandler(
            permissionCenterPresenter: NotificationCenterPermissionCenterPresenter(
                notificationCenter: notificationCenter,
                // Posting the notification is enough — the address-bar observer dedupes
                // against its own popover state. From here we can't see UI state without
                // pulling AppKit in, so the probe defaults to `false`.
                isPresentedProvider: { _ in false }
            )
        )
        self.aiChatNativePromptPublisher = aiChatNativePromptSubject.eraseToAnyPublisher()
        self.pageContextPublisher = pageContextSubject.eraseToAnyPublisher()
        self.selectionContextPublisher = selectionContextSubject.eraseToAnyPublisher()
        self.pageContextRequestedPublisher = pageContextRequestedSubject.eraseToAnyPublisher()
        self.pageContextConsumedPublisher = pageContextConsumedSubject.eraseToAnyPublisher()
        self.pageContextRemovedPublisher = pageContextRemovedSubject.eraseToAnyPublisher()
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
        let isFireWindow = isFireWindowProvider?() ?? false
        return messageHandling.getNativeConfigValues(isFireWindow: isFireWindow)
    }

    func closeAIChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        if let floatingWindow = await message.messageWebView?.window as? AIChatFloatingWindow {
            await MainActor.run {
                floatingWindow.close()
            }
            return nil
        }

        let isSidebar = await message.messageWebView?.url?.hasAIChatSidebarPlacementParameter == true

        if isSidebar {
            guard let mainViewController = await windowControllersManager.mainWindowController?.mainViewController else {
                return nil
            }

            if let currentTabID = await mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab.uuid {
                await mainViewController.aiChatCoordinator.closeChat(for: currentTabID, withAnimation: true)
            }
        } else {
            await windowControllersManager.mainWindowController?.mainViewController.closeTab(nil)
        }
        return nil
    }

    func getAIChatNativePrompt(params: Any, message: UserScriptMessage) async -> Encodable? {
        messageHandling.getDataForMessageType(.nativePrompt)
    }

    @MainActor
    func getAIChatPageContext(params: Any, message: any UserScriptMessage) async -> Encodable? {
        guard let payload: GetPageContext = DecodableHelper.decode(from: params) else {
            return nil
        }

        let pageContext = messageHandling.getDataForMessageType(.pageContext) as? AIChatPageContextData

        // On an explicit user action (Ask-About-Page chip or tapping a suggestion), the user wants
        // the page CONTENT attached. If we only have a signals-only payload (auto-attach off) or no
        // context, trigger a fresh collection and await it so the content is returned directly in
        // this response instead of arriving later via the submit push.
        if payload.reason == "userAction" {
            let hasAttachedContent = pageContext != nil
                && pageContext?.attached != false
                && !(pageContext?.content.isEmpty ?? true)
            if !hasAttachedContent {
                let collected = await requestPageContextAndWait()
                return PageContextResponse(pageContext: collected)
            }
        }

        return PageContextResponse(pageContext: pageContext)
    }

    /// Triggers a fresh page-context collection and awaits the collected result, so
    /// `getAIChatPageContext` can return the content directly via request/response instead of
    /// returning `nil` and relying on the later `submitAIChatPageContext` push. The pushed context
    /// arrives back through `pageContextSubject`; we subscribe before firing the request so a fast
    /// collection can't slip through, and race the result against `timeout`. The submit push still
    /// fires (it serves auto-collect/navigation flows), so the FE may also receive it that way.
    /// Mirrors `PageContextUserScript.collectAndWait`.
    @MainActor
    private func requestPageContextAndWait(timeout: TimeInterval = 5) async -> AIChatPageContextData? {
        let collectedContext = AsyncStream<AIChatPageContextData?> { continuation in
            var cancellable: AnyCancellable?
            cancellable = pageContextSubject
                .first()
                .sink { result in
                    continuation.yield(result)
                    continuation.finish()
                }
            continuation.onTermination = { _ in cancellable?.cancel() }
            pageContextRequestedSubject.send()
        }

        return await withTaskGroup(of: AIChatPageContextData?.self) { group in
            group.addTask {
                for await result in collectedContext { return result }
                return nil
            }
            group.addTask {
                try? await Task.sleep(interval: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    func getAIChatSelectionContext(params: Any, message: any UserScriptMessage) -> Encodable? {
        // Mirrors `getAIChatPageContext`: the FE pulls this on init to retrieve selections attached
        // before it was ready to receive pushes. Returned non-destructively — the FE dedupes by `id`.
        return SelectionContextResponse(selections: messageHandling.getSelectionContexts())
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
            windowControllersManager.open(url, source: .link, target: nil, with: NSApp.currentEvent)
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

    func submitAIChatSelectionContext(_ selection: AIChatSelectionContextData) {
        selectionContextSubject.send(selection)
    }

    func reportMetric(params: Any, message: UserScriptMessage) async -> Encodable? {
        guard let paramsDict = params as? [String: Any] else {
            aiChatUserScriptErrorEventMapper.fire(.reportMetricDecodingFailed(
                error: nil,
                failureReason: .typeMismatch
            ))
            return nil
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: paramsDict, options: [])
            let metric = try JSONDecoder().decode(AIChatMetric.self, from: jsonData)
            didReportMetric(metric, completion: nil)
        } catch {
            Logger.aiChat.debug("Failed to decode metric JSON in AIChatUserScript: \(error)")
            aiChatUserScriptErrorEventMapper.fire(.reportMetricDecodingFailed(
                error: error,
                failureReason: AIChatUserScriptErrorFailureReason(error: error)
            ))
        }
        return nil
    }

    // MARK: - Tab Picker

    @MainActor
    func getAIChatOpenTabs(params: Any, message: UserScriptMessage) async -> Encodable? {
        // Source tabs from all windows (except Fire Windows) relative to the window the picker was
        // opened in — see `AIChatTabPickerSource`. A Fire Window only sees its own tabs.
        guard let origin = AIChatTabPickerSource.originTabCollectionViewModel(for: message.messageWebView, in: windowControllersManager) else {
            return AIChatOpenTabsResponse(tabs: [])
        }
        let currentTabId = origin.selectedTabViewModel?.tab.uuid

        let faviconManager = NSApp.delegateTyped.faviconManager
        let tabMetadata: [AIChatTabMetadata] = AIChatTabPickerSource.attachableTabs(forOrigin: origin, in: windowControllersManager).compactMap { tab in
            guard case .url(let url, _, _) = tab.content else { return nil }
            let favicon: [AIChatPageContextData.PageContextFavicon]
            if let image = faviconManager.getCachedFavicon(for: url, sizeCategory: .small)?.image,
               let base64 = image.base64PNGDataURL {
                favicon = [AIChatPageContextData.PageContextFavicon(href: base64, rel: "icon")]
            } else {
                favicon = []
            }
            return AIChatTabMetadata(
                tabId: tab.uuid,
                title: tab.title ?? url.host ?? "",
                url: url.absoluteString,
                favicon: favicon,
                isCurrentTab: tab.uuid == currentTabId
            )
        }

        return AIChatOpenTabsResponse(tabs: tabMetadata)
    }

    @MainActor
    func getAIChatTabContent(params: Any, message: UserScriptMessage) async -> Encodable? {
        guard let params: AIChatTabContentParams = DecodableHelper.decode(from: params) else {
            return AIChatTabContentResponse(pageContext: nil)
        }

        guard let origin = AIChatTabPickerSource.originTabCollectionViewModel(for: message.messageWebView, in: windowControllersManager) else {
            return AIChatTabContentResponse(pageContext: nil)
        }

        // Wakes the tab if it's suspended so its content can be extracted instead of being dropped.
        // The JS-bridge consumer is always a tab-picker flow (sidebar's `@` picker), so the result
        // is always a tab-picker context — stamp `tabId` so the duck.ai web app sees the
        // discriminator and treats it as "additional context", not "current page".
        let extracted = await Self.extractPageContext(forTabId: params.tabId, origin: origin, in: windowControllersManager)
        return AIChatTabContentResponse(pageContext: extracted?.withTabId(params.tabId))
    }

    /// Extracts a fresh `AIChatPageContextData` from the given `Tab` by invoking its
    /// `PageContextUserScript`. Returns `nil` if the user script isn't attached or the
    /// page-context script's webView has been released (e.g. suspended tab).
    ///
    /// The returned page context carries **no `tabId`** — callers stamp it themselves
    /// (`getAIChatTabContent` always stamps; the omnibar submit path strips for the active
    /// tab and stamps for the rest).
    ///
    /// Shared by the JS-bridge consumer (`getAIChatTabContent`) and the omnibar's submit
    /// path so both go through the exact same extraction + favicon-enrichment logic.
    @MainActor
    static func extractPageContext(from tab: Tab, timeout: TimeInterval = 5) async -> AIChatPageContextData? {
        // Access the tab's PageContextUserScript via its content blocking assets
        guard let userScripts = tab.userContentController?.contentBlockingAssets?.userScripts as? UserScripts,
              let pageContextScript = userScripts.pageContextUserScript else {
            return nil
        }

        // Ensure the webView is set — it may have been released for background tabs
        if pageContextScript.webView == nil {
            pageContextScript.webView = tab.webView
        }

        // If webView is still nil (e.g. suspended tab), return immediately instead of waiting for timeout
        guard pageContextScript.webView != nil else {
            return nil
        }

        let pageContext = await pageContextScript.collectAndWait(timeout: timeout)

        // Replace favicon URLs with base64-encoded data to avoid CSP blocking in the sidebar
        return pageContext.map { ctx -> AIChatPageContextData in
            guard let pageURL = URL(string: ctx.url),
                  let favicon = NSApp.delegateTyped.faviconManager.getCachedFavicon(for: pageURL, sizeCategory: .small)?.image,
                  let base64 = favicon.base64PNGDataURL else {
                return ctx
            }
            let faviconEntry = AIChatPageContextData.PageContextFavicon(href: base64, rel: "icon")
            return AIChatPageContextData(
                title: ctx.title,
                favicon: [faviconEntry],
                url: ctx.url,
                content: ctx.content,
                truncated: ctx.truncated,
                fullContentLength: ctx.fullContentLength,
                attachable: ctx.attachable
            )
        }
    }

    /// Resolves `tabId` to a live `Tab` within the origin scope — **waking a suspended/unloaded tab
    /// if needed** — then extracts its page context. A freshly-woken tab's page isn't loaded yet, so
    /// we trigger a load and wait (bounded) for navigation to finish before collecting; an
    /// already-loaded tab (e.g. the current page) extracts immediately with no wait. Returns `nil`
    /// if the tab can't be found, the wake fails, or the page doesn't load within the budget.
    /// Never selects or focuses the tab.
    @MainActor
    static func extractPageContext(forTabId tabId: String,
                                   origin: TabCollectionViewModel,
                                   in windowControllersManager: WindowControllersManagerProtocol,
                                   navigationTimeout: TimeInterval = 5,
                                   collectTimeout: TimeInterval = 5) async -> AIChatPageContextData? {
        guard let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: tabId, forOrigin: origin, in: windowControllersManager) else {
            return nil
        }

        if resolved.wasMaterialized {
            // Mirror `resumeTab(at:)`: a just-materialized tab won't auto-load, so kick a reload and
            // wait for navigation to finish before collecting — otherwise an early empty JS response
            // could win the `collectAndWait` race.
            let didNavigate = await waitForNavigationFinish(tab: resolved.tab, timeout: navigationTimeout) {
                resolved.tab.reload()
            }
            guard didNavigate else { return nil }
        }

        return await extractPageContext(from: resolved.tab, timeout: collectTimeout)
    }

    /// Subscribes to the tab's first finished navigation, runs `start()` (e.g. `reload()`), and
    /// awaits the navigation bounded by `timeout`. Subscribing before `start()` avoids missing a
    /// fast-finishing navigation. Returns `true` if navigation finished, `false` on timeout.
    ///
    /// The navigation signal is bridged through an `AsyncStream` (not `withCheckedContinuation`) so
    /// that cancelling the task group on timeout actually tears the waiter down — a bare
    /// continuation isn't cancellation-aware, so the timeout loser would otherwise hang the group
    /// forever and leak the continuation. Mirrors `PageContextUserScript.collectAndWait`.
    @MainActor
    private static func waitForNavigationFinish(tab: Tab,
                                                timeout: TimeInterval,
                                                start: @escaping @MainActor () -> Void) async -> Bool {
        let navigationFinished = AsyncStream<Void> { continuation in
            var cancellable: AnyCancellable?
            cancellable = tab.webViewDidFinishNavigationPublisher
                .first()
                .sink { _ in
                    continuation.yield(())
                    continuation.finish()
                }
            continuation.onTermination = { _ in cancellable?.cancel() }
            start()
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in navigationFinished { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(interval: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
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

        if !payload.enabled {
            pageContextRemovedSubject.send()
        }

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
            fireSyncDailyAndStandardPixel(AIChatPixel.aiChatSyncScopedSyncTokenError(reason: reason))
            return AIChatErrorResponse(reason: reason)
        }

        do {
            guard let syncHandler = makeSyncHandler() else {
                return makeErrorResponse("internal error")
            }
            let payload = try await syncHandler.getScopedToken()
            fireSyncAiChatActiveDailyIfNeeded()
            return AIChatPayloadResponse(payload: payload)
        } catch {
            let reason: String
            switch error {
            case SyncError.accountNotFound:
                reason = "sync off"
            case SyncError.unauthenticatedWhileLoggedIn:
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
            Task { @MainActor [weak self] in
                self?.fireSyncDailyAndStandardPixel(AIChatPixel.aiChatSyncEncryptionError(reason: "invalid parameters"))
            }
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        do {
            let payload = try syncHandler.encrypt(data)
            Task { @MainActor [weak self] in
                self?.fireSyncAiChatActiveDailyIfNeeded()
            }
            return AIChatPayloadResponse(payload: payload)
        } catch {
            let reason: String
            switch error {
            case SyncError.failedToEncryptValue:
                reason = "encryption failed"
            default:
                reason = "internal error"
            }
            Task { @MainActor [weak self] in
                self?.fireSyncDailyAndStandardPixel(AIChatPixel.aiChatSyncEncryptionError(reason: reason))
            }
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
            Task { @MainActor [weak self] in
                self?.fireSyncDailyAndStandardPixel(AIChatPixel.aiChatSyncDecryptionError(reason: "invalid parameters"))
            }
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        do {
            let payload = try syncHandler.decrypt(data)
            Task { @MainActor [weak self] in
                self?.fireSyncAiChatActiveDailyIfNeeded()
            }
            return AIChatPayloadResponse(payload: payload)
        } catch {
            let reason = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.fireSyncDailyAndStandardPixel(AIChatPixel.aiChatSyncDecryptionError(reason: reason))
            }
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
            Task { @MainActor [weak self] in
                self?.fireSyncDailyAndStandardPixel(AIChatPixel.aiChatSyncHistoryEnabledError(reason: "invalid parameters"))
            }
            return AIChatErrorResponse(reason: "invalid parameters")
        }

        syncServiceProvider()?.setAIChatHistoryEnabled(enabled)
        return nil
    }

    // MARK: - Voice Session

    @MainActor
    func voiceSessionStarted(params: Any, message: UserScriptMessage) async -> Encodable? {
        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: message.messageWebView)
        return nil
    }

    @MainActor
    func voiceSessionEnded(params: Any, message: UserScriptMessage) async -> Encodable? {
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: message.messageWebView)
        return nil
    }

    @MainActor
    func voiceChatStartFailed(params: Any, message: UserScriptMessage) async -> Encodable? {
        // No-op when the feature flag is off — FE should never reach here in that case
        // (it sees `supportsNativeVoicePermissionHandler: false` and keeps its tooltip),
        // but stale clients or local-override misuse could fire it. Fail closed.
        guard featureFlagger.isFeatureOn(.aiChatNativeVoicePermissionFlow) else { return nil }
        voiceChatFailureHandler.handleVoiceChatStartFailed(reason: Self.failureReason(from: params), sourceWebView: message.messageWebView)
        return nil
    }

    @MainActor
    func dictationStartFailed(params: Any, message: UserScriptMessage) async -> Encodable? {
        // Unlike voice chat, the dictation flow ships without a feature flag, so it's always
        // handled. The carried `reason` drives the same OS-mic-denied check as voice chat;
        // only the remediation copy differs.
        voiceChatFailureHandler.handleDictationStartFailed(reason: Self.failureReason(from: params), sourceWebView: message.messageWebView)
        return nil
    }

    private static func failureReason(from params: Any) -> String {
        guard let dict = params as? [String: Any], let value = dict["reason"] as? String else {
            return ""
        }
        return value
    }

    private func makeSyncHandler() -> AIChatSyncHandler? {
        guard let sync = syncServiceProvider() else {
            return nil
        }
        setUpSyncStatusObserverIfNeeded(syncService: sync)
        guard sync.authState != .initializing else {
            return nil
        }
        return AIChatSyncHandler(sync: sync, httpRequestErrorHandler: syncErrorHandler.handleAiChatsError)
    }

    @MainActor
    private func fireSyncAiChatActiveDailyIfNeeded() {
        pixelFiring?.fire(GeneralPixel.syncAiChatActiveDaily, frequency: .legacyDailyNoSuffix)
    }

    @MainActor
    private func fireSyncDailyAndStandardPixel(_ pixel: PixelKitEvent) {
        pixelFiring?.fire(pixel, frequency: .dailyAndStandard)
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
            pageContextConsumedSubject.send()
            // Selections were consumed by the prompt; clear the pull-store so a later init doesn't resurrect them.
            messageHandling.clearSelectionContexts()
            pixelFiring?.fire(AIChatPixel.aiChatMetricStartNewConversation, frequency: .standard)
            DispatchQueue.main.async { [self] in
                refreshAtbs(completion: completion)
            }
        case .userDidSubmitPrompt:
            notificationCenter.post(name: .aiChatUserDidSubmitPrompt, object: nil)
            markDuckAIActivatedIfNeeded(metric)
            pageContextConsumedSubject.send()
            messageHandling.clearSelectionContexts()
            pixelFiring?.fire(AIChatPixel.aiChatMetricSentPromptOngoingChat, frequency: .standard)
            DispatchQueue.main.async { [self] in
                refreshAtbs(completion: completion)
            }
        case .userDidAcceptTermsAndConditions:
            handleTermsAccepted()
            completion?()
        case .userDidSelectSuggestion:
            pixelFiring?.fire(
                AIChatPixel.aiChatSuggestionSelected(
                    suggestionId: metric.suggestionId ?? "",
                    pageType: metric.pageType ?? "none"
                ),
                frequency: .dailyAndStandard
            )
            completion?()
        default:
            completion?()
            return
        }
    }

    private func handleTermsAccepted() {
        let alreadyAccepted = storage.hasAcceptedTermsAndConditions

        if alreadyAccepted {
            let syncIsOn = makeSyncHandler()?.isSyncTurnedOn() ?? false
            let pixel: AIChatPixel = syncIsOn
                ? .aiChatTermsAcceptedDuplicateSyncOn
                : .aiChatTermsAcceptedDuplicateSyncOff
            Task { @MainActor [weak self] in
                self?.pixelFiring?.fire(pixel, frequency: .dailyAndStandard)
            }
        }

        storage.hasAcceptedTermsAndConditions = true
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
