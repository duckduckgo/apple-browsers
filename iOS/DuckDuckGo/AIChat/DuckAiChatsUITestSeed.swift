//
//  DuckAiChatsUITestSeed.swift
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

#if DEBUG
import AIChat
import Core
import Foundation

enum DuckAiChatsUITestSeed {
    private struct Counts: Decodable {
        let normal: Int
        let fire: Int
    }

    private enum SeedError: Error {
        case invalidCounts
        case storageUnavailable
        case readbackFailed
    }

    private static var requestedSeedIndex: Int? {
        guard LaunchOptionsHandler().isUITesting else { return nil }
        return ProcessInfo.processInfo.arguments.firstIndex(of: "-duckAiChatsTestSeed")
    }

    static var isRequested: Bool { requestedSeedIndex != nil }

    /// The chat count the last Fire sheet preparation read, which UI tests read from the sheet; `nil` unless seeding.
    @MainActor static var lastReadChatCount: Int?

    static func applyIfRequested(normal: DuckAiNativeStorageHandling?, fire: DuckAiNativeStorageHandling?) throws {
        guard let index = requestedSeedIndex else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.indices.contains(index + 1) else { throw SeedError.invalidCounts }
        let counts = try JSONDecoder().decode(Counts.self, from: Data(arguments[index + 1].utf8))
        guard (0...3).contains(counts.normal), (0...3).contains(counts.fire) else { throw SeedError.invalidCounts }
        guard let normal, let fire else { throw SeedError.storageUnavailable }
        try seed(normal, count: counts.normal, mode: "normal")
        try seed(fire, count: counts.fire, mode: "fire")
    }

    private static func seed(_ storage: DuckAiNativeStorageHandling, count: Int, mode: String) throws {
        try storage.deleteAllChats()
        try storage.deleteAllFiles()
        try storage.deleteAllEntries()
        guard let lastEdit = AIChatSuggestion.formatISO8601Date(Date()) else { throw SeedError.readbackFailed }
        var expectedIDs = Set<String>()
        for index in 0..<count {
            let chatID = "uitest-\(mode)-\(index)"
            let json: [String: Any] = [
                "chatId": chatID, "title": "Seed \(mode) chat \(index + 1)",
                "model": "gpt-4o-mini", "lastEdit": lastEdit,
                "pinned": index == 0, "messages": [["role": "user", "content": "Seeded conversation"]]
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            try storage.putChat(chatId: chatID, data: data)
            expectedIDs.insert(chatID)
        }
        try storage.markMigrationDone(key: DuckAiMigrationKey.chats)
        try storage.markMigrationDone(key: DuckAiMigrationKey.files)
        let actualIDs = try Set(storage.getAllChats().map { try DuckAiChat.decode(from: $0.data).chat.chatId })
        guard actualIDs == expectedIDs, try storage.isMigrationDone() else { throw SeedError.readbackFailed }
    }
}

#endif
