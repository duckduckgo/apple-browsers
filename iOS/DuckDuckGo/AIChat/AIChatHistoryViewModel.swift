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

    @Published private(set) var query: String = ""

    /// The query that produced the current `pinned`/`recent`. Lags `query` by the debounce
    /// interval — read this (not `query`) for UI decisions that must stay consistent with
    /// the rows on screen, e.g. the illustrated empty-state check.
    @Published private(set) var effectiveQuery: String = ""

    var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }

    private let reader: ChatHistoryReading
    private var cancellables: Set<AnyCancellable> = []

    weak var delegate: AIChatHistoryViewModelDelegate?

    init(reader: ChatHistoryReading) {
        self.reader = reader

        // Failures become a sentinel `.failure` so the combined publisher stays alive and
        // we can surface the error via `loadFailed` instead of terminating.
        let chats: AnyPublisher<Result<[DuckAiChat], Error>, Never> = reader.chatsPublisher()
            .map(Result.success)
            .catch { Just(.failure($0)) }
            .eraseToAnyPublisher()

        // `dropFirst().debounce(...).prepend("")` seeds the initial empty query into
        // `CombineLatest` synchronously while still debouncing user typing — without the
        // prepend, the sheet hides for ~150ms when chats emit synchronously on warm re-open.
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
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        switch result {
        case .success(let allChats):
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
        // Store the trimmed value so whitespace-only queries don't read as "user is
        // searching" — they aren't (the filter treated the query as empty).
        effectiveQuery = trimmed
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

    // MARK: - Row identity

    /// Resolve the stable chat id at gesture-start, then pass it to the intent. Don't
    /// re-resolve from the index path later — `pinned`/`recent` can shift between gesture
    /// start and commit, so the index path may point at a different chat.
    func chatId(forRowAt indexPath: IndexPath) -> String? {
        chat(at: indexPath)?.chatId
    }

    // MARK: - Intents

    func newChatTapped() {
        delegate?.viewModelDidRequestOpenNewChat()
    }

    func openChat(chatId: String) {
        delegate?.viewModelDidRequestOpenChat(chatId: chatId)
    }

    func deleteChat(chatId: String) {
        delegate?.viewModelDidRequestDeleteChat(chatId: chatId)
    }

    func downloadChat(chatId: String) {
        delegate?.viewModelDidRequestDownloadChat(chatId: chatId)
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
        let image: UIImage
        // Switch on `chat.chatType` rather than `AIChatSuggestion.kind(forModel:)` so chats
        // that produced images via a tool call (without the image-mode model id) still get
        // the image glyph — same precedence the exporter uses.
        switch (chat.chatType, chat.pinned) {
        case (.discussion, true): image = DesignSystemImages.Glyphs.Size24.chatPinned
        case (.discussion, false): image = DesignSystemImages.Glyphs.Size24.chat
        case (.voice, true): image = DesignSystemImages.Glyphs.Size24.voicePinned
        case (.voice, false): image = DesignSystemImages.Glyphs.Size24.voice
        case (.imageGeneration, _): image = DesignSystemImages.Glyphs.Size24.image
        }
        // The chat-family glyph assets aren't marked `template-rendering-intent` in their
        // Contents.json, so without forcing template mode they render in their own
        // light-mode-tuned colors and become unreadable in dark mode. Force template so
        // the cell's `.icons` tint (which adapts to appearance) takes effect.
        return image.withRenderingMode(.alwaysTemplate)
    }
}

@MainActor
protocol AIChatHistoryViewModelDelegate: AnyObject {
    /// Dismiss the sheet and open Duck.ai on a fresh chat.
    func viewModelDidRequestOpenNewChat()

    /// Dismiss the sheet and open `chatId` in Duck.ai.
    func viewModelDidRequestOpenChat(chatId: String)

    /// Delete `chatId`. The sheet stays open; the observation publisher refreshes the list
    /// once the deletion lands.
    func viewModelDidRequestDeleteChat(chatId: String)

    /// Export `chatId` to the Downloads directory and present the "Download complete" toast.
    /// The sheet stays open.
    func viewModelDidRequestDownloadChat(chatId: String)
}
