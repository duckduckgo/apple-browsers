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
import PrivacyConfig
import Combine
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
}

/// Coordinates the presentation and lifecycle of the contextual AI chat sheet.
final class AIChatContextualSheetCoordinator {

    // MARK: - Properties

    weak var delegate: AIChatContextualSheetCoordinatorDelegate?

    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let settings: AIChatSettingsProvider
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private let featureDiscovery: FeatureDiscovery
    private let featureFlagger: FeatureFlagger

    /// The retained sheet view controller for this tab's active chat session.
    private(set) var sheetViewController: AIChatContextualSheetViewController?

    /// The retained web view controller for persisting the chat session across sheet dismissals.
    private(set) var webViewController: AIChatContextualWebViewController?

    /// The view model for the current sheet session (retained alongside the sheet)
    private var viewModel: AIChatContextualSheetViewModel?

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol,
         settings: AIChatSettingsProvider,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         featureDiscovery: FeatureDiscovery,
         featureFlagger: FeatureFlagger) {
        self.voiceSearchHelper = voiceSearchHelper
        self.settings = settings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
    }

    // MARK: - Public Methods

    /// Presents the contextual AI chat sheet.
    /// If an active chat exists, it will be re-presented. Otherwise, a new sheet is created.
    ///
    /// - Parameter presentingViewController: The view controller to present the sheet from.
    func presentSheet(from presentingViewController: UIViewController) {
        let sheetVC: AIChatContextualSheetViewController

        if let existingSheet = sheetViewController {
            sheetVC = existingSheet
        } else {
            let sheetViewModel = AIChatContextualSheetViewModel(
                settings: settings,
                hasExistingChat: webViewController != nil
            )
            // TODO: Set page context from tab when available
            sheetViewModel.pageContext = AIChatContextualSheetViewModel.PageContext(
                title: "Example Page Title",
                favicon: nil
            )
            viewModel = sheetViewModel

            sheetVC = AIChatContextualSheetViewController(
                viewModel: sheetViewModel,
                voiceSearchHelper: voiceSearchHelper,
                webViewControllerFactory: { [unowned self] in
                    self.makeWebViewController()
                },
                existingWebViewController: webViewController
            )
            sheetVC.delegate = self
            sheetViewController = sheetVC
        }

        presentingViewController.present(sheetVC, animated: true)
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
    }

    /// Reloads the contextual chat web view if one exists.
    func reloadIfNeeded() {
        webViewController?.reload()
    }

    // MARK: - Private Methods

    /// Factory method for creating web view controllers, avoids prop drilling through the Sheet VC.
    private func makeWebViewController() -> AIChatContextualWebViewController {
        AIChatContextualWebViewController(
            aiChatSettings: settings,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger
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
        clearActiveChat()
    }

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didCreateWebViewController webVC: AIChatContextualWebViewController) {
        webViewController = webVC
    }

    func aiChatContextualSheetViewControllerDidRequestOpenSettings(_ viewController: AIChatContextualSheetViewController) {
        viewController.dismiss(animated: true)
        delegate?.aiChatContextualSheetCoordinatorDidRequestOpenSettings(self)
    }

    func aiChatContextualSheetViewControllerDidRequestOpenSyncSettings(_ viewController: AIChatContextualSheetViewController) {
        viewController.dismiss(animated: true)
        delegate?.aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(self)
    }
}
