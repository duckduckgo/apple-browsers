//
//  NativeTabChat.swift
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
import DuckAINative
import Observation
import UIKit

/// A native chat shown in a Duck.ai tab in place of its web view. The tab keeps its normal AI-tab chrome; while the
/// tab is current, the main input sends prompts and Stop here instead of to the hidden web page.
@MainActor
final class NativeTabChat: NativeChatDelegate {
    let session: ChatSession
    private(set) lazy var viewController: UIViewController = DuckAINative.makeChatViewController(
        session: session, surface: .tab, showsComposer: false, delegate: self)
    var onContinueInWeb: (() -> Void)?

    private weak var input: UnifiedToggleInputCoordinator?
    private var stopSubscription: AnyCancellable?
    private static weak var attached: NativeTabChat?

    init(context: ChatContext) {
        session = ChatSession(context: context, provider: NativeChatProviderFactory.makeProvider(for: .chat))
    }

    static func newChat() -> NativeTabChat? {
        (try? ChatContext(page: nil, selections: [], opening: nil)).map(NativeTabChat.init)
    }

    /// Only one chat drives the shared input at a time: the one in the current tab.
    func attach(to input: UnifiedToggleInputCoordinator) {
        if Self.attached !== self { Self.attached?.detach() }
        Self.attached = self
        input.unbind()
        self.input = input
        stopSubscription = input.didPressStopGeneratingButton.sink { [weak self] in self?.session.stop() }
        observeStatus()
    }

    func detach() {
        stopSubscription = nil
        input?.aiChatStatus = .ready
        input = nil
        if Self.attached === self { Self.attached = nil }
    }

    static func detachCurrent() {
        attached?.detach()
    }

    func nativeChatDidRequestClose() {}

    func nativeChatDidRequestContinueInWeb(_ context: ChatContext) {
        onContinueInWeb?()
    }

    private func observeStatus() {
        let status = withObservationTracking {
            session.state.status
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatus() }
        }
        guard let input else { return }
        switch status {
        case .ready: input.aiChatStatus = .ready
        case .loading: input.aiChatStatus = .loading
        case .streaming: input.aiChatStatus = .streaming
        case .error: input.aiChatStatus = .error
        }
    }
}

extension TabViewController {

    /// Covers the web view with the native chat; the tab stays a Duck.ai tab underneath.
    func showNativeChat(_ chat: NativeTabChat) {
        removeNativeChat()
        nativeChat = chat
        let chatView = chat.viewController.view!
        addChild(chat.viewController)
        chatView.translatesAutoresizingMaskIntoConstraints = false
        outerContainer.addSubview(chatView)
        NSLayoutConstraint.activate([
            chatView.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
            chatView.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
            chatView.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
            chatView.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor)
        ])
        chat.viewController.didMove(toParent: self)
        webView.isHidden = true
    }

    func removeNativeChat() {
        guard let chat = nativeChat else { return }
        nativeChat = nil
        chat.detach()
        chat.viewController.willMove(toParent: nil)
        chat.viewController.view.removeFromSuperview()
        chat.viewController.removeFromParent()
        webView.isHidden = false
    }
}

extension URL {

    /// The same Duck.ai page without the prompt, so the hidden web page under a native chat never sends it.
    var withoutDuckAIPrompt: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        let promptItems: Set<String> = [AIChatURLParameters.promptQueryName, AIChatURLParameters.autoSubmitPromptQueryName,
                                        AIChatURLParameters.flowQueryName, AIChatURLParameters.toolChoiceName]
        components.queryItems = components.queryItems?.filter { !promptItems.contains($0.name) }
        return components.url ?? self
    }
}
