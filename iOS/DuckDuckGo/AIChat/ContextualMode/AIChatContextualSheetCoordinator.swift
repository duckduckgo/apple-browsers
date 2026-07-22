//
//  AIChatContextualSheetCoordinator.swift
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

import AIChat
import BrowserServicesKit
import Combine
import Common
import ConcurrencyExtensions
import FoundationExtensions
import Core
import os.log
import PrivacyConfig
import UIKit
import WebKit

/// Underlying-tab URL publishers the contextual chat needs.
struct AIChatTabURLPublishers {
    let originating: AnyPublisher<URL?, Never>
    let didFinish: AnyPublisher<URL?, Never>
}

private struct ContextualUnifiedToggleInputFeature: UnifiedToggleInputFeatureProviding {
    let isAvailable: Bool
    let isToggleHiddenOnDuckAITab: Bool
}

/// Delegate protocol for coordinating actions that require interaction with the browser.
protocol AIChatContextualSheetCoordinatorDelegate: AnyObject {
    /// Called when the user requests to load a URL externally.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL)

    /// Called when the user taps expand to open duck.ai in a new tab with the given chat URL.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestExpandWithURL url: URL)

    /// Called when the user taps "View all chats" to open the native chat history page.
    func aiChatContextualSheetCoordinatorDidRequestViewAllChats(_ coordinator: AIChatContextualSheetCoordinator)

    /// Called when the user requests to open AI Chat settings.
    func aiChatContextualSheetCoordinatorDidRequestOpenSettings(_ coordinator: AIChatContextualSheetCoordinator)

    /// Called when the user requests to open sync settings.
    func aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(_ coordinator: AIChatContextualSheetCoordinator)

    /// Called when the contextual chat URL changes, used to persist for cold restore.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?)

    /// Called when the user requests to open a downloaded file.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestOpenDownloadWithFileName fileName: String)

    /// Called when the user confirmed deletion of the contextual chat, providing the chat ID to delete server-side.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestDeleteChatWithID chatID: String)

    /// Called when the user requests a new Duck.ai voice chat.
    func aiChatContextualSheetCoordinatorDidRequestNewVoiceChat(_ coordinator: AIChatContextualSheetCoordinator)
}

/// Coordinates the presentation and lifecycle of the contextual AI chat sheet.
@MainActor
final class AIChatContextualSheetCoordinator {

    // MARK: - Properties

    weak var delegate: AIChatContextualSheetCoordinatorDelegate?

    private let voiceSearchHelper: VoiceSearchHelperProtocol
    let aiChatSettings: AIChatSettingsProvider
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private let featureDiscovery: FeatureDiscovery
    private let featureFlagger: FeatureFlagger
    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding
    private let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
    private let duckAiFireModeStorageHandler: DuckAiNativeStorageHandling?
    private let debugSettings: AIChatDebugSettingsHandling
    private let isFireTab: Bool
    static let contextualContextCollectionTimeout: TimeInterval = 5

    /// Handler for page context - single source of truth.
    let pageContextHandler: AIChatPageContextHandling
    private let tabURLPublishers: AIChatTabURLPublishers
    private var contextUpdateCancellable: AnyCancellable?
    private var sessionEffectCancellable: AnyCancellable?
    private var currentPageURLCancellable: AnyCancellable?
    private var didFinishURLCancellable: AnyCancellable?
    private var currentPageURL: URL?
    private var persistentUTIHost: AIChatContextualUTIHost?
    private var latestDidFinishURL: URL?

    /// Handles all pixel firing for contextual mode.
    let pixelHandler: AIChatContextualModePixelFiring

    /// Session state - single source of truth for frontend and chip state
    let sessionState: AIChatContextualChatSessionState

    /// The retained sheet view controller for this tab's active chat session.
    private(set) var sheetViewController: AIChatContextualSheetViewController?

    /// Session timer for auto-resetting the chat after inactivity
    private var sessionTimer: AIChatSessionTimer?

    /// Whether the sheet is currently presented on screen. Tracked as `@Published`
    /// so chrome surfaces (e.g. the iPad tabs-bar Duck.ai chip) can swap their
    /// state-aware glyph and respond to swipe-to-dismiss.
    @Published private(set) var isSheetPresented: Bool = false

    /// Whether the sheet is presented and actively observing page context updates.
    private var isActivelyObservingContext: Bool {
        contextUpdateCancellable != nil
    }

    private var isWebUTIEnabled: Bool {
        unifiedToggleInputFeature.isAvailable
    }

    private var isImmediateContextualUTIEnabled: Bool {
        isWebUTIEnabled && featureFlagger.isFeatureOn(.aiChatContextualUnifiedToggleInput)
    }

    /// Publishes the URL of the page that originated the contextual chat session, with replay of the last value.
    var originatingURLPublisher: AnyPublisher<URL?, Never> {
        tabURLPublishers.originating
    }

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol,
         aiChatSettings: AIChatSettingsProvider,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         featureDiscovery: FeatureDiscovery,
         featureFlagger: FeatureFlagger,
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature(),
         pageContextHandler: AIChatPageContextHandling,
         tabURLPublishers: AIChatTabURLPublishers,
         isFireTab: Bool = false,
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
         duckAiFireModeStorageHandler: DuckAiNativeStorageHandling? = nil,
         debugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings(),
         pixelHandler: AIChatContextualModePixelFiring = AIChatContextualModePixelHandler()) {
        self.voiceSearchHelper = voiceSearchHelper
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
        self.pageContextHandler = pageContextHandler
        self.tabURLPublishers = tabURLPublishers
        self.isFireTab = isFireTab
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.duckAiFireModeStorageHandler = duckAiFireModeStorageHandler
        self.debugSettings = debugSettings
        self.pixelHandler = pixelHandler
        self.sessionState = AIChatContextualChatSessionState(
            aiChatSettings: aiChatSettings,
            pixelHandler: pixelHandler,
            featureFlagger: featureFlagger,
            isCurrentPageAttachable: { [weak pageContextHandler] in pageContextHandler?.isCurrentPageAttachable() ?? true }
        )
        self.sessionState.updateUnifiedToggleInputActive(isWebUTIEnabled, isImmediateContextual: isImmediateContextualUTIEnabled)
        self.sessionEffectCancellable = self.sessionState.effects
            .sink { [weak self] effect in
                guard case .deliverPageContext(let context, let targets) = effect else { return }
                self?.deliverPageContext(context, targets: targets)
            }
        self.currentPageURLCancellable = tabURLPublishers.originating
            .sink { [weak self] url in
                guard let self else { return }
                self.currentPageURL = url
                // Attachability is URL-driven. `originating` is KVO-backed on webView.url, so it fires on
                // back/forward navigation (unlike `didFinish`), keeping the affordances in sync.
                guard self.hasActiveSheet else { return }
                self.sessionState.refreshForCurrentPage()
                self.persistentUTIHost?.refreshPageContextAttachability()
            }
        self.didFinishURLCancellable = tabURLPublishers.didFinish
            .dropFirst()
            .sink { [weak self] url in
                Task { [weak self] in
                    self?.latestDidFinishURL = url
                    await self?.notifyPageChanged()
                }
            }
    }

    // MARK: - Public Methods

    /// Presents the contextual AI chat sheet.
    func presentSheet(from presentingViewController: UIViewController,
                      restoreURL: URL? = nil) async {
        sessionState.refreshAutoAttachSetting()
        sessionState.updateUnifiedToggleInputActive(isWebUTIEnabled, isImmediateContextual: isImmediateContextualUTIEnabled)
        clearStaleManualContextIfNeeded()

        startObservingContextUpdates()

        if sessionState.shouldTriggerAutoCollect(for: currentPageURL) {
            if sessionState.showsSuggestionsStartSurface {
                sessionState.beginLoadingSuggestions()
            }
            pageContextHandler.triggerContextCollection(trigger: .auto)
        } else if shouldCollectSignalsOnly {
            sessionState.markPendingSignalsOnlyCollection()
            pageContextHandler.triggerContextCollection(trigger: .tabContent)
        } else {
            // No collection attempted — still measure the current page's attachability.
            pageContextHandler.reportAttachabilityMeasurement(trigger: .navigation)
        }

        stopSessionTimer()

        if let sheetViewController {
            presentExistingSheet(sheetViewController, from: presentingViewController)
        } else {
            presentNewSheet(from: presentingViewController, restoreURL: restoreURL)
        }
    }

    /// Dismisses the sheet if currently presented. The sheet is retained for potential re-presentation.
    /// State cleanup (flag + cancellables + session timer) runs from the VC's `viewDidDisappear` hook.
    func dismissSheet() {
        sheetViewController?.dismiss(animated: true)
    }

    /// Forces the starting model for the bound chat
    func preselectModel(_ modelID: String) {
        guard let persistentUTIHost else { return }
        persistentUTIHost.preselectModel(modelID)
    }

    private func handleSheetDismissed() {
        guard isSheetPresented else { return }
        isSheetPresented = false
        stopObservingContextUpdates()
        sessionState.handleSheetDismissed()
        startSessionTimer()
    }

    // Mirrors handleSheetDismissed but deliberately skips startSessionTimer — a fire-button
    // clear nukes the chat and doesn't want a pending timer firing afterwards. Keep aligned
    // when adding side effects to handleSheetDismissed.
    func clearActiveChat() {
        sheetViewController?.notifySheetDismissed()
        isSheetPresented = false
        sheetViewController = nil
        persistentUTIHost = nil
        stopObservingContextUpdates()
        pageContextHandler.clear()
        sessionState.resetToNoChat()
        pixelHandler.reset()
    }

    func reloadIfNeeded() {
        sessionState.requestWebViewReload()
    }

    /// Called by TabViewController when the page navigates to a new URL.
    func notifyPageChanged() async {
        guard hasActiveSheet else { return }
        sessionState.notifyPageChanged()

        if sessionState.shouldTriggerAutoCollect() {
            if sessionState.showsSuggestionsStartSurface {
                sessionState.beginLoadingSuggestions()
            }
            let didTrigger = pageContextHandler.triggerContextCollection(trigger: .navigation)
            if !didTrigger {
                sessionState.clearProcessingNavigationFlag()
            }
        } else if sessionState.supportsMultipleContexts && sessionState.hasActiveChat && (isActivelyObservingContext || isImmediateContextualUTIEnabled) {
            sessionState.notifyFrontendOfMultiContextNavigation()
            sessionState.clearProcessingNavigationFlag()
            pageContextHandler.reportAttachabilityMeasurement(trigger: .navigation)
        } else if shouldCollectSignalsOnly {
            sessionState.markPendingSignalsOnlyCollection()
            if !pageContextHandler.triggerContextCollection(trigger: .tabContent) {
                sessionState.clearProcessingNavigationFlag()
            }
        } else {
            sessionState.clearProcessingNavigationFlag()
            pageContextHandler.reportAttachabilityMeasurement(trigger: .navigation)
        }
    }

    /// Returns true if the contextual sheet has been shown.
    var hasActiveSheet: Bool {
        sheetViewController != nil
    }

    private var shouldCollectSignalsOnly: Bool {
        featureFlagger.isFeatureOn(.contextualSuggestedPrompts)
            && !sessionState.hasActiveChat
            && !sessionState.shouldAutoCollectContext
    }
}

// MARK: - Private Methods

private extension AIChatContextualSheetCoordinator {
    
    func presentExistingSheet(_ sheetVC: AIChatContextualSheetViewController, from presentingVC: UIViewController) {
        guard sheetVC.presentingViewController == nil else { return }
        // UIKit silently drops present() if the presenter already has a presentedViewController;
        // bail so isSheetPresented doesn't get stuck true.
        guard presentingVC.presentedViewController == nil else { return }
        sheetVC.configureSheetPresentation()
        presentingVC.present(sheetVC, animated: true)
        isSheetPresented = true
    }

    func presentNewSheet(from presentingVC: UIViewController, restoreURL: URL?) {
        guard presentingVC.presentedViewController == nil else { return }

        if let restoreURL {
            sessionState.restoreChat(with: restoreURL)
        }

        let suggestionsReader = makeSuggestionsReaderIfEnabled()
        let persistentUTIHost = isImmediateContextualUTIEnabled
            ? makePersistentUTIHostIfNeeded(startsPreSubmit: !sessionState.hasActiveChat)
            : nil

        let sheetVC = AIChatContextualSheetViewController(
            sessionState: sessionState,
            aiChatSettings: aiChatSettings,
            voiceSearchHelper: voiceSearchHelper,
            webViewControllerFactory: { [weak self] in
                guard let self else { return nil }
                return self.makeWebViewController()
            },
            pixelHandler: pixelHandler,
            featureFlagger: featureFlagger,
            persistentUTIHost: persistentUTIHost,
            suggestionsReader: suggestionsReader
        )
        sheetVC.delegate = self
        sheetViewController = sheetVC

        presentingVC.present(sheetVC, animated: true)
        isSheetPresented = true
    }

    func makeSuggestionsReaderIfEnabled() -> AIChatSuggestionsReading? {
        let reader = SuggestionsReader(
            featureFlagger: featureFlagger,
            privacyConfig: privacyConfigurationManager,
            nativeStorageHandler: duckAiNativeStorageHandler,
            featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger)
        )
        let settings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
        return AIChatSuggestionsReader(suggestionsReader: reader, historySettings: settings)
    }

    func makePersistentUTIHostIfNeeded(startsPreSubmit: Bool) -> AIChatContextualUTIHost? {
        guard isWebUTIEnabled else { return nil }
        if let persistentUTIHost { return persistentUTIHost }

        let initialUTIAttachment = self.initialUTIAttachment
        let host = AIChatContextualUTIHost(
            originatingURLPublisher: originatingURLPublisher,
            initialAttachedContext: initialUTIAttachment.context,
            initialAttachmentDeliveryState: initialUTIAttachment.deliveryState,
            hasActiveChat: { [weak self] in self?.sessionState.hasActiveChat ?? false },
            isAutoAttachEnabled: { [weak self] in self?.sessionState.shouldAutoCollectContext ?? false },
            isCurrentPageAttachable: { [weak self] in self?.pageContextHandler.isCurrentPageAttachable() ?? true },
            isFireTab: isFireTab,
            lastUsedModelProvider: duckAiLastUsedModelProvider,
            startsPreSubmit: startsPreSubmit
        )
        host.onAttachRequested = { [weak self] in
            guard let self else { return }
            self.sessionState.beginManualAttach()
            let didTrigger = self.pageContextHandler.triggerContextCollection(trigger: .userRequest)
            if !didTrigger {
                self.sessionState.cancelManualAttach()
            }
        }
        host.onRemoveRequested = { [weak self] in
            guard let self else { return }
            self.sessionState.downgradeToPlaceholder()
            self.pageContextHandler.clear()
        }
        host.onPromptSubmitted = { [weak self] in
            guard let self else { return }
            self.sessionState.beginChatForUTISubmission()
            self.sheetViewController?.handleFirstUTISubmission()
        }
        host.onPromptDelivered = { [weak self] in
            self?.sessionState.markUTIContextDelivered()
        }
        host.onAIVoiceChatRequested = { [weak self] in
            guard let self else { return }
            self.sheetViewController?.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.delegate?.aiChatContextualSheetCoordinatorDidRequestNewVoiceChat(self)
            }
        }
        self.persistentUTIHost = host
        return host
    }

    func startObservingContextUpdates() {
        guard contextUpdateCancellable == nil else { return }

        contextUpdateCancellable = pageContextHandler.contextPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] contextData in
                self?.handleContextDataUpdate(contextData)
            }

    }

    func stopObservingContextUpdates() {
        contextUpdateCancellable?.cancel()
        contextUpdateCancellable = nil
    }

    func handleContextDataUpdate(_ context: AIChatPageContext?) {
        sessionState.updateContext(context)
    }

    func collectFreshContextAndWait(timeout: TimeInterval) async -> AIChatPageContextData? {
        let expectedURL = latestDidFinishURL
        let firstResult = AsyncStream<AIChatPageContextData?> { continuation in
            let cancellable = pageContextHandler.contextPublisher
                .dropFirst()
                .first(where: { context in
                    guard let expectedURL,
                          let context,
                          let emittedURL = URL(string: context.contextData.url) else { return true }
                    return emittedURL.equals(expectedURL, by: .sameDocument)
                })
                .sink { context in
                    continuation.yield(context?.contextData)
                    continuation.finish()
                }
            continuation.onTermination = { _ in cancellable.cancel() }

            if !pageContextHandler.triggerContextCollection(trigger: .userRequest) {
                sessionState.cancelManualAttach()
                continuation.yield(nil)
                continuation.finish()
            }
        }

        // Await with `timeout` so this FE bridge call never hangs if the JS collection never responds
        // (web view torn down, navigation mid-request, JS error). On timeout the push still delivers.
        do {
            return try await withTimeout(timeout) {
                for await result in firstResult {
                    return result
                }
                return nil
            }
        } catch {
            // Timed out (or cancelled) before JS published
            sessionState.cancelManualAttach()
            return nil
        }
    }

    func clearStaleManualContextIfNeeded() {
        guard sessionState.clearManualContextIfStale(for: currentPageURL) else { return }
        pageContextHandler.clearAttachedContext()
        persistentUTIHost?.clearAttachedContext()
    }

    func deliverPageContext(_ context: AIChatPageContextData?, targets: PageContextDeliveryTargets) {
        if let host = persistentUTIHost, targets.contains(.utiChip) {
            deliverToUTIChip(context, host: host)
        }

        if let host = persistentUTIHost, targets.contains(.utiAttachAffordance) {
            host.showAttachAffordance()
        }

        if targets.contains(.frontendBridge) {
            sheetViewController?.pushPageContext(context)
        }
    }

    func deliverToUTIChip(_ context: AIChatPageContextData?, host: AIChatContextualUTIHost) {
        guard let context else {
            host.clearAttachedContext()
            return
        }

        let pageContext = sessionState.latestContext?.contextData == context
            ? sessionState.latestContext
            : AIChatPageContext(contextData: context, favicon: nil)
        if let pageContext {
            host.setAttachedContext(pageContext, deliveryState: sessionState.utiChipDeliveryState(forDelivering: context))
        }
    }

    /// Factory method for creating web view controllers, avoids prop drilling through the Sheet VC.
    func makeWebViewController() -> AIChatContextualWebViewController {
        let downloadsDirectoryHandler = DownloadsDirectoryHandler()
        downloadsDirectoryHandler.createDownloadsDirectoryIfNeeded()
        let downloadHandler = makeDownloadHandler(downloadsPath: downloadsDirectoryHandler.downloadsDirectory)

        let contextualUTIFeature = ContextualUnifiedToggleInputFeature(
            isAvailable: isWebUTIEnabled,
            isToggleHiddenOnDuckAITab: unifiedToggleInputFeature.isToggleHiddenOnDuckAITab
        )

        let webVC = AIChatContextualWebViewController(
            aiChatSettings: aiChatSettings,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger,
            unifiedToggleInputFeature: contextualUTIFeature,
            isFireTab: isFireTab,
            duckAiFireModeStorageHandler: duckAiFireModeStorageHandler,
            downloadHandler: downloadHandler,
            getPageContext: { [weak self] reason in
                guard let self else { return nil }
                guard reason == .userAction else { return nil }

                guard self.featureFlagger.isFeatureOn(.contextualSuggestedPrompts) else {
                    self.sessionState.beginManualAttach(fromFrontend: true)
                    if !self.pageContextHandler.triggerContextCollection(trigger: .userRequest) {
                        self.sessionState.cancelManualAttach()
                    }
                    return nil
                }

                if let cached = self.sessionState.latestContext?.contextData,
                   cached.attached != false, !cached.content.isEmpty {
                    return cached
                }
                self.sessionState.beginManualAttach(fromFrontend: true)
                return await self.collectFreshContextAndWait(timeout: Self.contextualContextCollectionTimeout)
            },
            pixelHandler: pixelHandler,
            utiHostInstaller: { [weak self] contextualChatViewController in
                guard let self else { return nil }
                guard self.isWebUTIEnabled else { return nil }
                let host = self.makePersistentUTIHostIfNeeded(startsPreSubmit: self.isImmediateContextualUTIEnabled && !self.sessionState.hasActiveChat)
                host?.setContextualChatViewController(contextualChatViewController)
                if !self.isImmediateContextualUTIEnabled {
                    host?.installInWebView(contextualChatViewController)
                }
                return host
            }
        )

        return webVC
    }

    var initialUTIAttachment: (context: AIChatPageContext?, deliveryState: PageContextAttachmentDeliveryState) {
        if let context = sessionState.intendedAttachedContext {
            if isImmediateContextualUTIEnabled, !sessionState.hasActiveChat {
                return (context, .pendingSubmit)
            }
            return (context, .delivered)
        }
        if sessionState.hasActiveChat, let context = sessionState.latestContext {
            return (context, .pendingSubmit)
        }
        return (nil, .delivered)
    }

    var duckAiLastUsedModelProvider: DuckAiLastUsedModelProviding? {
        let storageHandler = isFireTab ? duckAiFireModeStorageHandler : duckAiNativeStorageHandler
        return storageHandler.map {
            DuckAiLastUsedModelProvider(storage: $0, pixelFiring: DuckAiNativeStoragePixelAdapter())
        }
    }
    
    /// Starts the session timer after the sheet is dismissed.
    /// Timer will automatically reset the chat to native input after configured inactivity period.
    /// Uses privacy config value, but can be overridden via debug settings.
    func startSessionTimer() {
        guard sessionTimer == nil else { return }
        let sessionDuration: TimeInterval
        if let debugSeconds = debugSettings.contextualSessionTimerSeconds {
            sessionDuration = TimeInterval(debugSeconds)
            Logger.aiChat.debug("[Contextual SessionTimer] Started: \(debugSeconds) seconds (debug setting)")
        } else {
            let minutes = aiChatSettings.sessionTimerInMinutes
            sessionDuration = TimeInterval(minutes * 60)
            Logger.aiChat.debug("[Contextual SessionTimer] Started: \(minutes) minutes (privacy config)")
        }

        sessionTimer = AIChatSessionTimer(durationInSeconds: sessionDuration) { [weak self] in
            Task { @MainActor in
                self?.resetToNativeInputState()
            }
        }
        sessionTimer?.start()
    }

    /// Stops the session timer when the sheet is re-opened.
    func stopSessionTimer() {
        sessionTimer?.cancel()
        sessionTimer = nil
        Logger.aiChat.debug("[Contextual SessionTimer] Stopped")
    }

    /// Resets the chat session to native input state.
    /// Called when the session timer expires or when the user taps "New Chat".
    func resetToNativeInputState() {
        Logger.aiChat.debug("[Contextual] Resetting to native input")

        sessionState.resetToNoChat()
        persistentUTIHost?.prepareForNewChat()

        if shouldCollectSignalsOnly {
            Logger.aiChat.debug("[PageContext] New chat - collecting signals-only")
            sessionState.markPendingSignalsOnlyCollection()
            pageContextHandler.triggerContextCollection(trigger: .tabContent)
        } else {
            Logger.aiChat.debug("[PageContext] New chat - collecting fresh context")
            sessionState.beginLoadingSuggestions()
            pageContextHandler.triggerContextCollection(trigger: .userRequest)
        }

        delegate?.aiChatContextualSheetCoordinator(self, didUpdateContextualChatURL: nil)
    }
}

// MARK: - AIChatContextualSheetViewControllerDelegate
extension AIChatContextualSheetCoordinator: AIChatContextualSheetViewControllerDelegate {

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestToLoad url: URL) {
        viewController.dismiss(animated: true)
        delegate?.aiChatContextualSheetCoordinator(self, didRequestToLoad: url)
    }

    func aiChatContextualSheetViewControllerDidRequestDismiss(_ viewController: AIChatContextualSheetViewController) {
        viewController.dismiss(animated: true)
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestExpandWithURL url: URL) {
        delegate?.aiChatContextualSheetCoordinator(self, didRequestExpandWithURL: url)
        viewController.dismiss(animated: true)
        sessionState.cancelManualAttach()
    }

    func aiChatContextualSheetViewControllerDidRequestViewAllChats(_ viewController: AIChatContextualSheetViewController) {
        sessionState.cancelManualAttach()
        // Dismiss the sheet first, then open the native history page so it isn't presented over a dismissing sheet.
        viewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.aiChatContextualSheetCoordinatorDidRequestViewAllChats(self)
        }
    }

    func aiChatContextualSheetViewControllerDidRequestOpenSettings(_ viewController: AIChatContextualSheetViewController) {
        viewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.aiChatContextualSheetCoordinatorDidRequestOpenSettings(self)
        }
    }

    func aiChatContextualSheetViewControllerDidRequestOpenSyncSettings(_ viewController: AIChatContextualSheetViewController) {
        viewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(self)
        }
    }

    func aiChatContextualSheetViewControllerDidRequestAttachPage(_ viewController: AIChatContextualSheetViewController) {
        sessionState.beginManualAttach()
        let didTrigger = pageContextHandler.triggerContextCollection(trigger: .userRequest)
        if !didTrigger {
            sessionState.cancelManualAttach()
        }
    }

    func aiChatContextualSheetViewControllerDidRequestRemoveChip(_ viewController: AIChatContextualSheetViewController) {
        sessionState.downgradeToPlaceholder()
        pageContextHandler.clear()
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didUpdateContextualChatURL url: URL?) {
        sessionState.updateContextualChatURL(url)
        delegate?.aiChatContextualSheetCoordinator(self, didUpdateContextualChatURL: url)
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestOpenDownloadWithFileName fileName: String) {
        viewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.aiChatContextualSheetCoordinator(self, didRequestOpenDownloadWithFileName: fileName)
        }
    }

    func aiChatContextualSheetViewControllerDidDismiss(_ viewController: AIChatContextualSheetViewController) {
        handleSheetDismissed()
    }

    func aiChatContextualSheetViewControllerDidRequestNewChat(_ viewController: AIChatContextualSheetViewController) {
        resetToNativeInputState()
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didSubmitPrompt prompt: String) {
        let hasPageContext: Bool
        if case .attached = sessionState.chipState { hasPageContext = true } else { hasPageContext = false }
        sheetViewController?.notifyInitialNativePromptSubmitted(hasPageContext: hasPageContext)
        sessionState.handlePromptSubmission(prompt)
    }

    func aiChatContextualSheetViewControllerDidConfirmDeleteChat(_ viewController: AIChatContextualSheetViewController) {
        let chatURL = sessionState.contextualChatURL
        clearActiveChat()
        viewController.dismiss(animated: true)

        if let chatID = chatURL?.duckAIChatID {
            delegate?.aiChatContextualSheetCoordinator(self, didRequestDeleteChatWithID: chatID)
        }
    }
}
