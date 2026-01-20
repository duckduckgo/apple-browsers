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
import PrivacyConfig
import UIKit

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

    /// Called when the user taps "Attach Page" and context needs to be collected from the tab.
    func aiChatContextualSheetCoordinatorDidRequestAttachPage(_ coordinator: AIChatContextualSheetCoordinator)

    /// Called when the contextual chat URL changes, used to persist for cold restore.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?)
}

/// Coordinates the presentation and lifecycle of the contextual AI chat sheet.
final class AIChatContextualSheetCoordinator {

    // MARK: - Properties

    weak var delegate: AIChatContextualSheetCoordinatorDelegate?

    private let voiceSearchHelper: VoiceSearchHelperProtocol
    let aiChatSettings: AIChatSettingsProvider
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private let featureDiscovery: FeatureDiscovery
    private let featureFlagger: FeatureFlagger

    /// Single source of truth for page context in this chat session.
    let pageContextStore: AIChatPageContextStoring

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
         pageContextStore: AIChatPageContextStoring = AIChatPageContextStore()) {
        self.voiceSearchHelper = voiceSearchHelper
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        self.pageContextStore = pageContextStore
    }

    // MARK: - Public Methods

    /// Presents the contextual AI chat sheet.
    /// If an active chat exists, it will be re-presented. Otherwise, a new sheet is created.
    ///
    /// - Parameters:
    ///   - presentingViewController: The view controller to present the sheet from.
    ///   - pageContext: Optional page context data collected from the current tab.
    ///   - restoreURL: Optional URL to restore a previous chat session (cold restore after app restart).
    func presentSheet(from presentingViewController: UIViewController,
                      pageContext: AIChatPageContextData? = nil,
                      restoreURL: URL? = nil) {
        let sheetVC: AIChatContextualSheetViewController

        if let existingSheet = sheetViewController {
            sheetVC = existingSheet
        } else {
            if let context = pageContext {
                pageContextStore.update(context)
            }

            let sheetViewModel = AIChatContextualSheetViewModel(
                settings: aiChatSettings,
                pageContextStore: pageContextStore,
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
                existingWebViewController: webViewController,
                restoreURL: restoreURL,
                onOpenSettings: { [weak self] in
                    guard let self else { return }
                    self.sheetViewController?.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        self.delegate?.aiChatContextualSheetCoordinatorDidRequestOpenSettings(self)
                    }
                }
            )
            sheetVC.delegate = self
            sheetViewController = sheetVC
        }

        presentingViewController.present(sheetVC, animated: true)
    }

    /// Updates page context in the store and notifies UI to refresh.
    /// If there's an active chat, pushes context to the frontend. Otherwise, updates the context chip.
    ///
    /// - Parameter context: The page context data to set.
    func updatePageContext(_ context: AIChatPageContextData) {
        pageContextStore.update(context)
        if hasActiveChat {
            sheetViewController?.pushPageContextToFrontend(context)
        } else {
            sheetViewController?.didReceivePageContext()
        }
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
        pageContextStore.clear()
    }

    /// Reloads the contextual chat web view if one exists.
    func reloadIfNeeded() {
        webViewController?.reload()
    }

    /// Returns true if there's an active chat session (web view retained).
    var hasActiveChat: Bool {
        webViewController != nil
    }

    /// Returns true if the contextual sheet has been shown (viewModel exists).
    var hasActiveSheet: Bool {
        viewModel != nil
    }
}

// MARK: - Private Methods

private extension AIChatContextualSheetCoordinator {

    /// Factory method for creating web view controllers, avoids prop drilling through the Sheet VC.
    func makeWebViewController() -> AIChatContextualWebViewController {
        AIChatContextualWebViewController(
            aiChatSettings: aiChatSettings,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger,
            pageContextStore: pageContextStore
        )
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
        delegate?.aiChatContextualSheetCoordinatorDidRequestAttachPage(self)
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didUpdateContextualChatURL url: URL?) {
        delegate?.aiChatContextualSheetCoordinator(self, didUpdateContextualChatURL: url)
    }
}
