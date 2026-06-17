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
import Core
import DesignResourcesKitIcons
import os.log

@MainActor
final class AIChatHistoryViewModel: ObservableObject {

    enum Section: Int, CaseIterable {
        case pinned
        case recent
    }

    @Published private(set) var pinned: [DuckAiChat] = []
    @Published private(set) var recent: [DuckAiChat] = []
    @Published private(set) var hasLoaded: Bool = false

    /// Distinct from `isEmpty` so the UI can show an error state rather than "no chats yet".
    @Published private(set) var loadFailed: Bool = false

    @Published private(set) var query: String = ""

    /// Lags `query` by the debounce interval. Read this (not `query`) for UI checks that
    /// must stay consistent with the rows on screen.
    @Published private(set) var effectiveQuery: String = ""

    var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }

    /// Count of ALL persistent chats, independent of the active search filter. `burnAllChats`
    /// clears every chat, so the confirmation must reflect the full scope — not just the matches
    /// currently shown in `pinned`/`recent`.
    private(set) var totalChatCount: Int = 0

    private let reader: ChatHistoryReading
    private let fireExecutor: FireExecuting?
    private let downloader: ChatHistoryDownloading?
    private let pinner: ChatPinning?
    private let mutationQueue: DispatchQueue
    private var cancellables: Set<AnyCancellable> = []

    weak var delegate: AIChatHistoryViewModelDelegate?

    init(
        reader: ChatHistoryReading,
        fireExecutor: FireExecuting? = nil,
        downloader: ChatHistoryDownloading? = nil,
        pinner: ChatPinning? = nil,
        mutationQueue: DispatchQueue = DispatchQueue(label: "chat-history.mutation", qos: .userInitiated)
    ) {
        self.reader = reader
        self.fireExecutor = fireExecutor
        self.downloader = downloader
        self.pinner = pinner
        self.mutationQueue = mutationQueue

        // `.failure` as a sentinel keeps the combined publisher alive for `loadFailed`.
        let chats: AnyPublisher<Result<[DuckAiChat], Error>, Never> = reader.chatsPublisher()
            .map(Result.success)
            .catch { Just(.failure($0)) }
            .eraseToAnyPublisher()

        // `prepend("")` seeds the initial empty query so chats can render immediately on
        // warm re-open; `dropFirst().debounce(...)` then handles typed values.
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
            totalChatCount = allChats.count
            pinned = filtered.filter(\.pinned)
            recent = filtered.filter { !$0.pinned }
        case .failure:
            loadFailed = true
            totalChatCount = 0
            pinned = []
            recent = []
        }
        // Trimmed so whitespace-only doesn't read as "user is searching" downstream.
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
        // Sheet only surfaces persistent chats, so never fire-mode.
        guard let fireExecutor else { return }
        Task { @MainActor in
            let result = await fireExecutor.burnChat(chatID: chatId, isFireMode: false)
            guard case .success = result else { return }
            // Flush the deletion to sync now so the FE doesn't re-pull the chat.
            fireExecutor.scheduleSync()
        }
    }

    func burnAllChats() async {
        guard let fireExecutor else { return }
        let result = await fireExecutor.burnAllChats(isFireMode: false)
        guard case .success = result else { return }
        // Flush the clear to sync now so the FE doesn't re-pull the chats.
        fireExecutor.scheduleSync()
    }

    func downloadChat(chatId: String) {
        // Image-gen exports do enough I/O to freeze the sheet — dispatch off-main.
        guard let downloader else { return }
        mutationQueue.async { [weak self] in
            do {
                let url = try downloader.downloadChat(chatId: chatId)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.viewModelDidExportChat(filename: url.lastPathComponent)
                }
            } catch {
                Logger.aiChat.debug("Chat export failed: \(error.localizedDescription)")
                // Failure-state toast pairs with the pixels-pass follow-up (task #28).
            }
        }
    }

    func isPinned(chatId: String) -> Bool {
        pinned.contains(where: { $0.chatId == chatId })
    }

    /// Optimistically moves the chat between sections and dispatches the storage write.
    /// Returns the source + destination index paths for the table animation, or `nil` when
    /// no move is possible (chat absent or pinner not wired).
    @discardableResult
    func togglePin(chatId: String) -> (source: IndexPath, destination: IndexPath)? {
        guard let pinner, let move = applyOptimisticPinToggle(chatId: chatId) else { return nil }
        let newPinned = move.destination.section == Section.pinned.rawValue
        mutationQueue.async {
            do {
                try pinner.setPinned(chatId: chatId, pinned: newPinned)
            } catch {
                Logger.aiChat.debug("Pin toggle failed: \(error.localizedDescription)")
            }
        }
        return move
    }

    private func applyOptimisticPinToggle(chatId: String) -> (source: IndexPath, destination: IndexPath)? {
        if let row = pinned.firstIndex(where: { $0.chatId == chatId }) {
            let chat = pinned.remove(at: row)
            let toggled = chat.withPinned(false)
            let insertIndex = recent.firstIndex(where: { $0.lastEdit < toggled.lastEdit }) ?? recent.count
            recent.insert(toggled, at: insertIndex)
            return (IndexPath(row: row, section: Section.pinned.rawValue),
                    IndexPath(row: insertIndex, section: Section.recent.rawValue))
        }
        if let row = recent.firstIndex(where: { $0.chatId == chatId }) {
            let chat = recent.remove(at: row)
            let toggled = chat.withPinned(true)
            let insertIndex = pinned.firstIndex(where: { $0.lastEdit < toggled.lastEdit }) ?? pinned.count
            pinned.insert(toggled, at: insertIndex)
            return (IndexPath(row: row, section: Section.recent.rawValue),
                    IndexPath(row: insertIndex, section: Section.pinned.rawValue))
        }
        return nil
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

    /// A chat export finished writing to disk. Present the "Download complete" toast for
    /// `filename` with a "Show" action that dismisses the sheet and opens the in-app
    /// Downloads list.
    func viewModelDidExportChat(filename: String)
}
