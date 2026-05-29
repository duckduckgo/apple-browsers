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

/// View-layer model for a single chat row. Decouples the views from `DuckAiChat`
/// (the storage type), so previews and tests only depend on this 4-field struct.
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
/// loads chats from a `ChatHistoryReading` data source, and publishes pinned/recent
/// arrays for the views. Emits intents to its delegate (the presenter), which
/// translates each intent into the matching UIKit action.
@MainActor
final class AIChatHistoryViewModel: ObservableObject {

    @Published private(set) var pinned: [ChatItem] = []
    @Published private(set) var recent: [ChatItem] = []
    @Published private(set) var isLoading: Bool = false

    var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }

    private let reader: ChatHistoryReading

    weak var delegate: AIChatHistoryViewModelDelegate?

    init(reader: ChatHistoryReading) {
        self.reader = reader
    }

    func loadChats() async {
        isLoading = true
        defer { isLoading = false }

        // Match Android: read every chat the local database holds. The reader
        // already returns chats with pinned-first ordering and `lastEdit` desc.
        let result = await reader.fetchAllChats(query: nil)
        switch result {
        case .success(let chats):
            let items = chats.map(ChatItem.init(from:))
            self.pinned = items.filter(\.pinned)
            self.recent = items.filter { !$0.pinned }
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
    init(from chat: DuckAiChat) {
        // Reuse the canonical model-string → kind helper used by autocomplete so
        // the chat-history rows stay in sync with how the rest of the app
        // classifies Duck.ai chat types.
        let suggestionKind = AIChatSuggestion.kind(forModel: chat.model)
        self.init(
            id: chat.chatId,
            title: chat.title,
            kind: ChatItem.Kind(from: suggestionKind),
            pinned: chat.pinned
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
