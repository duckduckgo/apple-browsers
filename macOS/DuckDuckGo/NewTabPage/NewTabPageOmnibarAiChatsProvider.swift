//
//  NewTabPageOmnibarAiChatsProvider.swift
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
import FeatureFlags
import PrivacyConfig
import Foundation
import NewTabPage

final class NewTabPageOmnibarAiChatsProvider: NewTabPageOmnibarAiChatsProviding {

    private let featureFlagger: FeatureFlagger
    private let suggestionsReader: AIChatSuggestionsReading
    private var cancellables = Set<AnyCancellable>()

    init(featureFlagger: FeatureFlagger, configProvider: NewTabPageOmnibarConfigProviding, suggestionsReader: AIChatSuggestionsReading) {
        self.featureFlagger = featureFlagger
        self.suggestionsReader = suggestionsReader

        // configProvider is not stored — Combine keeps the publisher pipeline alive
        // as long as the cancellables are retained. If configProvider is deallocated,
        // the publishers stop emitting, which is safe (no teardown needed if there's
        // nothing to manage).
        configProvider.modePublisher
            .filter { $0 == .search }
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.suggestionsReader.tearDown()
                }
            }
            .store(in: &cancellables)

        Publishers.Merge(
            configProvider.isAIChatShortcutEnabledPublisher.filter { !$0 }.map { _ in () },
            configProvider.isAIChatSettingVisiblePublisher.filter { !$0 }.map { _ in () }
        )
        .sink { [weak self] in
            Task { @MainActor in
                self?.suggestionsReader.tearDown()
            }
        }
        .store(in: &cancellables)
    }

    @MainActor
    func aiChats(query: String?) async -> NewTabPageDataModel.AiChatsData {
        guard featureFlagger.isFeatureOn(.aiChatNtpRecentChats) else {
            return .empty
        }
        let effectiveQuery = query
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let (pinned, recent) = await suggestionsReader.fetchSuggestions(query: effectiveQuery)
        let viewModel = AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount)
        viewModel.setChats(pinned: pinned, recent: recent)
        let chats = viewModel.filteredSuggestions.map { $0.asNewTabPageAiChat }
        return NewTabPageDataModel.AiChatsData(chats: chats)
    }

}

private extension AIChatSuggestion {
    var asNewTabPageAiChat: NewTabPageDataModel.AiChat {
        NewTabPageDataModel.AiChat(
            chatId: chatId,
            title: title,
            pinned: isPinned,
            lastEdit: Self.formatISO8601Date(timestamp),
            firstUserMessageContent: firstUserMessageContent
        )
    }

}
