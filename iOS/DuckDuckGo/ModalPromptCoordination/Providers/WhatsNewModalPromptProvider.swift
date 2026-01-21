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
import PrivacyConfig

@MainActor
final class WhatsNewCoordinator: NSObject, ModalPromptProvider {
    enum DisplayContext: Equatable {
        // Shown via modal prompt coordination schedule when a remote message is delivered.
        case scheduled
        // Shown when user opened the prompt on-demand.
        case onDemand
    }

    private let displayContext: DisplayContext
    private let repository: WhatsNewMessageRepository
    private let remoteMessageActionHandler: RemoteMessagingActionHandling
    private let isIPad: Bool
    private let pixelReporter: RemoteMessagingPixelReporting?
    private let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    private let displayModelMapper: WhatsNewDisplayModelMapping

    private weak var navigationController: UINavigationController?

    private var remoteMessage: RemoteMessageModel?
    private let featureFlagger: FeatureFlagger

    init(
        displayContext: DisplayContext,
        repository: WhatsNewMessageRepository,
        remoteMessageActionHandler: RemoteMessagingActionHandling,
        isIPad: Bool,
        pixelReporter: RemoteMessagingPixelReporting?,
        userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
        displayModelMapper: WhatsNewDisplayModelMapping = WhatsNewDisplayModelMapper(),
        featureFlagger: FeatureFlagger
    ) {
        self.displayContext = displayContext
        self.repository = repository
        self.remoteMessageActionHandler = remoteMessageActionHandler
        self.isIPad = isIPad
        self.pixelReporter = pixelReporter
        self.userScriptsDependencies = userScriptsDependencies
        self.displayModelMapper = displayModelMapper
        self.featureFlagger = featureFlagger
    }

    // MARK: - ModalPromptProvider

    func provideModalPrompt() -> ModalPromptConfiguration? {
        let message: RemoteMessageModel?
        switch displayContext {
        case .scheduled:
            message = repository.fetchScheduledMessage()
        case .onDemand:
            message = repository.fetchLastShownMessage()
        }

        guard let message else {
            Logger.modalPrompt.info("\(self.logPrefix) - What's New - No message for context: \(self.displayContext.debugDescription)")
            return nil
        }

        guard let viewController = makeViewController(message: message) else {
            Logger.modalPrompt.info("\(self.logPrefix) - What's New - Could not render message \(message.id, privacy: .public)")
            return nil
        }
        self.navigationController = viewController

        // Store the message ID to mark it as shown later
        self.remoteMessage = message

        Logger.modalPrompt.info("\(self.logPrefix) - What's New - Providing modal for message: \(message.id, privacy: .public)")

        return ModalPromptConfiguration(
            viewController: viewController,
            animated: true
        )
    }

    func didPresentModal() {
        // Only mark as shown for modal prompt context
        guard displayContext == .scheduled else { return }

        Logger.modalPrompt.info("\(self.logPrefix) - What's New - Did present modal")
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
        let embeddedWebViewController = EmbeddedWebViewController(
            url: url,
            userScriptsDependencies: userScriptsDependencies,
            featureFlagger: featureFlagger)
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

    var logPrefix: String {
        switch displayContext {
        case .scheduled:
            return "[Modal Prompt Coordination]"
        case .onDemand:
            return "[What's New On Demand]"
        }
    }

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
        guard let message = remoteMessage else {
            Logger.modalPrompt.error("\(self.logPrefix) - What's New - Cannot mark message as shown - no current message")
            return
        }

        // Mark message seen (needed to send the right pixel. E.g. first vs subsequent time)
        // Mark the messages "seen" and avoid showing it again
        await repository.markMessageAsShown(message)
        Logger.modalPrompt.info("\(self.logPrefix) - What's New - Marked message as shown: \(message.id, privacy: .public)")
    }

    func dismiss(source: DismissSource) {
        Logger.modalPrompt.info("\(self.logPrefix) - What's New - Dismissed From source: \(source.debugDescription, privacy: .public)")
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

        let hasAlreadySeenMessage = repository.hasShownMessage(withID: remoteMessage.id)
        pixelReporter?.measureRemoteMessageAppeared(remoteMessage, hasAlreadySeenMessage: hasAlreadySeenMessage)
    }

    func measureMessageDismissed(source: DismissSource) {
        guard let message = remoteMessage else {
            assertionFailure("What's New - Cannot measure message dismissed - no current message")
            return
        }

        switch source {
        case .closeButton:
            pixelReporter?.measureRemoteMessageDismissed(message, dismissType: .closeButton)
        case .pullDown:
            pixelReporter?.measureRemoteMessageDismissed(message, dismissType: .pullDown)
        case .mainAction:
            pixelReporter?.measureRemoteMessageDismissed(message, dismissType: .primaryAction)
        }
    }

    func measurePrimaryActionTapped() {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure primary action tapped - no current message")
            return
        }
        
        pixelReporter?.measureRemoteMessagePrimaryActionClicked(remoteMessage)
    }

    func measureCardShown(cardId: String) {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure card shown - no current message")
            return
        }

        pixelReporter?.measureRemoteMessageCardShown(remoteMessage, cardId: cardId)
    }

    func measureCardTapped(cardId: String) {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure card tapped - no current message")
            return
        }

        pixelReporter?.measureRemoteMessageCardClicked(remoteMessage, cardId: cardId)
    }

    func measureSheetShown(result: Bool) {
        guard let remoteMessage else {
            assertionFailure("What's New - Cannot measure sheet shown - no current message")
            return
        }
        pixelReporter?.measureRemoteMessageSheetShown(remoteMessage, sheetResult: result)
    }

}

// MARK: - DisplayContext + CustomDebugStringConvertible

extension WhatsNewCoordinator.DisplayContext: CustomDebugStringConvertible {

    var debugDescription: String {
        switch self {
        case .scheduled: "Prompt Coordination"
        case .onDemand: "On Demand"
        }
    }

}

// MARK: - WhatsNewCoordinator + DismissSource

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

// MARK: - WhatsNewCoordinator + On Demand Prompt

extension WhatsNewCoordinator: OnDemandModalPromptProvider {

    var canShowPromptOnDemand: Bool {
        repository.fetchLastShownMessage() != nil
    }

}
