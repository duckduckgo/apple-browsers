//
//  DuckAiLastUsedModelProviding.swift
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

/// Reads the last-used model ID for a stored Duck.ai chat.
public protocol DuckAiLastUsedModelProviding {
    /// Returns the last-used model ID for `chatId`, or `nil` when:
    /// - the chat is not in storage,
    /// - the chat has no assistant reply yet (no `model` field), or
    /// - the stored payload cannot be parsed (a parse-error pixel is fired in that case).
    func lastUsedModel(forChatId chatId: String) -> String?
}

public struct DuckAiLastUsedModelProvider: DuckAiLastUsedModelProviding {

    private let storage: DuckAiNativeStorageHandling
    private let pixelFiring: DuckAiNativeStoragePixelFiring

    public init(
        storage: DuckAiNativeStorageHandling,
        pixelFiring: DuckAiNativeStoragePixelFiring = NullDuckAiNativeStoragePixelFiring()
    ) {
        self.storage = storage
        self.pixelFiring = pixelFiring
    }

    public func lastUsedModel(forChatId chatId: String) -> String? {
        let record: DuckAiChatRecord?
        do {
            record = try storage.getChat(chatId: chatId)
        } catch {
            pixelFiring.fire(.chatGetError(error))
            return nil
        }
        guard let record else { return nil }
        do {
            let model = try DuckAiChat.decode(from: record.data).chat.model
            return model.isEmpty ? nil : model
        } catch {
            pixelFiring.fire(.lastUsedModelParseError(error))
            return nil
        }
    }
}
