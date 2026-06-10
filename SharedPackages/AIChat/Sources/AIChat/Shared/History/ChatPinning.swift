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
    /// Writes the supplied `pinned` value into the chat's stored JSON blob.
    func setPinned(chatId: String, pinned: Bool) throws
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

    public func setPinned(chatId: String, pinned: Bool) throws {
        guard let record = try storageHandler.getChat(chatId: chatId) else {
            throw ChatPinningError.chatNotFound
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: record.data, options: []),
              var json = parsed as? [String: Any] else {
            throw ChatPinningError.invalidChatBlob
        }
        json["pinned"] = pinned
        let mutated = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try storageHandler.putChat(chatId: chatId, data: mutated)
    }
}
