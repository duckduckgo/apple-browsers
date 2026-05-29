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
import UIKit
import AIChat
import DesignResourcesKitIcons

@MainActor
final class AIChatHistoryViewModel: ObservableObject {

    enum Section: Int, CaseIterable {
        case pinned
        case recent
    }

    @Published private(set) var chats: [DuckAiChat] = []
    @Published private(set) var isLoading: Bool = false

    var isEmpty: Bool { chats.isEmpty }

    private let reader: ChatHistoryReading

    weak var delegate: AIChatHistoryViewModelDelegate?

    init(reader: ChatHistoryReading) {
        self.reader = reader
    }

    // MARK: - Loading

    func loadChats() async {
        isLoading = true
        defer { isLoading = false }

        let result = await reader.fetchAllChats()
        switch result {
        case .success(let chats): self.chats = chats
        case .failure: self.chats = []
        }
    }

    // MARK: - Table data source

    var numberOfSections: Int { Section.allCases.count }

    func title(forSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .pinned: return chats(in: .pinned).isEmpty ? nil : "PINNED"
        case .recent: return chats(in: .recent).isEmpty ? nil : "RECENT"
        }
    }

    func numberOfRows(in section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        return chats(in: section).count
    }

    func title(forRowAt indexPath: IndexPath) -> String? {
        chat(at: indexPath)?.title
    }

    func icon(forRowAt indexPath: IndexPath) -> UIImage? {
        guard let chat = chat(at: indexPath) else { return nil }
        return Self.icon(for: chat)
    }

    // MARK: - Intents

    func openDuckAiTapped() {
        delegate?.viewModelDidRequestOpenDuckAi()
    }

    // MARK: - Helpers

    private func chats(in section: Section) -> [DuckAiChat] {
        switch section {
        case .pinned: return chats.filter(\.pinned)
        case .recent: return chats.filter { !$0.pinned }
        }
    }

    private func chat(at indexPath: IndexPath) -> DuckAiChat? {
        guard let section = Section(rawValue: indexPath.section) else { return nil }
        let pool = chats(in: section)
        guard pool.indices.contains(indexPath.row) else { return nil }
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
    func viewModelDidRequestOpenDuckAi()
}
