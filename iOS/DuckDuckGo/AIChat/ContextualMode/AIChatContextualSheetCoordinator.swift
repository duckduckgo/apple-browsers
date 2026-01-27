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

    /// Handler for page context - single source of truth.
    let pageContextHandler: AIChatPageContextHandling
    private var contextUpdateCancellable: AnyCancellable?

    /// Handles all pixel firing for contextual mode.
    let pixelHandler: AIChatContextualModePixelFiring

    /// The retained sheet view controller for this tab's active chat session.
    private(set) var sheetViewController: AIChatContextualSheetViewController?

    /// The retained web view controller for persisting the chat session across sheet dismissals.
    private(set) var webViewController: AIChatContextualWebViewController?

    /// The view model for the current sheet session (retained alongside the sheet)
    private var viewModel: AIChatContextualSheetViewModel?

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
         pixelHandler: AIChatContextualModePixelFiring = AIChatContextualModePixelHandler()) {
        self.voiceSearchHelper = voiceSearchHelper
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.pageContextHandler = pageContextHandler
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

            if restoreURL == nil {
                await pageContextHandler.triggerContextCollection()
            }

            // Auto-attach: push to frontend if chat is active (frontend manages context),
            // otherwise apply to native input view (context submitted with prompt).
            if aiChatSettings.isAutomaticContextAttachmentEnabled {
                if hasActiveChat, let context = pageContextHandler.latestContext {
                    existingSheet.pushPageContextToFrontend(context)
                } else if let snapshot = currentSnapshot {
                    existingSheet.markNextAttachAsAutomatic()
                    existingSheet.applyContextSnapshot(snapshot)
                }
            }
        } else {
            if restoreURL == nil {
                await pageContextHandler.triggerContextCollection()
            }

            let sheetViewModel = AIChatContextualSheetViewModel(
                settings: aiChatSettings,
                hasContext: pageContextHandler.hasContext,
                hasExistingChat: webViewController != nil || restoreURL != nil
            )
            viewModel = sheetViewModel

            sheetVC = AIChatContextualSheetViewController(
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
        presentingViewController.present(sheetVC, animated: true)

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

        viewModel?.updateContextAvailability(true)

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

    /// Clears the retained sheet and web view, ending the chat session for this tab.
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
        viewModel?.updateContextAvailability(false)
    }

    /// Reloads the contextual chat web view if one exists.
    func reloadIfNeeded() {
        webViewController?.reload()
    }

    /// Called by TabViewController when the page navigates to a new URL.
    /// Triggers context collection if there's an active sheet and auto-attach is enabled.
    func notifyPageChanged() async {
        guard hasActiveSheet,
              aiChatSettings.isAutomaticContextAttachmentEnabled else { return }

        Logger.aiChat.debug("[PageContext] Navigation detected - triggering collection")
        await pageContextHandler.triggerContextCollection()

        // Fire navigation pixel only when navigation actually happens
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

        viewModel?.updateContextAvailability(pageContextHandler.hasContext)

        let autoAttachEnabled = aiChatSettings.isAutomaticContextAttachmentEnabled
        guard isSheetPresented && autoAttachEnabled else { return }

        guard let snapshot = currentSnapshot else { return }

        if hasActiveChat {
            Logger.aiChat.debug("[PageContext] Auto-attached to active chat")
            sheetViewController?.pushPageContextToFrontend(snapshot.context)
        } else {
            Logger.aiChat.debug("[PageContext] Auto-attached to input box")
            sheetViewController?.markNextAttachAsAutomatic()
            sheetViewController?.applyContextSnapshot(snapshot)
        }
    }
}

// MARK: - Private Methods

private extension AIChatContextualSheetCoordinator {

    /// Factory method for creating web view controllers, avoids prop drilling through the Sheet VC.
    func makeWebViewController() -> AIChatContextualWebViewController {
        let webVC = AIChatContextualWebViewController(
            aiChatSettings: aiChatSettings,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger,
            getPageContext: { [weak self] reason in
                guard let self else { return nil }
                let autoAttachEnabled = self.aiChatSettings.isAutomaticContextAttachmentEnabled
                guard autoAttachEnabled || reason == .userAction else { return nil }
                return self.pageContextHandler.latestContext
            },
            pixelHandler: pixelHandler
        )

        webVC.onContextualChatURLChange = { [weak self, weak webVC] url in
            self?.handleWebViewChatURLChange(url, webViewController: webVC)
        }

        return webVC
    }

    /// Handles auto-attach decision when web view's chat URL changes.
    func handleWebViewChatURLChange(_ url: URL?, webViewController: AIChatContextualWebViewController?) {
        guard url != nil,
              aiChatSettings.isAutomaticContextAttachmentEnabled,
              let context = pageContextHandler.latestContext else { return }

        webViewController?.pushPageContext(context)
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
        sheetViewController = nil
        viewModel = nil
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
}
