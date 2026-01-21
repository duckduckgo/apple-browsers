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

    /// The retained sheet view controller for this tab's active chat session.
    private(set) var sheetViewController: AIChatContextualSheetViewController?

    /// The retained web view controller for persisting the chat session across sheet dismissals.
    private(set) var webViewController: AIChatContextualWebViewController?

    /// The view model for the current sheet session (retained alongside the sheet)
    private var viewModel: AIChatContextualSheetViewModel?

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol,
         aiChatSettings: AIChatSettingsProvider,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         featureDiscovery: FeatureDiscovery,
         featureFlagger: FeatureFlagger) {
        self.voiceSearchHelper = voiceSearchHelper
        self.aiChatSettings = aiChatSettings
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
    }

    // MARK: - Public Methods

    /// Presents the contextual AI chat sheet.
    /// If an active chat exists, it will be re-presented. Otherwise, a new sheet is created.
    ///
    /// - Parameters:
    ///   - presentingViewController: The view controller to present the sheet from.
    ///   - pageContext: Optional page context data collected from the current tab.
    func presentSheet(from presentingViewController: UIViewController, pageContext: AIChatPageContextData? = nil) {
        let sheetVC: AIChatContextualSheetViewController

        if let existingSheet = sheetViewController {
            sheetVC = existingSheet
        } else {
            let sheetViewModel = AIChatContextualSheetViewModel(
                settings: aiChatSettings,
                hasExistingChat: webViewController != nil
            )

            if let context = pageContext {
                sheetViewModel.pageContext = AIChatContextualSheetViewModel.PageContext(
                    title: context.title,
                    favicon: decodeFaviconImage(from: context.favicon)
                )
                sheetViewModel.fullPageContext = context
            }
            viewModel = sheetViewModel

            sheetVC = AIChatContextualSheetViewController(
                viewModel: sheetViewModel,
                voiceSearchHelper: voiceSearchHelper,
                webViewControllerFactory: { [unowned self] in
                    self.makeWebViewController()
                },
                existingWebViewController: webViewController,
                settings: aiChatSettings,
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

    /// Updates page context after manual attachment via the "Attach Page" button.
    ///
    /// - Parameter context: The page context data to set.
    func updatePageContext(_ context: AIChatPageContextData) {
        guard let viewModel = viewModel else { return }
        viewModel.pageContext = AIChatContextualSheetViewModel.PageContext(
            title: context.title,
            favicon: decodeFaviconImage(from: context.favicon)
        )
        viewModel.fullPageContext = context
        sheetViewController?.didReceivePageContext()
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
            featureFlagger: featureFlagger
        )
    }

    /// Decodes a base64-encoded favicon from the page context data.
    func decodeFaviconImage(from favicons: [AIChatPageContextData.PageContextFavicon]?) -> UIImage? {
        guard let favicon = favicons?.first,
              favicon.href.hasPrefix("data:image"),
              let dataRange = favicon.href.range(of: "base64,"),
              let imageData = Data(base64Encoded: String(favicon.href[dataRange.upperBound...])) else {
            return nil
        }
        return UIImage(data: imageData)
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

    func aiChatContextualSheetViewControllerDidRequestAttachPage(_ viewController: AIChatContextualSheetViewController) {
        delegate?.aiChatContextualSheetCoordinatorDidRequestAttachPage(self)
    }
}
