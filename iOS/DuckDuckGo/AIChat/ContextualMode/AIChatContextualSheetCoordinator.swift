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
import Core
import os.log
import PrivacyConfig
import UIKit
import WebKit

/// Delegate protocol for coordinating actions that require interaction with the browser.
protocol AIChatContextualSheetCoordinatorDelegate: AnyObject {
    /// Called when the user requests to load a URL externally.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL)

    /// Called when the user taps expand to open duck.ai in a new tab with the given chat URL.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestExpandWithURL url: URL)

    /// Called when the user requests to open AI Chat settings.
    func aiChatContextualSheetCoordinatorDidRequestOpenSettings(_ coordinator: AIChatContextualSheetCoordinator)

    /// Called when the user requests to open sync settings.
    func aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(_ coordinator: AIChatContextualSheetCoordinator)

    /// Called when the contextual chat URL changes, used to persist for cold restore.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?)

    /// Called when the user requests to open a downloaded file.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestOpenDownloadWithFileName fileName: String)
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
    private let debugSettings: AIChatDebugSettingsHandling

    /// Handler for page context - single source of truth.
    let pageContextHandler: AIChatPageContextHandling
    private var contextUpdateCancellable: AnyCancellable?

    /// Handles all pixel firing for contextual mode.
    let pixelHandler: AIChatContextualModePixelFiring

    /// Session state - single source of truth for frontend and chip state
    let sessionState = AIChatContextualChatSessionState()

    /// The retained sheet view controller for this tab's active chat session.
    private(set) var sheetViewController: AIChatContextualSheetViewController?

    /// The retained web view controller for persisting the chat session across sheet dismissals.
    private(set) var webViewController: AIChatContextualWebViewController?

    /// The view model for the current sheet session (retained alongside the sheet)
    private var viewModel: AIChatContextualSheetViewModel?

    /// Session timer for auto-resetting the chat after inactivity
    private var sessionTimer: AIChatSessionTimer?

    /// Flag to prevent duplicate navigation processing
    private var isProcessingNavigation = false

    /// Hash of last processed context to prevent duplicate updates
    private var lastProcessedContextHash: String?

    /// Returns true if the sheet is currently presented.
    var isSheetPresented: Bool {
        sheetViewController?.presentingViewController != nil
    }

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol,
         aiChatSettings: AIChatSettingsProvider,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         featureDiscovery: FeatureDiscovery,
         featureFlagger: FeatureFlagger,
         pageContextHandler: AIChatPageContextHandling,
         debugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings(),
         pixelHandler: AIChatContextualModePixelFiring = AIChatContextualModePixelHandler()) {
        self.voiceSearchHelper = voiceSearchHelper
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.pageContextHandler = pageContextHandler
        self.debugSettings = debugSettings
        self.pixelHandler = pixelHandler
    }

    // MARK: - Public Methods

    /// Presents the contextual AI chat sheet.
    /// If an active chat exists, it will be re-presented. Otherwise, a new sheet is created.
    /// For fresh presentations (not cold restore), collects page context automatically.
    ///
    /// - Parameters:
    ///   - presentingViewController: The view controller to present the sheet from.
    ///   - restoreURL: Optional URL to restore a previous chat session (cold restore after app restart).
    func presentSheet(from presentingViewController: UIViewController,
                      restoreURL: URL? = nil) async {
        let sheetVC: AIChatContextualSheetViewController
        let isNewSheet: Bool

        if let existingSheet = sheetViewController {
            sheetVC = existingSheet
            isNewSheet = false
            // Restore logic moved to after presentation to ensure view is loaded
        } else {
            if restoreURL == nil {
                await pageContextHandler.triggerContextCollection()
            }

            let sheetViewModel = AIChatContextualSheetViewModel(
                settings: aiChatSettings,
                hasExistingChat: webViewController != nil || restoreURL != nil
            )
            viewModel = sheetViewModel

            sheetVC = AIChatContextualSheetViewController(
                sessionState: sessionState,
                viewModel: sheetViewModel,
                voiceSearchHelper: voiceSearchHelper,
                webViewControllerFactory: { [weak self] in
                    guard let self else { return nil }
                    return self.makeWebViewController()
                },
                snapshotProvider: { [weak self] in
                    self?.currentSnapshot
                },
                existingWebViewController: webViewController,
                restoreURL: restoreURL,
                onOpenSettings: { [weak self] in
                    guard let self else { return }
                    self.sheetViewController?.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        self.delegate?.aiChatContextualSheetCoordinatorDidRequestOpenSettings(self)
                    }
                },
                pixelHandler: pixelHandler
            )
            sheetVC.delegate = self
            sheetViewController = sheetVC
            isNewSheet = true
        }

        startObservingContextUpdates()
        stopSessionTimer()

        presentingViewController.present(sheetVC, animated: true) { [weak self] in
            guard let self else { return }

            // Restore existing sheet after presentation to ensure view is loaded
            if !isNewSheet {
                Task {
                    await self.restoreExistingSheet(sheetVC, restoreURL: restoreURL)
                }
            }
        }

        pixelHandler.fireSheetOpened()
        if isNewSheet && restoreURL != nil {
            pixelHandler.fireSessionRestored()
        }
    }

    /// Collects fresh context and updates UI.
    /// Called when user taps "Attach Page" button.
    func collectAndAttachPageContext() async {
        Logger.aiChat.debug("[PageContext] Manual attach requested")

        pixelHandler.beginManualAttach()

        await pageContextHandler.triggerContextCollection()

        guard pageContextHandler.hasContext else {
            pixelHandler.endManualAttach()
            return
        }

        guard let snapshot = currentSnapshot else {
            pixelHandler.endManualAttach()
            return
        }

        sheetViewController?.applyContextSnapshot(snapshot)
        pixelHandler.endManualAttach()
    }

    /// Dismisses the sheet if currently presented. The sheet is retained for potential re-presentation.
    func dismissSheet() {
        sheetViewController?.dismiss(animated: true)
    }
    
    func clearActiveChat() {
        sheetViewController = nil
        webViewController = nil
        viewModel = nil
        stopObservingContextUpdates()
        pageContextHandler.clear()
        pixelHandler.reset()
    }

    /// Clears the current page context.
    func clearPageContext() {
        pageContextHandler.clear()
    }

    /// Reloads the contextual chat web view if one exists.
    func reloadIfNeeded() {
        webViewController?.reload()
    }

    /// Called by TabViewController when the page navigates to a new URL.
    /// Triggers context collection based on session state.
    func notifyPageChanged() async {
        guard hasActiveSheet else { return }
        guard !isProcessingNavigation else {
            Logger.aiChat.debug("[PageContext] Navigation processing skipped (already in progress)")
            return
        }

        isProcessingNavigation = true
        defer { isProcessingNavigation = false }

        sessionState.clearUserDowngradeOnNavigation()

        Logger.aiChat.debug("[PageContext] Navigation detected - triggering collection")
        await pageContextHandler.triggerContextCollection()

        if let context = pageContextHandler.latestContext {
            pixelHandler.firePageContextUpdatedOnNavigation(url: context.url)
        }
    }

    /// Returns true if there's an active chat session (web view retained).
    var hasActiveChat: Bool {
        webViewController != nil
    }

    /// Returns true if the contextual sheet has been shown (viewModel exists).
    var hasActiveSheet: Bool {
        viewModel != nil
    }

    /// Creates a snapshot of the current page context for UI display.
    var currentSnapshot: AIChatPageContextSnapshot? {
        guard let context = pageContextHandler.latestContext else { return nil }
        return AIChatPageContextSnapshot(context: context, favicon: pageContextHandler.latestFavicon)
    }

    // MARK: - Session Timer

    /// Starts the session timer after the sheet is dismissed.
    /// Timer will automatically reset the chat to native input after configured inactivity period.
    /// Uses privacy config value, but can be overridden via debug settings.
    func startSessionTimer() {
        guard hasActiveChat else { return }

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
                await self?.resetToNativeInputState()
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
    func resetToNativeInputState() async {
        Logger.aiChat.debug("[Contextual] Resetting to native input")

        sessionState.resetToNoChat()

        Logger.aiChat.debug("[PageContext] New chat - collecting fresh context")
        await pageContextHandler.triggerContextCollection()

        if let snapshot = currentSnapshot {
            Logger.aiChat.debug("[PageContext] Applying fresh snapshot immediately after collection")
            sheetViewController?.updateLatestSnapshot(snapshot)
        }

        sheetViewController?.resetToNativeInput()
        webViewController = nil
        delegate?.aiChatContextualSheetCoordinator(self, didUpdateContextualChatURL: nil)
        viewModel?.didStartNewChat()
    }

    // MARK: - Context Observation

    private func startObservingContextUpdates() {
        guard contextUpdateCancellable == nil else { return }

        contextUpdateCancellable = pageContextHandler.contextPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] context in
                self?.handleContextUpdate(context)
            }
    }

    private func stopObservingContextUpdates() {
        contextUpdateCancellable?.cancel()
        contextUpdateCancellable = nil
    }

    private func handleContextUpdate(_ context: AIChatPageContextData?) {
        guard let context = context else { return }

        // Deduplicate: ignore if identical to last processed context
        let contextHash = "\(context.url)_\(context.title)_\(context.content)"
        if contextHash == lastProcessedContextHash {
            Logger.aiChat.debug("[PageContext] Duplicate context update ignored")
            return
        }
        lastProcessedContextHash = contextHash

        guard isSheetPresented else {
            Logger.aiChat.debug("[PageContext] Context update - sheet not presented")
            return
        }

        guard let snapshot = currentSnapshot else {
            Logger.aiChat.debug("[PageContext] Context update - no snapshot available")
            return
        }

        sheetViewController?.updateLatestSnapshot(snapshot)

        let autoAttachEnabled = aiChatSettings.isAutomaticContextAttachmentEnabled
        let shouldUpdate = sessionState.shouldUpdateUI(autoAttachEnabled: autoAttachEnabled)

        guard shouldUpdate else {
            Logger.aiChat.debug("[PageContext] Context update - not updating UI (shouldUpdate=false)")
            return
        }

        if sessionState.isShowingNativeInput {
            guard sessionState.shouldAllowAutomaticUpgrade() else {
                Logger.aiChat.debug("[PageContext] Context update - skipping native input update (user downgraded)")
                return
            }
            Logger.aiChat.debug("[PageContext] Context update - updating native input chip")
            sheetViewController?.applyContextSnapshot(snapshot)
        } else if sessionState.canPushToFrontend() {
            Logger.aiChat.debug("[PageContext] Context update - pushing to frontend")
            sheetViewController?.pushPageContextToFrontend(snapshot.context)
        } else {
            Logger.aiChat.debug("[PageContext] Context update - frontend already has initial context, not pushing")
        }
    }
}

// MARK: - Private Methods

private extension AIChatContextualSheetCoordinator {

    /// Factory method for creating web view controllers, avoids prop drilling through the Sheet VC.
    func makeWebViewController() -> AIChatContextualWebViewController {
        let downloadsDirectoryHandler = DownloadsDirectoryHandler()
        downloadsDirectoryHandler.createDownloadsDirectoryIfNeeded()
        let downloadHandler = makeDownloadHandler(downloadsPath: downloadsDirectoryHandler.downloadsDirectory)

        let webVC = AIChatContextualWebViewController(
            aiChatSettings: aiChatSettings,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger,
            downloadHandler: downloadHandler,
            getPageContext: { [weak self] reason in
                guard let self else { return nil }
                guard reason == .userAction else { return nil }
                return self.pageContextHandler.latestContext
            },
            pixelHandler: pixelHandler
        )

        webVC.onContextualChatURLChange = { [weak self, weak webVC] url in
            self?.handleWebViewChatURLChange(url, webViewController: webVC)
        }

        return webVC
    }

    func restoreExistingSheet(_ existingSheet: AIChatContextualSheetViewController, restoreURL: URL?) async {
        if restoreURL == nil && aiChatSettings.isAutomaticContextAttachmentEnabled {
            await pageContextHandler.triggerContextCollection()
        }

        if aiChatSettings.isAutomaticContextAttachmentEnabled {
            if hasActiveChat, let context = pageContextHandler.latestContext {
                existingSheet.pushPageContextToFrontend(context)
            } else if let snapshot = currentSnapshot {
                existingSheet.applyContextSnapshot(snapshot)
            }
        } else {
            if !hasActiveChat, let snapshot = currentSnapshot {
                if sessionState.chipState == .attached {
                    existingSheet.applyContextSnapshot(snapshot)
                } else {
                    existingSheet.showPlaceholderContextChip(snapshot)
                }
            }
        }
    }

    /// Handles chat URL changes for persistence.
    func handleWebViewChatURLChange(_ url: URL?, webViewController: AIChatContextualWebViewController?) {
        delegate?.aiChatContextualSheetCoordinator(self, didUpdateContextualChatURL: url)
    }
}

// MARK: - AIChatContextualSheetViewControllerDelegate
extension AIChatContextualSheetCoordinator: AIChatContextualSheetViewControllerDelegate {

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestToLoad url: URL) {
        viewController.dismiss(animated: true)
        delegate?.aiChatContextualSheetCoordinator(self, didRequestToLoad: url)
    }

    func aiChatContextualSheetViewControllerDidRequestDismiss(_ viewController: AIChatContextualSheetViewController) {
        viewController.dismiss(animated: true) { [weak self] in
            self?.aiChatContextualSheetViewControllerDidDismiss(viewController)
        }
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestExpandWithURL url: URL) {
        delegate?.aiChatContextualSheetCoordinator(self, didRequestExpandWithURL: url)
        viewController.dismiss(animated: true)
        sheetViewController = nil
        webViewController = nil
        viewModel = nil
        stopSessionTimer()
        stopObservingContextUpdates()
        pixelHandler.reset()
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didCreateWebViewController webVC: AIChatContextualWebViewController) {
        webViewController = webVC
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
        Task { @MainActor in
            await collectAndAttachPageContext()
        }
    }

    func aiChatContextualSheetViewControllerDidRequestClearContext(_ viewController: AIChatContextualSheetViewController) {
        clearPageContext()
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didUpdateContextualChatURL url: URL?) {
        delegate?.aiChatContextualSheetCoordinator(self, didUpdateContextualChatURL: url)
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestOpenDownloadWithFileName fileName: String) {
        viewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.aiChatContextualSheetCoordinator(self, didRequestOpenDownloadWithFileName: fileName)
        }
    }

    func aiChatContextualSheetViewControllerDidDismiss(_ viewController: AIChatContextualSheetViewController) {
        startSessionTimer()
    }

    func aiChatContextualSheetViewControllerDidRequestNewChat(_ viewController: AIChatContextualSheetViewController) {
        Task {
            await resetToNativeInputState()
        }
    }
}
