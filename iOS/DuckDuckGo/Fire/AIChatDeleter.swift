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
import WebKit

protocol AIChatDeleting {
    @discardableResult
    @MainActor
    func deleteChat(chatID: String, isFireMode: Bool) async -> Result<Void, Error>

    @discardableResult
    @MainActor
    func deleteChats(chatIDs: [String], isFireMode: Bool) async -> Result<Void, Error>

    @discardableResult
    @MainActor
    func deleteAllChats(isFireMode: Bool) async -> Result<Void, Error>

    @MainActor
    func scheduleSync()
}

struct AIChatDeleter: AIChatDeleting {

    private let historyCleanerProvider: (WKWebsiteDataStore?, _ isFireMode: Bool) -> HistoryCleaning
    private let aiChatSyncCleaner: AIChatSyncCleaning
    private let idManager: DataStoreIDManaging

    init(historyCleanerProvider: @escaping (WKWebsiteDataStore?, _ isFireMode: Bool) -> HistoryCleaning,
         aiChatSyncCleaner: AIChatSyncCleaning,
         idManager: DataStoreIDManaging = DataStoreIDManager.shared) {
        self.historyCleanerProvider = historyCleanerProvider
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.idManager = idManager
    }

    @discardableResult
    @MainActor
    func deleteChat(chatID: String, isFireMode: Bool) async -> Result<Void, Error> {
        guard let cleaner = historyCleaner(isFireMode: isFireMode) else {
            return .success(())
        }

        let result = await cleaner.deleteAIChat(chatID: chatID)
        switch result {
        case .success:
            DailyPixel.fireDailyAndCount(pixel: .aiChatSingleDeleteSuccessful)
            if !isFireMode {
                await aiChatSyncCleaner.recordChatDeletion(chatID: chatID)
            }
        case .failure(let error):
            DailyPixel.fireDailyAndCount(pixel: .aiChatSingleDeleteFailed)
            Logger.aiChat.debug("Failed to delete AI Chat: \(error.localizedDescription)")
            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
        return result
    }

    @discardableResult
    @MainActor
    func deleteChats(chatIDs: [String], isFireMode: Bool) async -> Result<Void, Error> {
        guard let cleaner = historyCleaner(isFireMode: isFireMode) else {
            return .success(())
        }

        let result = await cleaner.deleteAIChats(chatIDs: chatIDs)
        switch result {
        case .success:
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteSuccessful)
            if !isFireMode {
                for chatID in chatIDs {
                    await aiChatSyncCleaner.recordChatDeletion(chatID: chatID)
                }
            }
        case .failure(let error):
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteFailed, error: error)
            Logger.aiChat.debug("Failed to delete AI Chats: \(error.localizedDescription)")
            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
        return result
    }

    @discardableResult
    @MainActor
    func deleteAllChats(isFireMode: Bool) async -> Result<Void, Error> {
        guard let cleaner = historyCleaner(isFireMode: isFireMode) else {
            return .success(())
        }

        let result = await cleaner.cleanAIChatHistory()
        switch result {
        case .success:
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteSuccessful)
            if !isFireMode {
                await aiChatSyncCleaner.recordLocalClear(date: Date())
            }
        case .failure(let error):
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteFailed, error: error)
            Logger.aiChat.debug("Failed to clear AI Chat history: \(error.localizedDescription)")
            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
        return result
    }

    @MainActor
    func scheduleSync() {
        aiChatSyncCleaner.scheduleSync()
    }

    @MainActor
    private func historyCleaner(isFireMode: Bool) -> HistoryCleaning? {
        if isFireMode {
            guard #available(iOS 17, *) else { return nil }
            let dataStore = WKWebsiteDataStore(forIdentifier: idManager.currentFireModeID)
            return historyCleanerProvider(dataStore, isFireMode)
        }
        return historyCleanerProvider(nil, isFireMode)
    }
}
