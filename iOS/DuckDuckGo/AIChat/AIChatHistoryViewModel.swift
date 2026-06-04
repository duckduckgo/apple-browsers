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

import Combine
import Foundation
import UIKit
import AIChat
import DesignResourcesKitIcons

@MainActor
final class AIChatHistoryViewModel: ObservableObject {

    enum Section: Int, CaseIterable {
        case pinned
        case recent
    }

    @Published private(set) var pinned: [DuckAiChat] = []
    @Published private(set) var recent: [DuckAiChat] = []
    @Published private(set) var hasLoaded: Bool = false

    /// `true` when the chats publisher finished with an error (e.g. native storage failed to
    /// configure). Distinct from `isEmpty` so the UI can show an error state rather than the
    /// "no chats yet" empty state.
    @Published private(set) var loadFailed: Bool = false

    /// Live search query as the user types. Updated synchronously by `updateQuery`.
    @Published private(set) var query: String = ""

    /// The query that produced the current `pinned`/`recent` snapshot. Lags `query` by the
    /// debounce interval. UI state that depends on "is the user searching?" (e.g. the
    /// illustrated empty-state decision) must read this rather than `query` to stay
    /// consistent with what's actually on screen.
    @Published private(set) var effectiveQuery: String = ""

    var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }

    private let reader: ChatHistoryReading
    private var cancellables: Set<AnyCancellable> = []

    weak var delegate: AIChatHistoryViewModelDelegate?

    init(reader: ChatHistoryReading) {
        self.reader = reader

        // Materialize the chats publisher so failures become a sentinel value rather than
        // terminating the stream — keeps the combined publisher alive while we surface the
        // error via `loadFailed`.
        let chats: AnyPublisher<Result<[DuckAiChat], Error>, Never> = reader.chatsPublisher()
            .map(Result.success)
            .catch { Just(.failure($0)) }
            .eraseToAnyPublisher()

        // Debounce typed values so the in-memory filter runs once the user pauses, not on
        // every keystroke. `dropFirst().debounce(...).prepend("")` seeds `CombineLatest`
        // with the initial empty query synchronously — without it, the sheet would hide for
        // ~150ms whenever the chats publisher emits synchronously (warm cache re-opens).
        let queryStream = $query
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .prepend("")

        Publishers.CombineLatest(chats, queryStream)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result, query in
                self?.apply(result: result, query: query)
            }
            .store(in: &cancellables)
    }

    private func apply(result: Result<[DuckAiChat], Error>, query: String) {
        switch result {
        case .success(let allChats):
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            let filtered = trimmed.isEmpty
                ? allChats
                : allChats.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
            loadFailed = false
            pinned = filtered.filter(\.pinned)
            recent = filtered.filter { !$0.pinned }
        case .failure:
            loadFailed = true
            pinned = []
            recent = []
        }
        effectiveQuery = query
        hasLoaded = true
    }

    // MARK: - Table data source

    var numberOfSections: Int { Section.allCases.count }

    func title(forSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .pinned: return pinned.isEmpty ? nil : UserText.aiChatHistoryPinnedSectionTitle
        case .recent: return recent.isEmpty ? nil : UserText.aiChatHistoryRecentSectionTitle
        }
    }

    func numberOfRows(in section: Int) -> Int {
        chats(in: section)?.count ?? 0
    }

    func title(forRowAt indexPath: IndexPath) -> String? {
        chat(at: indexPath)?.title
    }

    func icon(forRowAt indexPath: IndexPath) -> UIImage? {
        guard let chat = chat(at: indexPath) else { return nil }
        return Self.icon(for: chat)
    }

    // MARK: - Intents

    func newChatTapped() {
        delegate?.viewModelDidRequestOpenNewChat()
    }

    func chatTapped(at indexPath: IndexPath) {
        guard let chatId = chat(at: indexPath)?.chatId else { return }
        delegate?.viewModelDidRequestOpenChat(chatId: chatId)
    }

    func updateQuery(_ newValue: String) {
        query = newValue
    }

    // MARK: - Helpers

    private func chats(in section: Int) -> [DuckAiChat]? {
        switch Section(rawValue: section) {
        case .pinned: return pinned
        case .recent: return recent
        case .none: return nil
        }
    }

    private func chat(at indexPath: IndexPath) -> DuckAiChat? {
        guard let pool = chats(in: indexPath.section),
              pool.indices.contains(indexPath.row) else { return nil }
        return pool[indexPath.row]
    }

    private static func icon(for chat: DuckAiChat) -> UIImage {
        let kind = AIChatSuggestion.kind(forModel: chat.model)
        switch (kind, chat.pinned) {
        case (.text, true): return DesignSystemImages.Glyphs.Size24.chatPinned
        case (.text, false): return DesignSystemImages.Glyphs.Size24.chat
        case (.voice, true): return DesignSystemImages.Glyphs.Size24.voicePinned
        case (.voice, false): return DesignSystemImages.Glyphs.Size24.voice
        case (.image, _): return DesignSystemImages.Glyphs.Size24.image
        }
    }
}

@MainActor
protocol AIChatHistoryViewModelDelegate: AnyObject {
    /// Dismiss the sheet and open Duck.ai on a fresh chat.
    func viewModelDidRequestOpenNewChat()

    /// Dismiss the sheet and open the chat identified by `chatId` in Duck.ai.
    func viewModelDidRequestOpenChat(chatId: String)
}
