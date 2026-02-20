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
    let sessionState: AIChatContextualChatSessionState

    /// The retained sheet view controller for this tab's active chat session.
    private(set) var sheetViewController: AIChatContextualSheetViewController?

    /// Session timer for auto-resetting the chat after inactivity
    private var sessionTimer: AIChatSessionTimer?

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
        self.sessionState = AIChatContextualChatSessionState(
            aiChatSettings: aiChatSettings,
            pixelHandler: pixelHandler
        )
    }

    // MARK: - Public Methods

    /// Presents the contextual AI chat sheet.
    func presentSheet(from presentingViewController: UIViewController,
                      restoreURL: URL? = nil) async {
        sessionState.refreshAutoAttachSetting()

        startObservingContextUpdates()

        if sessionState.shouldAutoCollectContext {
            pageContextHandler.triggerContextCollection()
        }

        stopSessionTimer()

        if let sheetViewController {
            presentExistingSheet(sheetViewController, from: presentingViewController)
        } else {
            presentNewSheet(from: presentingViewController, restoreURL: restoreURL)
        }
    }

    /// Dismisses the sheet if currently presented. The sheet is retained for potential re-presentation.
    func dismissSheet() {
        sheetViewController?.dismiss(animated: true)
    }
    
    func clearActiveChat() {
        sheetViewController = nil
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

        guard sessionState.shouldAutoCollectContext else {
            sessionState.clearProcessingNavigationFlag()
            return
        }

        let didTrigger = pageContextHandler.triggerContextCollection()
        if !didTrigger {
            sessionState.clearProcessingNavigationFlag()
        }
    }

    /// Returns true if the contextual sheet has been shown.
    var hasActiveSheet: Bool {
        sheetViewController != nil
    }
}

// MARK: - Private Methods

private extension AIChatContextualSheetCoordinator {
    
    func presentExistingSheet(_ sheetVC: UIViewController, from presentingVC: UIViewController) {
        presentingVC.present(sheetVC, animated: true)
    }
    
    func presentNewSheet(from presentingVC: UIViewController, restoreURL: URL?) {
        if let restoreURL {
            sessionState.restoreChat(with: restoreURL)
        }

        let sheetVC = AIChatContextualSheetViewController(
            sessionState: sessionState,
            aiChatSettings: aiChatSettings,
            voiceSearchHelper: voiceSearchHelper,
            webViewControllerFactory: { [weak self] in
                guard let self else { return nil }
                return self.makeWebViewController()
            },
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
        
        presentingVC.present(sheetVC, animated: true)
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
                self.sessionState.beginManualAttach(fromFrontend: true)
                let didTrigger = self.pageContextHandler.triggerContextCollection()
                if !didTrigger {
                    self.sessionState.cancelManualAttach()
                }
                return nil
            },
            pixelHandler: pixelHandler
        )

        return webVC
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

        Logger.aiChat.debug("[PageContext] New chat - collecting fresh context")
        pageContextHandler.triggerContextCollection()

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
        viewController.dismiss(animated: true) { [weak self] in
            self?.aiChatContextualSheetViewControllerDidDismiss(viewController)
        }
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestExpandWithURL url: URL) {
        delegate?.aiChatContextualSheetCoordinator(self, didRequestExpandWithURL: url)
        viewController.dismiss(animated: true) { [weak self] in
            self?.startSessionTimer()
        }
        stopObservingContextUpdates()
        sessionState.cancelManualAttach()
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
        let didTrigger = pageContextHandler.triggerContextCollection()
        if !didTrigger {
            sessionState.cancelManualAttach()
        }
    }

    func aiChatContextualSheetViewControllerDidRequestRemoveChip(_ viewController: AIChatContextualSheetViewController) {
        sessionState.downgradeToPlaceholder()
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
        startSessionTimer()
    }

    func aiChatContextualSheetViewControllerDidRequestNewChat(_ viewController: AIChatContextualSheetViewController) {
        resetToNativeInputState()
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didSubmitPrompt prompt: String) {
        sessionState.handlePromptSubmission(prompt)
    }
}
