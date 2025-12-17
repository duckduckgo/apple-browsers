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

import UIKit

/// Delegate protocol for coordinating actions that require interaction with the browser.
protocol AIChatContextualSheetCoordinatorDelegate: AnyObject {
    /// Called when the user requests to load a URL externally.
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL)

    /// Called when the user taps expand to open duck.ai in a new tab.
    func aiChatContextualSheetCoordinatorDidRequestExpand(_ coordinator: AIChatContextualSheetCoordinator)
}

/// Coordinates the presentation and lifecycle of the contextual AI chat sheet.
final class AIChatContextualSheetCoordinator {

    // MARK: - Properties

    weak var delegate: AIChatContextualSheetCoordinatorDelegate?

    private let voiceSearchHelper: VoiceSearchHelperProtocol

    /// The retained sheet view controller for this tab's active chat session.
    private(set) var sheetViewController: AIChatContextualSheetViewController?

    // MARK: - Initialization

    init(voiceSearchHelper: VoiceSearchHelperProtocol) {
        self.voiceSearchHelper = voiceSearchHelper
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
            sheetVC = AIChatContextualSheetViewController(voiceSearchHelper: voiceSearchHelper)
            sheetVC.delegate = self
            sheetViewController = sheetVC
        }

        presentingViewController.present(sheetVC, animated: true)
    }

    /// Dismisses the sheet if currently presented. The sheet is retained for potential re-presentation.
    func dismissSheet() {
        sheetViewController?.dismiss(animated: true)
    }

    /// Clears the retained sheet, ending the chat session for this tab.
    func clearActiveChat() {
        sheetViewController = nil
    }
}

// MARK: - AIChatContextualSheetViewControllerDelegate
extension AIChatContextualSheetCoordinator: AIChatContextualSheetViewControllerDelegate {

    func aiChatContextualSheetViewController(_ viewController: AIChatContextualSheetViewController, didRequestToLoad url: URL) {
        delegate?.aiChatContextualSheetCoordinator(self, didRequestToLoad: url)
    }

    func aiChatContextualSheetViewControllerDidRequestDismiss(_ viewController: AIChatContextualSheetViewController) {
        viewController.dismiss(animated: true)
    }

    func aiChatContextualSheetViewControllerDidRequestExpand(_ viewController: AIChatContextualSheetViewController) {
        delegate?.aiChatContextualSheetCoordinatorDidRequestExpand(self)
        viewController.dismiss(animated: true)
        clearActiveChat()
    }
    
    func aiChatContextualSheetViewControllerDidRequestNewChat(_ viewController: AIChatContextualSheetViewController) {
        // TODO: Later
    }
}
