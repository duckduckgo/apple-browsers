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
    private weak var webVC: AIChatContextualWebViewController?
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
        self.chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            attachedURLPublisher: attachedURLPublisher,
            onAttach: { [weak pageContextHandler] _ in
                Logger.contextualUTI.info("UTIHost: chip onAttach — triggering context collection")
                _ = pageContextHandler?.triggerContextCollection()
            }
        )
        coordinator.viewController.bindPageContextChip(to: chipViewModel)
        coordinator.didSubmitPrompt
            .sink { [weak self] prompt in
                Logger.contextualUTI.info("UTIHost: didSubmitPrompt — forwarding to web VC")
                self?.webVC?.submitPrompt(prompt, pageContext: nil)
            }
            .store(in: &cancellables)
    }

    func install(in webVC: AIChatContextualWebViewController) {
        self.webVC = webVC
        webVC.addChild(coordinator.viewController)
        webVC.view.addSubview(coordinator.viewController.view)
        coordinator.viewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coordinator.viewController.view.leadingAnchor.constraint(equalTo: webVC.view.leadingAnchor),
            coordinator.viewController.view.trailingAnchor.constraint(equalTo: webVC.view.trailingAnchor),
            coordinator.viewController.view.bottomAnchor.constraint(equalTo: webVC.view.keyboardLayoutGuide.topAnchor),
        ])
        webVC.anchorWebViewBottom(to: coordinator.viewController.view.topAnchor)
        coordinator.viewController.didMove(toParent: webVC)
        coordinator.showExpanded()
        Logger.contextualUTI.info("UTIHost: installed at bottom of contextual web VC")
    }
}
