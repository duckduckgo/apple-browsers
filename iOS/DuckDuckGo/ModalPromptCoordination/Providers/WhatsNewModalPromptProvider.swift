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
    private var navigationController: UINavigationController?
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

        guard let displayModel = makeDisplayModel(from: message) else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Could not render message \(message.id, privacy: .public)")
            return nil
        }

        Logger.modalPrompt.info("[Modal Prompt Coordination] - What's New - Providing modal for message: \(message.id, privacy: .public)")

        // Store the message ID to mark it as shown later
        self.currentMessageId = message.id

        let viewController = makeViewController(displayModel: displayModel)
        self.navigationController = viewController

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
        print("[Modal Prompt Coordination] - What's New - Present Share Item")
    }

    @MainActor
    func presentEmbeddedWebView(url: URL) async {
        print("[Modal Prompt Coordination] - What's New - Present Embedded Web View")
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

    func makeViewController(displayModel: RemoteMessagingUI.CardsListDisplayModel) -> WhatsNewViewController {
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

    func makeDisplayModel(from message: RemoteMessageModel) -> RemoteMessagingUI.CardsListDisplayModel? {
        guard
            let contentType = message.content,
            case let .cardsList(mainTitleText, items, primaryActionText, primaryAction) = contentType
        else {
            return nil
        }

        let dismissAction: () -> Void = { [weak self] in
            self?.dismiss(source: .mainAction)
        }

        let promoItems = items.map { remoteListItem in
            RemoteMessagingUI.CardsListDisplayModel.Item(
                icon: Image(remoteListItem.placeholderImage.rawValue),
                title: remoteListItem.titleText,
                description: remoteListItem.descriptionText,
                disclosureIcon: Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronRightSmall),
                onTapAction: remoteListItem.action.map { action in
                    makeAction(for: action)
                }
            )
        }

        return RemoteMessagingUI.CardsListDisplayModel(
            screenTitle: mainTitleText,
            items: promoItems,
            onAppear: nil,
            primaryAction: (
                title: primaryActionText,
                action: makeAction(for: primaryAction, andDismiss: dismissAction)
            )
        )
    }

    func makeAction(
        for remoteAction: RemoteAction,
        andDismiss dismissAction: (() -> Void)? = nil
    ) -> () -> Void {
        return {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.remoteMessageActionHandler.handleAction(remoteAction, presenter: self)
                dismissAction?()
            }
        }
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
