//
//  AIChatContextualUTIHost.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Combine
import UIKit
import os.log

/// Owns a `UnifiedToggleInputCoordinator` configured for the contextual chat surface and
/// embeds its view controller as a child of `AIChatContextualWebViewController`.
@MainActor
final class AIChatContextualUTIHost {

    private let coordinator: UnifiedToggleInputCoordinator
    private let pageContextHandler: AIChatPageContextHandling
    private let chipViewModel: UnifiedToggleInputPageContextChipViewModel
    private let chipPushState = ChipPushState()
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        attachedURLPublisher: AnyPublisher<URL?, Never>,
        pageContextHandler: AIChatPageContextHandling,
        isFireTab: Bool
    ) {
        self.pageContextHandler = pageContextHandler
        self.coordinator = UnifiedToggleInputCoordinator(
            host: .contextualChat,
            isToggleEnabled: false,
            isFireTab: isFireTab
        )
        let chipPushState = self.chipPushState
        self.chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            attachedURLPublisher: attachedURLPublisher,
            onAttach: { [weak pageContextHandler] _ in
                guard let pageContextHandler else { return }
                Logger.contextualUTI.info("UTIHost: chip onAttach — triggering context collection")
                let didTrigger = pageContextHandler.triggerContextCollection()
                guard didTrigger else {
                    Logger.contextualUTI.error("UTIHost: triggerContextCollection returned false")
                    return
                }
                chipPushState.cancellable = pageContextHandler.contextPublisher
                    .dropFirst()
                    .prefix(1)
                    .sink { context in
                        guard let context else {
                            Logger.contextualUTI.error("UTIHost: collection completed with nil context")
                            return
                        }
                        Logger.contextualUTI.info("UTIHost: pushing collected context to contextual chat for FE delivery")
                        chipPushState.contextualChatViewController?.pushPageContext(context.contextData)
                    }
            }
        )
        coordinator.viewController.bindPageContextChip(to: chipViewModel)
    }

    /// Binds the UTI coordinator to the contextual chat's `AIChatUserScript` so submitted prompts
    /// flow through the same JS message channel the FE uses today, preserving model/tools/images.
    func bindToUserScript(_ userScript: AIChatUserScript) {
        Logger.contextualUTI.info("UTIHost: binding coordinator to AIChatUserScript")
        coordinator.bindToTab(userScript)
    }

    func install(in contextualChatViewController: AIChatContextualWebViewController) {
        chipPushState.contextualChatViewController = contextualChatViewController
        coordinator.attachmentPresentingViewController = contextualChatViewController
        contextualChatViewController.addChild(coordinator.viewController)
        contextualChatViewController.view.addSubview(coordinator.viewController.view)
        coordinator.viewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coordinator.viewController.view.leadingAnchor.constraint(equalTo: contextualChatViewController.view.leadingAnchor),
            coordinator.viewController.view.trailingAnchor.constraint(equalTo: contextualChatViewController.view.trailingAnchor),
            coordinator.viewController.view.bottomAnchor.constraint(equalTo: contextualChatViewController.view.keyboardLayoutGuide.topAnchor),
        ])
        contextualChatViewController.anchorWebViewBottom(to: coordinator.viewController.view.topAnchor)
        coordinator.viewController.didMove(toParent: contextualChatViewController)
        coordinator.showExpanded()
        Logger.contextualUTI.info("UTIHost: installed at bottom of contextual chat")
    }
}

/// Holds shared state captured by the chip-onAttach closure: a weak ref to the contextual chat
/// view controller (so we can push freshly-collected context to it) and the cancellable for the
/// one-shot context subscription.
@MainActor
private final class ChipPushState {
    weak var contextualChatViewController: AIChatContextualWebViewController?
    var cancellable: AnyCancellable?
}
