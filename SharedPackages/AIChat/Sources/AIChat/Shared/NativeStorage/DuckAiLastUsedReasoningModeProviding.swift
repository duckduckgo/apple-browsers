//
//  DuckAiLastUsedReasoningModeProviding.swift
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

import DuckAiDataStore
import Foundation

/// Reads the last-used `reasoningMode` raw string for a stored Duck.ai chat.
public protocol DuckAiLastUsedReasoningModeProviding {
    /// Returns the raw `reasoningMode` string persisted with `chatId`, or `nil` when:
    /// - the chat is not in storage,
    /// - the payload has no `reasoningMode` field, or
    /// - the stored payload cannot be parsed.
    func reasoningMode(forChatId chatId: String) -> String?
}

public struct DuckAiLastUsedReasoningModeProvider: DuckAiLastUsedReasoningModeProviding {
    private let storage: DuckAiNativeStorageHandling
    private let pixelFiring: DuckAiNativeStoragePixelFiring

    public init(
        storage: DuckAiNativeStorageHandling,
        pixelFiring: DuckAiNativeStoragePixelFiring = NullDuckAiNativeStoragePixelFiring()
    ) {
        self.storage = storage
        self.pixelFiring = pixelFiring
    }

    public func reasoningMode(forChatId chatId: String) -> String? {
        let record: DuckAiChatRecord?
        do {
            record = try storage.getChat(chatId: chatId)
        } catch {
            pixelFiring.fire(.chatGetError(error))
            return nil
        }
        guard let record else { return nil }
        do {
            return try DuckAiChat.decode(from: record.data).chat.reasoningMode
        } catch {
            pixelFiring.fire(.lastUsedReasoningModeParseError(error))
            return nil
        }
    }
}
