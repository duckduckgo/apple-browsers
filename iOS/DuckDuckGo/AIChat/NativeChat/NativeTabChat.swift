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
        session: session, surface: .tab,
        emptyState: ChatEmptyState(image: UIImage(resource: .duckAIDefault), title: restoredAfterRelaunch ? "Start a new local chat. Previous messages were not saved." : "All chats are local"), delegate: self)
    var onContinueInWeb: (() -> Void)?

    private weak var input: UnifiedToggleInputCoordinator?
    private var stopSubscription: AnyCancellable?
    private static weak var attached: NativeTabChat?

    init(session: ChatSession, restoredAfterRelaunch: Bool = false) {
        self.session = session
        self.restoredAfterRelaunch = restoredAfterRelaunch
    }

    private let restoredAfterRelaunch: Bool

    convenience init(context: ChatContext) {
        self.init(session: ChatSession(context: context, provider: NativeChatProviderFactory.makeProvider(for: .chat)))
    }

    /// The header title: which model answers, on this device.
    var title: String {
        let descriptor = session.descriptor
        let name = descriptor.displayName == "MLX" ? descriptor.modelName.replacingOccurrences(of: " (4-bit)", with: "") : descriptor.displayName
        return "\(name) · On device"
    }

    static func newChat() -> NativeTabChat? {
        (try? ChatContext(page: nil, selections: [], opening: nil)).map(NativeTabChat.init)
    }

    /// Only one chat drives the shared input at a time: the one in the current tab.
    func attach(to input: UnifiedToggleInputCoordinator) {
        if Self.attached !== self { Self.attached?.detach() }
        Self.attached = self
        input.unbind()
        input.nativeSession = session
        input.refreshNativeInputCapabilities()
        self.input = input
        stopSubscription = input.didPressStopGeneratingButton.sink { [weak self] in self?.session.stop() }
        observeStatus()
    }

    func detach() {
        stopSubscription = nil
        input?.aiChatStatus = .ready
        input?.nativeSession = nil
        input?.refreshNativeInputCapabilities()
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
        input.refreshNativeInputCapabilities()
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
        if let previousSession = tabModel.nativeChatSession, previousSession !== chat.session { previousSession.close() }
        removeNativeChat(preservingSession: true)
        nativeChat = chat
        tabModel.nativeChatSession = chat.session
        tabModel.nativeChatWasOpen = true
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

    func removeNativeChat(preservingSession: Bool = false) {
        if !preservingSession {
            tabModel.nativeChatSession?.close()
            tabModel.nativeChatSession = nil
            tabModel.nativeChatWasOpen = false
        }
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

/// Explicit web destinations must stay web even when new chats default to local inference.
enum DuckAIChatDestination: Equatable {
    case web
    case native(prompt: String?)

    static func forURL(_ url: URL, opensNatively: Bool) -> Self {
        guard opensNatively, url.isDuckAIURL,
              url.path.isEmpty || url.path == "/",
              url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .web }
        let items = components.queryItems ?? []
        let webParameters: Set<String> = ["chatID", AIChatURLParameters.settingsName, AIChatURLParameters.sidebarName,
                                          AIChatURLParameters.chatProtectionName, AIChatURLParameters.customizeResponsesName,
                                          AIChatURLParameters.modeName, AIChatURLParameters.toolChoiceName, AIChatURLParameters.flowQueryName]
        guard !items.contains(where: { webParameters.contains($0.name) }) else { return .web }
        let prompt = items.first { $0.name == AIChatURLParameters.promptQueryName }?.value
        // A non-submitted URL prompt belongs to the web draft. Never silently drop it.
        if let prompt, !prompt.isEmpty {
            guard items.contains(where: { $0.name == AIChatURLParameters.autoSubmitPromptQueryName && $0.value == "1" }) else { return .web }
            return .native(prompt: prompt)
        }
        return .native(prompt: nil)
    }

    @MainActor
    func makeNativeChat() -> NativeTabChat? {
        guard case .native(let prompt) = self,
              let context = try? ChatContext(page: nil, selections: [], opening: prompt.map(Opening.prompt)) else { return nil }
        return NativeTabChat(context: context)
    }
}
