//
//  ChatHistoryReader.swift
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
import os.log

public protocol ChatHistoryReading {
    @MainActor
    func fetchAllChats() async -> Result<[DuckAiChat], Error>
}

@MainActor
public final class ChatHistoryReader: ChatHistoryReading {

    private let storageHandler: DuckAiNativeStorageHandling

    public init(storageHandler: DuckAiNativeStorageHandling) {
        self.storageHandler = storageHandler
    }

    public func fetchAllChats() async -> Result<[DuckAiChat], Error> {
        do {
            let records = try storageHandler.getAllChats()
            let chats = records.compactMap { try? DuckAiChat.decode(from: $0.data).chat }

            let sorted = chats.sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                return lhs.lastEdit > rhs.lastEdit
            }
            return .success(sorted)
        } catch {
            Logger.aiChat.error("ChatHistoryReader: Failed to fetch chats: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}
