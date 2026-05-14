//
//  AIChatSession.swift
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
import Foundation

/// Per-tab session that owns an `AIChatState` (persisted model) and transient UI references
/// (view controller, floating window controller). Manages VC creation, Combine plumbing
/// for restoration data and page context, and teardown.
final class AIChatSession {

    let state: AIChatState
    let burnerMode: BurnerMode

    private(set) var chatViewController: AIChatViewController? {
        didSet {
            subscribeToRestorationDataUpdates()
            chatViewControllerSubject.send(chatViewController)
        }
    }

    var floatingWindowController: AIChatFloatingWindowController?

    private let chatViewControllerSubject = CurrentValueSubject<AIChatViewController?, Never>(nil)
    private var restorationDataCancellable: AnyCancellable?

    /// Publishes when the active view controller's page context is requested.
    /// Automatically switches to the latest VC's publisher when the VC changes.
    var pageContextRequestedPublisher: AnyPublisher<Void, Never> {
        chatViewControllerSubject
            .compactMap { $0?.pageContextRequestedPublisher }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    /// Publishes when a prompt is submitted in the active chat session.
    var pageContextConsumedPublisher: AnyPublisher<Void, Never> {
        chatViewControllerSubject
            .compactMap { $0?.pageContextConsumedPublisher }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    /// Publishes when the user explicitly removes page context from the chat.
    var pageContextRemovedPublisher: AnyPublisher<Void, Never> {
        chatViewControllerSubject
            .compactMap { $0?.pageContextRemovedPublisher }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    /// The live AI Chat URL (reads from the VC if alive, falls back to persisted state).
    var currentAIChatURL: URL {
        chatViewController?.currentAIChatURL ?? state.currentAIChatURL
    }

    init(state: AIChatState, burnerMode: BurnerMode) {
        self.state = state
        self.burnerMode = burnerMode
    }

    /// Lazily creates a chat view controller for the given tab, reusing an existing one if present.
    func makeChatViewController(tabID: TabIdentifier) -> AIChatViewController {
        if let existing = chatViewController {
            return existing
        }

        let viewController = AIChatViewController(currentAIChatURL: currentAIChatURL, burnerMode: burnerMode)
        viewController.tabID = tabID
        if let restorationData = state.restorationData {
            viewController.setAIChatRestorationData(restorationData)
        }
        chatViewController = viewController
        return viewController
    }

    /// Snapshots the live URL into the persisted state so it survives serialization.
    func snapshotCurrentURL() {
        if let chatViewController {
            state.aiChatURL = chatViewController.currentAIChatURL
        }
    }

    /// Persists state and tears down transient references. Call from the coordinator/store.
    func tearDown(persistingState: Bool) {
        if persistingState {
            snapshotCurrentURL()
        }

        // Stop loading only after URL snapshot so restoration does not capture
        // a transient blank-page URL from teardown.
        chatViewController?.stopLoading()
        floatingWindowController = nil
        chatViewController = nil
        restorationDataCancellable = nil

        state.setHidden()
    }

    private func subscribeToRestorationDataUpdates() {
        restorationDataCancellable = nil

        restorationDataCancellable = chatViewController?.chatRestorationDataPublisher?
            .sink { [weak self] restorationData in
                self?.state.restorationData = restorationData
            }
    }
}
