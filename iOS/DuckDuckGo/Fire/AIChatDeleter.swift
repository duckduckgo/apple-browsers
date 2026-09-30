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
import PixelKit

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

    /// What happened during the most recent single-chat JS clear (retries, timings), or `nil` if none ran.
    @MainActor
    var lastClearingReport: AIChatClearingReport? { get }
}

extension AIChatDeleting {
    @MainActor
    var lastClearingReport: AIChatClearingReport? { nil }
}

final class AIChatDeleter: AIChatDeleting {

    private let historyCleanerProvider: (WKWebsiteDataStore?, _ isFireMode: Bool) -> HistoryCleaning
    private let aiChatSyncCleaner: AIChatSyncCleaning
    private let idManager: DataStoreIDManaging
    @MainActor private(set) var lastClearingReport: AIChatClearingReport?

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
        lastClearingReport = cleaner.lastClearingReport
        switch result {
        case .success:
            PixelKit.fire(Pixel.Event.aiChatSingleDeleteSuccessful, frequency: .dailyAndCount, options: .parameters(deletePixelParameters(of: cleaner)))
            if !isFireMode {
                await aiChatSyncCleaner.recordChatDeletion(chatID: chatID)
            }
        case .failure(let error):
            PixelKit.fire(Pixel.Event.aiChatSingleDeleteFailed.withError(error), frequency: .dailyAndCount, options: .parameters(deletePixelParameters(of: cleaner)))
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
            PixelKit.fire(Pixel.Event.aiChatHistoryDeleteSuccessful, frequency: .dailyAndCount, options: .parameters(deletePixelParameters(of: cleaner, source: .multiSelect)))
            if !isFireMode {
                for chatID in chatIDs {
                    await aiChatSyncCleaner.recordChatDeletion(chatID: chatID)
                }
            }
        case .failure(let error):
            PixelKit.fire(Pixel.Event.aiChatHistoryDeleteFailed.withError(error), frequency: .dailyAndCount, options: .parameters(deletePixelParameters(of: cleaner, source: .multiSelect)))
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
            PixelKit.fire(Pixel.Event.aiChatHistoryDeleteSuccessful, frequency: .dailyAndCount, options: .parameters(deletePixelParameters(of: cleaner, source: .deleteAll)))
            if !isFireMode {
                await aiChatSyncCleaner.recordLocalClear(date: Date())
            }
        case .failure(let error):
            PixelKit.fire(Pixel.Event.aiChatHistoryDeleteFailed.withError(error), frequency: .dailyAndCount, options: .parameters(deletePixelParameters(of: cleaner, source: .deleteAll)))
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

/// Where a Duck.ai history delete came from, so the delete pixels can tell the paths apart.
enum AIChatDeletePixelSource: String {
    case fireButton = "fire_button"
    case autoClear = "auto_clear"
    case multiSelect = "multi_select"
    case deleteAll = "delete_all"

    init(trigger: FireRequest.Trigger) {
        switch trigger {
        case .manualFire: self = .fireButton
        case .autoClearOnLaunch, .autoClearOnForeground, .fireModeAutoClear: self = .autoClear
        }
    }
}

/// The delete pixels' parameters: where the delete came from, whether it was retried, and why the first attempt failed.
@MainActor
func deletePixelParameters(of cleaner: HistoryCleaning, source: AIChatDeletePixelSource? = nil) -> [String: String] {
    var parameters: [String: String] = [:]
    parameters["source"] = source?.rawValue
    if let report = cleaner.lastClearingReport {
        parameters["retried"] = String(report.wasRetried)
        if let firstAttemptError = report.firstAttemptError {
            parameters["first_attempt_error_code"] = String((firstAttemptError as NSError).code)
        }
    }
    return parameters
}
