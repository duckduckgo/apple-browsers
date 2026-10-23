//
//  FreshChatSuggestionsPresentation.swift
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

/// A destination-bound adapter. Native and web use separate parents and one renderer.
@MainActor
final class FreshChatSuggestionsPresentation {
    private weak var tab: TabViewController?
    private weak var input: UnifiedToggleInputCoordinator?
    private let content: FreshChatSuggestionsView
    private var subscriptions = Set<AnyCancellable>()
    private var submitted = false
    private var isActive = true
    private let destinationID: String
    private let nativeChat: NativeTabChat?
    private let initialURL: URL?
    private weak var webRecipient: AIChatUserScript?

    init(tab: TabViewController, input: UnifiedToggleInputCoordinator) {
        self.tab = tab
        self.input = input
        destinationID = tab.tabModel.uid
        nativeChat = tab.nativeChat
        content = FreshChatSuggestionsView(welcome: tab.nativeChat == nil ? .privateChat : .local)
        initialURL = tab.url ?? tab.link?.url
        webRecipient = tab.userScripts?.aiChatUserScript
        content.isHidden = true
        mount(in: tab)
        input.$freshSuggestionsState.sink { [weak self] state in self?.render(state) }.store(in: &subscriptions)
        input.textChangePublisher.sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        input.didSubmitPrompt.sink { [weak self] _ in
            self?.submitted = true
            self?.refresh()
        }.store(in: &subscriptions)
        tab.urlPublisher.sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        observeNativeState()
        refresh()
    }

    func matches(tab: TabViewController, input: UnifiedToggleInputCoordinator) -> Bool {
        isActive && self.tab === tab && self.input === input && nativeChat === tab.nativeChat
    }

    func deactivate() {
        isActive = false
        subscriptions.removeAll()
        content.removeFromSuperview()
        if input?.currentTabUID == destinationID { input?.hideFreshSuggestions() }
    }

    func refresh() {
        guard let input else { return }
        if nativeChat == nil, webRecipient !== tab?.userScripts?.aiChatUserScript {
            input.hideFreshSuggestions()
            webRecipient = tab?.userScripts?.aiChatUserScript
        }
        content.isHidden = !isFresh
        input.refreshFreshSuggestions(destinationID: destinationID, isFresh: { [weak self] in self?.isFresh == true })
    }

    private var isFresh: Bool {
        guard isActive, !submitted, let tab, let input,
              input.currentTabUID == destinationID, !input.hasSubmittedPrompt,
              input.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let nativeChat {
            if case .error = nativeChat.session.state.status { return false }
            return !nativeChat.restoredAfterRelaunch && tab.nativeChat === nativeChat && nativeChat.session.state.messages.isEmpty
                && nativeChat.session.state.context.opening == nil
        }
        guard tab.nativeChat == nil, let webRecipient, tab.userScripts?.aiChatUserScript === webRecipient, let url = tab.url ?? tab.link?.url,
              url == initialURL, url.isDuckAIURL, url.duckAIChatID == nil,
              ["", "/", "/chat", "/chat/"].contains(url.path),
              !url.isDuckAISidebarOpen, !url.isDuckAISettingsOpen,
              !url.isDuckAIChatProtectionOpen, !url.isDuckAIVoiceMode else { return false }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let promptNames: Set<String> = [AIChatURLParameters.promptQueryName, AIChatURLParameters.autoSubmitPromptQueryName,
                                        AIChatURLParameters.flowQueryName, AIChatURLParameters.toolChoiceName]
        return !query.contains { promptNames.contains($0.name) }
    }

    private func observeNativeState() {
        guard let nativeChat, isActive else { return }
        withObservationTracking {
            _ = nativeChat.session.state.messages
            _ = nativeChat.session.state.status
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeNativeState()
            }
        }
    }

    private func mount(in tab: TabViewController) {
        // Native content covers the transcript's empty state. Web content stays inside its
        // existing content rectangle so the shared header and composer keep their controls.
        let parent = nativeChat?.viewController.view ?? tab.outerContainer!
        let bounds = nativeChat == nil ? tab.webViewContainer! : parent
        parent.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: bounds.topAnchor),
            content.leadingAnchor.constraint(equalTo: bounds.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: bounds.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bounds.bottomAnchor)
        ])
    }

    private func render(_ state: FreshChatSuggestionsState) {
        guard isFresh else {
            content.isHidden = true
            return
        }
        switch state {
        case .hidden:
            content.isHidden = true
        case .loading:
            content.isHidden = false
            content.render(.loading)
        case .unavailable:
            content.isHidden = false
            content.render(.unavailable)
        case .ready(let suggestions):
            content.isHidden = false
            content.render(.ready(suggestions.map { suggestion in
                FreshChatSuggestionsView.Action(title: suggestion.label) { [weak self] in
                    guard let self, self.isFresh else { return }
                    self.input?.selectFreshSuggestion(suggestion)
                }
            }))
        }
    }
}

extension TabViewController {
    func bindFreshChatSuggestions(to input: UnifiedToggleInputCoordinator) {
        if let presentation = freshChatSuggestionsPresentation, presentation.matches(tab: self, input: input) {
            presentation.refresh()
            return
        }
        freshChatSuggestionsPresentation?.deactivate()
        freshChatSuggestionsPresentation = FreshChatSuggestionsPresentation(tab: self, input: input)
    }
}
