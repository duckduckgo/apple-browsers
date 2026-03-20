//
//  AIChatDeleter.swift
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

import AIChat
import Core
import UserScript

protocol AIChatDeleting {
    @discardableResult
    func deleteChat(chatID: String) async -> Result<Void, Error>
}

struct AIChatDeleter: AIChatDeleting {

    private let historyCleanerProvider: () -> HistoryCleaning
    private let aiChatSyncCleaner: AIChatSyncCleaning

    init(historyCleanerProvider: @escaping () -> HistoryCleaning,
         aiChatSyncCleaner: AIChatSyncCleaning) {
        self.historyCleanerProvider = historyCleanerProvider
        self.aiChatSyncCleaner = aiChatSyncCleaner
    }

    @discardableResult
    func deleteChat(chatID: String) async -> Result<Void, Error> {
        let cleaner = historyCleanerProvider()
        let result = await cleaner.deleteAIChat(chatID: chatID)
        switch result {
        case .success:
            DailyPixel.fireDailyAndCount(pixel: .aiChatSingleDeleteSuccessful)
            await aiChatSyncCleaner.recordChatDeletion(chatID: chatID)
        case .failure(let error):
            DailyPixel.fireDailyAndCount(pixel: .aiChatSingleDeleteFailed)
            Logger.aiChat.debug("Failed to delete AI Chat: \(error.localizedDescription)")
            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
        return result
    }
}
