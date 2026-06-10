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

public protocol ChatPinning {
    /// Reads the chat's stored JSON blob, flips its `pinned` boolean, and writes it back.
    func togglePin(chatId: String) throws
}

public enum ChatPinningError: Error, Equatable {
    case chatNotFound
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

    /// Flips the top-level `pinned` boolean while preserving every other field in the blob.
    /// Missing `pinned` key is treated as `false`.
    static func flipPinnedField(in data: Data) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw ChatPinningError.invalidChatBlob
        }
        let current = json["pinned"] as? Bool ?? false
        json["pinned"] = !current
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}
