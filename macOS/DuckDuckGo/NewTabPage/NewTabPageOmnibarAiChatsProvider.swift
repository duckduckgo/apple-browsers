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
import FeatureFlags_macOS
import PrivacyConfig
import Foundation
import NewTabPage
import os.log

final class NewTabPageOmnibarAiChatsProvider: NewTabPageOmnibarAiChatsProviding {

    private let featureFlagger: FeatureFlagger
    private let suggestionsReader: AIChatSuggestionsReading
    private let searchPreferences: SearchPreferences
    /// POC: reads every stored chat, bypassing the suggestions reader's 7-day window and
    /// result cap so the chats rail can show a full history.
    private let historyCleaner: AIChatHistoryCleaning
    private var cancellables = Set<AnyCancellable>()
    @Published private var hasExcessChats = false

    var hasExcessChatsPublisher: AnyPublisher<Bool, Never> {
        $hasExcessChats.eraseToAnyPublisher()
    }

    init(featureFlagger: FeatureFlagger,
         configProvider: NewTabPageOmnibarConfigProviding,
         suggestionsReader: AIChatSuggestionsReading,
         searchPreferences: SearchPreferences,
         historyCleaner: AIChatHistoryCleaning) {
        self.featureFlagger = featureFlagger
        self.suggestionsReader = suggestionsReader
        self.searchPreferences = searchPreferences
        self.historyCleaner = historyCleaner

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
        // POC: three things dropped here so the chats rail can show a real, full history in a
        // demo build. Restore all of it before this goes anywhere real:
        //  - the .aiChatNtpRecentChats and showAutocompleteSuggestions guards;
        //  - the suggestions reader, whose unqueried path only returns pinned chats plus the
        //    last 7 days, and which caps results at maxHistoryCount (5 on macOS);
        //  - hasExcessChats, which drove the "View all chats" footer and is now always false.
        let effectiveQuery = query
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let all = historyCleaner.allChats()
        let matching = effectiveQuery.map { query in
            all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        } ?? all

        // Pinned first, then most recently edited, matching ChatHistoryReader's ordering.
        let sorted = matching.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return (lhs.lastEdit ?? "") > (rhs.lastEdit ?? "")
        }

        hasExcessChats = false
        return NewTabPageDataModel.AiChatsData(chats: sorted.map(\.asNewTabPageAiChat))
    }

}

private extension DuckAiChat {
    var asNewTabPageAiChat: NewTabPageDataModel.AiChat {
        NewTabPageDataModel.AiChat(
            chatId: chatId,
            title: title,
            pinned: pinned,
            lastEdit: lastEdit,
            model: model
        )
    }

}
