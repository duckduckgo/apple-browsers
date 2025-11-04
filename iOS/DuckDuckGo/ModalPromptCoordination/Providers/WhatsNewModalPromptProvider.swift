//
//  WhatsNewModalPromptProvider.swift
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
import SwiftUI
import DesignResourcesKitIcons
import RemoteMessaging

@MainActor
final class WhatsNewCoordinator: NSObject, ModalPromptProvider {
    private let remoteMessageStore: RemoteMessagingStoring
    private let remoteMessageActionHandler: RemoteMessagingActionHandling
    private let isIPad: Bool
    private let pixelReporter: RemoteMessagingPixelReporting
    private let displayModelMapper: WhatsNewDisplayModelMapping

    private weak var navigationController: UINavigationController?

    private var remoteMessage: RemoteMessageModel?

    init(
        remoteMessageStore: RemoteMessagingStoring,
        remoteMessageActionHandler: RemoteMessagingActionHandling,
        isIPad: Bool,
        pixelReporter: RemoteMessagingPixelReporting,
        displayModelMapper: WhatsNewDisplayModelMapping = WhatsNewDisplayModelMapper()
    ) {
        self.remoteMessageStore = remoteMessageStore
        self.remoteMessageActionHandler = remoteMessageActionHandler
        self.isIPad = isIPad
        self.pixelReporter = pixelReporter
        self.displayModelMapper = displayModelMapper
    }

    // MARK: - ModalPromptProvider

    func provideModalPrompt() -> ModalPromptConfiguration? {
        guard let message = remoteMessageStore.fetchScheduledRemoteMessage(surfaces: .modal) else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - No scheduled remote modal message")
            return nil
        }

        guard let viewController = makeViewController(message: message) else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Could not render message \(message.id, privacy: .public)")
            return nil
        }
        self.navigationController = viewController

        // Store the message ID to mark it as shown later
        self.remoteMessage = message

        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Providing modal for message: \(message.id, privacy: .public)")

        return ModalPromptConfiguration(
            viewController: viewController,
            animated: true
        )
    }

    func didPresentModal() {
        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Did present modal")
        Task {
            await markMessageAsShown()
        }
    }
}

// MARK: - RemoteMessagingPresenter

extension WhatsNewCoordinator: RemoteMessagingPresenter {

    @MainActor
    func presentActivitySheet(value: String, title: String?) async {
        let activityController = UIActivityViewController(activityItems: [TitleValueShareItem(value: value, title: title).item], applicationActivities: nil)
        activityController.completionWithItemsHandler = { [weak self] _, result, _, _ in
            self?.measureSheetShown(result: result)
        }
        navigationController?.present(activityController, animated: true)
    }

    @MainActor
    func presentEmbeddedWebView(url: URL) async {
        let embeddedWebViewController = EmbeddedWebViewController(url: url)
        navigationController?.pushViewController(embeddedWebViewController, animated: true)
    }

}

// MARK: - UIAdaptivePresentationControllerDelegate

extension WhatsNewCoordinator: UIAdaptivePresentationControllerDelegate {

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        dismiss(source: .pullDown)
    }

}

// MARK: - Private

private extension WhatsNewCoordinator {

    func makeViewController(message: RemoteMessageModel) -> WhatsNewViewController? {

        func makeDisplayModel(for message: RemoteMessageModel) -> RemoteMessagingUI.CardsListDisplayModel? {
            displayModelMapper.makeDisplayModel(
                from: message,
                onMessageAppear: { [weak self] in
                    self?.measureMessageShown()
                },
                onItemAppear: { [weak self] cardId in
                    self?.measureCardShown(cardId: cardId)
                },
                onItemAction: { [weak self] action, cardId in
                    self?.measureCardTapped(cardId: cardId)
                    await self?.handleAction(action)
                },
                onPrimaryAction: { [weak self] action in
                    self?.measurePrimaryActionTapped()
                    await self?.handleAction(action)
                },
                onDismiss: { [weak self] in
                    self?.dismiss(source: .mainAction)
                }
            )
        }

        // Build The UI Message. Return nil if message is unexpected type
        guard let displayModel = makeDisplayModel(for: message) else { return nil }

        let closeButtonDismissAction: () -> Void = { [weak self] in
            self?.dismiss(source: .closeButton)
        }
        let viewController = WhatsNewViewController(displayModel: displayModel, onCloseButton: closeButtonDismissAction)
        viewController.modalPresentationStyle = isIPad ? .formSheet : .pageSheet
        viewController.modalTransitionStyle = .coverVertical
        viewController.presentationController?.delegate = self

        return viewController
    }

    func markMessageAsShown() async {
        guard let messageId = remoteMessage?.id else {
            Logger.modalPrompt.error("[Modal Prompt Coordination] - What's New - Cannot mark message as shown - no current message ID")
            return
        }

        // Mark message seen (needed to send the right pixel. E.g. first vs subsequent time)
        await remoteMessageStore.updateRemoteMessage(withID: messageId, asShown: true)
        // Mark the messages "seen" and avoid showing it again
        await remoteMessageStore.dismissRemoteMessage(withID: messageId)
        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Marked message as shown: \(messageId, privacy: .public)")
    }

    func dismiss(source: DismissSource) {
        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Dismissed From source: \(source.debugDescription, privacy: .public)")
        navigationController?.dismiss(animated: true)
        measureMessageDismissed(source: source)
    }
}

// MARK: - Action Handling

extension WhatsNewCoordinator {

    func handleAction(_ action: RemoteAction) async {
        await remoteMessageActionHandler.handleAction(action, context: .init(presenter: self, presentationStyle: .withinCurrentContext))
    }
    
}

// MARK: - Pixels

private extension WhatsNewCoordinator {

    func measureMessageShown() {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure message as shown - no current message")
            return
        }

        let hasAlreadySeenMessage = remoteMessageStore.hasShownRemoteMessage(withID: remoteMessage.id)
        pixelReporter.measureRemoteMessageAppeared(remoteMessage, hasAlreadySeenMessage: hasAlreadySeenMessage)
    }

    func measureMessageDismissed(source: DismissSource) {
        guard let message = remoteMessage else {
            assertionFailure("What's New - Cannot measure message dismissed - no current message")
            return
        }

        switch source {
        case .closeButton:
            pixelReporter.measureRemoteMessageDismissed(message, dismissType: .closeButton)
        case .pullDown:
            pixelReporter.measureRemoteMessageDismissed(message, dismissType: .pullDown)
        case .mainAction:
            pixelReporter.measureRemoteMessageDismissed(message, dismissType: .primaryAction)
        }
    }

    func measurePrimaryActionTapped() {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure primary action tapped - no current message")
            return
        }
        
        pixelReporter.measureRemoteMessagePrimaryActionClicked(remoteMessage)
    }

    func measureCardShown(cardId: String) {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure card shown - no current message")
            return
        }

        pixelReporter.measureRemoteMessageCardShown(remoteMessage, cardId: cardId)
    }

    func measureCardTapped(cardId: String) {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure card tapped - no current message")
            return
        }

        pixelReporter.measureRemoteMessageCardClicked(remoteMessage, cardId: cardId)
    }

    func measureSheetShown(result: Bool) {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure sheet shown - no current message")
            return
        }
        pixelReporter.measureRemoteMessageSheetShown(remoteMessage, sheetResult: result)
    }

}

private extension WhatsNewCoordinator {

    enum DismissSource: String, CustomDebugStringConvertible {
        case closeButton
        case mainAction
        case pullDown

        var debugDescription: String {
            switch self {
            case .closeButton: "Close Button"
            case .mainAction: "Main CTA"
            case .pullDown: "Pull Down"
            }
        }
    }

}
