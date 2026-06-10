//
//  ChatPinning.swift
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

/// Toggles the `pinned` flag on a chat's stored JSON blob. Mirrors Android's per-row
/// pin/unpin (PR #8604) which writes directly to native storage rather than round-tripping
/// through the FE — the chat-history sheet has no live WebView to bridge through.
public protocol ChatPinning {
    /// Read the chat's JSON blob, flip the top-level `pinned` boolean, write it back.
    /// Caller doesn't need to know the current state.
    func togglePin(chatId: String) throws
}

public enum ChatPinningError: Error, Equatable {
    case chatNotFound
    /// The stored blob doesn't parse as a JSON object — can't safely flip a flag inside it.
    case invalidChatBlob
}

public struct ChatPinner: ChatPinning {

    private let storageHandler: DuckAiNativeStorageHandling

    public init(storageHandler: DuckAiNativeStorageHandling) {
        self.storageHandler = storageHandler
    }

    public func togglePin(chatId: String) throws {
        guard let record = try storageHandler.getChat(chatId: chatId) else {
            throw ChatPinningError.chatNotFound
        }
        let mutated = try Self.flipPinnedField(in: record.data)
        try storageHandler.putChat(chatId: chatId, data: mutated)
    }

    /// Flips the top-level `pinned` boolean in the chat blob, preserving every other field
    /// (messages, parts, reasoningMode, and any future FE-added keys we don't model in
    /// `DuckAiChat.ChatBlob`). Uses `JSONSerialization` rather than decode + re-encode so
    /// nothing is silently dropped on the round-trip. A missing `pinned` key is treated as
    /// `false` and flipped to `true`.
    static func flipPinnedField(in data: Data) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw ChatPinningError.invalidChatBlob
        }
        let current = json["pinned"] as? Bool ?? false
        json["pinned"] = !current
        // `.sortedKeys` keeps the output stable for tests and avoids reshuffling existing
        // FE-authored blobs (which themselves emit sorted keys).
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}
