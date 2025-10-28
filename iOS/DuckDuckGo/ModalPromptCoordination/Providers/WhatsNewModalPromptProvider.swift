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
    private weak var navigationController: UINavigationController?
    private var currentMessageId: String?

    init(
        remoteMessageStore: RemoteMessagingStoring,
        remoteMessageActionHandler: RemoteMessagingActionHandling
    ) {
        self.remoteMessageStore = remoteMessageStore
        self.remoteMessageActionHandler = remoteMessageActionHandler
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
        self.currentMessageId = message.id

        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Providing modal for message: \(message.id, privacy: .public)")

        return ModalPromptConfiguration(
            viewController: viewController,
            presentationStyle: .pageSheet,
            transitionStyle: .coverVertical,
            shouldDisablePullDownToDismiss: false,
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
            WhatsNewDisplayModelMapper.makeDisplayModel(
                from: message,
                onItemAction: { [weak self] action in
                    await self?.handleAction(action)
                },
                onPrimaryAction: { [weak self] action in
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
        viewController.presentationController?.delegate = self

        return viewController
    }

    func markMessageAsShown() async {
        guard let messageId = currentMessageId else {
            Logger.modalPrompt.error("[Modal Prompt Coordination] - What's New - Cannot mark message as shown - no current message ID")
            return
        }

        await remoteMessageStore.updateRemoteMessage(withID: messageId, asShown: true)
        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Marked message as shown: \(messageId, privacy: .public)")
    }

    func handleAction(_ action: RemoteAction) async {
        await remoteMessageActionHandler.handleAction(action, presenter: self)
    }

    func dismiss(source: DismissSource) {
        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Dismissed From source: \(source.debugDescription, privacy: .public)")
        navigationController?.dismiss(animated: true)
    }
}

private extension WhatsNewCoordinator {

    enum DismissSource: CustomDebugStringConvertible {
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
