//
//  AIChatHistoryViewModel.swift
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

import Foundation
import AIChat

/// View-layer model for a single chat row. Decouples the SwiftUI views from
/// `AIChatSuggestion` (the upstream `AIChat`-module type), so previews and tests
/// only depend on this 4-field struct.
struct ChatItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case text
        case voice
        case image
    }

    let id: String
    let title: String
    let kind: Kind
    let pinned: Bool
}

/// Backing model for the native Duck.ai chat-history sheet. Owns user intents,
/// loads chats from a `SuggestionsReading` data source, and publishes pinned/recent
/// arrays for the SwiftUI views. Emits intents to its delegate (the presenter), which
/// translates each intent into the matching UIKit action.
@MainActor
final class AIChatHistoryViewModel: ObservableObject {

    @Published private(set) var pinned: [ChatItem] = []
    @Published private(set) var recent: [ChatItem] = []
    @Published private(set) var isLoading: Bool = false

    var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }

    private let suggestionsReader: LocalSuggestionsReader

    weak var delegate: AIChatHistoryViewModelDelegate?

    init(suggestionsReader: LocalSuggestionsReader) {
        self.suggestionsReader = suggestionsReader
    }

    func loadChats() async {
        isLoading = true
        defer { isLoading = false }

        // Android shows every chat the local database holds — no recency window,
        // no count cap. `fetchAllChats` mirrors that on iOS.
        let result = await suggestionsReader.fetchAllChats(query: nil)
        switch result {
        case .success(let (pinned, recent)):
            self.pinned = pinned.map(ChatItem.init(from:))
            self.recent = recent.map(ChatItem.init(from:))
        case .failure:
            self.pinned = []
            self.recent = []
        }
    }

    func openDuckAiTapped() {
        delegate?.viewModelDidRequestOpenDuckAi()
    }
}

@MainActor
protocol AIChatHistoryViewModelDelegate: AnyObject {
    /// Dismiss the sheet and open the Duck.ai web chat.
    func viewModelDidRequestOpenDuckAi()
}

// MARK: - Mapping

private extension ChatItem {
    init(from suggestion: AIChatSuggestion) {
        self.init(
            id: suggestion.chatId,
            title: suggestion.title,
            kind: ChatItem.Kind(from: suggestion.kind),
            pinned: suggestion.isPinned
        )
    }
}

private extension ChatItem.Kind {
    init(from kind: AIChatSuggestion.Kind) {
        switch kind {
        case .text: self = .text
        case .voice: self = .voice
        case .image: self = .image
        }
    }
}
