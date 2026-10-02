//
//  HistoryCleaner.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import os.log
import PrivacyConfig
import UserScript
import WebKit

public protocol HistoryCleaning {
    @MainActor func cleanAIChatHistory() async -> Result<Void, Error>
    @MainActor func deleteAIChat(chatID: String) async -> Result<Void, Error>
    @MainActor func deleteAIChats(chatIDs: [String]) async -> Result<Void, Error>
    /// What happened during the most recent JS clear (retries, timings), or `nil` if none ran.
    @MainActor var lastClearingReport: AIChatClearingReport? { get }
}

public extension HistoryCleaning {
    @MainActor var lastClearingReport: AIChatClearingReport? { nil }
}

/// Splits `deleteAIChat`'s two phases so a caller can await the fast native delete without the slow JS clear.
public protocol PhasedAIChatHistoryCleaning: HistoryCleaning {
    /// Deletes the chat from native storage and writes the `locallyDeletedChatIds` tombstone;
    /// `nil` means native storage was unavailable (not a failure).
    @MainActor func deleteAIChatFromNativeStorage(chatID: String) -> Result<Void, Error>?

    /// Clears the JS layer (localStorage + IndexedDB) via a headless WebView; `nil` clears all chats.
    @MainActor func clearJSData(chatID: String?) async -> Result<Void, Error>
}

public final class HistoryCleaner: PhasedAIChatHistoryCleaning {
    private let nativeStorageHandler: DuckAiNativeStorageHandling?
    private let featureFlagProvider: AIChatFeatureFlagProviding?
    private let jsDataCleaner: AIChatJSDataCleaning
    private let indexedDBBlobCleaner: AIChatIndexedDBBlobCleaning

    @MainActor public var lastClearingReport: AIChatClearingReport? { jsDataCleaner.lastReport }

    /// Creates a history cleaner that clears Duck.ai data from both native storage and the JS layer.
    ///
    /// When `nativeStorageHandler` and `featureFlagProvider` are provided and the feature flag is enabled
    /// with migration done, chats and files are deleted from native storage. The JS clearing path
    /// (localStorage + IndexedDB) always runs, since JS-side data is kept in sync regardless of whether
    /// native storage is in use — without it, fire button cleanup leaves traces behind.
    ///
    /// A full clear additionally removes the IndexedDB blob files WebKit leaves on disk after the JS
    /// `clear()`; see `AIChatIndexedDBBlobCleaner`.
    public init(featureFlagger: FeatureFlagger,
                privacyConfig: PrivacyConfigurationManaging,
                websiteDataStore: WKWebsiteDataStore? = nil,
                nativeStorageHandler: DuckAiNativeStorageHandling? = nil,
                featureFlagProvider: AIChatFeatureFlagProviding? = nil,
                jsDataCleaner: AIChatJSDataCleaning? = nil,
                indexedDBBlobCleaner: AIChatIndexedDBBlobCleaning? = nil) {
        let websiteDataStore = websiteDataStore ?? .default()
        self.nativeStorageHandler = nativeStorageHandler
        self.featureFlagProvider = featureFlagProvider
        self.jsDataCleaner = jsDataCleaner ?? WebViewAIChatJSDataCleaner(
            featureFlagger: featureFlagger,
            privacyConfig: privacyConfig,
            websiteDataStore: websiteDataStore
        )
        self.indexedDBBlobCleaner = indexedDBBlobCleaner ?? AIChatIndexedDBBlobCleaner(websiteDataStore: websiteDataStore)
    }

    /// Clears all Duck.ai chat history (chats and files, not settings).
    @MainActor
    public func cleanAIChatHistory() async -> Result<Void, Error> {
        return await performClear(chatID: nil)
    }

    /// Deletes a single Duck.ai chat.
    @MainActor
    public func deleteAIChat(chatID: String) async -> Result<Void, Error> {
        return await performClear(chatID: chatID)
    }

    /// Deletes a specific set of Duck.ai chats in one pass: a single native file listing and one
    /// JS clearing session, rather than repeating both per chat.
    @MainActor
    public func deleteAIChats(chatIDs: [String]) async -> Result<Void, Error> {
        let nativeResult = clearLocalStorageIfAvailable(chatIDs: chatIDs)
        let jsResult = await jsDataCleaner.clearJSData(chatIDs: chatIDs)

        if case .failure = nativeResult {
            return nativeResult ?? jsResult
        }
        return jsResult
    }

    @MainActor
    private func performClear(chatID: String?) async -> Result<Void, Error> {
        let nativeResult = clearLocalStorageIfAvailable(chatID: chatID)
        let jsResult = await clearJSData(chatID: chatID)

        if case .failure = nativeResult {
            return nativeResult ?? jsResult
        }
        return jsResult
    }

    @MainActor
    public func deleteAIChatFromNativeStorage(chatID: String) -> Result<Void, Error>? {
        clearLocalStorageIfAvailable(chatID: chatID)
    }

    /// Clears the JS layer and, for a full clear (`nil`), the IndexedDB blob files the JS `clear()` leaves behind.
    /// Blob files are left alone after a single-chat delete because the remaining chats' images are still live.
    @MainActor
    public func clearJSData(chatID: String?) async -> Result<Void, Error> {
        let jsResult = await jsDataCleaner.clearJSData(chatID: chatID)
        guard chatID == nil, case .success = jsResult else {
            return jsResult
        }

        let blobResult = await indexedDBBlobCleaner.removeAllBlobFiles()
        if case .failure(let error) = blobResult {
            Logger.aiChat.error("HistoryCleaner: Failed to remove IndexedDB blob files: \(error.localizedDescription)")
        }
        return blobResult
    }

    private func clearLocalStorageIfAvailable(chatID: String?) -> Result<Void, Error>? {
        guard let featureFlagProvider, featureFlagProvider.isNativeDataStorageEnabled(),
              let nativeStorageHandler, (try? nativeStorageHandler.isMigrationDone()) == true else {
            return nil
        }

        do {
            if let chatID {
                Logger.aiChat.debug("HistoryCleaner: deleting chat \(chatID) from localStorage")
                let files = try nativeStorageHandler.listFiles().filter { $0.chatId == chatID }
                for file in files {
                    try nativeStorageHandler.deleteFile(uuid: file.uuid)
                }
                try nativeStorageHandler.deleteChat(chatId: chatID)
            } else {
                Logger.aiChat.debug("HistoryCleaner: deleting all chats from localStorage")
                try nativeStorageHandler.deleteAllFiles()
                try nativeStorageHandler.deleteAllChats()
            }
            return .success(())
        } catch {
            Logger.aiChat.error("HistoryCleaner: Failed to clear local storage: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private func clearLocalStorageIfAvailable(chatIDs: [String]) -> Result<Void, Error>? {
        guard let featureFlagProvider, featureFlagProvider.isNativeDataStorageEnabled(),
              let nativeStorageHandler, (try? nativeStorageHandler.isMigrationDone()) == true else {
            return nil
        }

        do {
            Logger.aiChat.debug("HistoryCleaner: deleting \(chatIDs.count) chats from localStorage")
            // List files once for the whole set instead of per chat.
            let idSet = Set(chatIDs)
            let files = try nativeStorageHandler.listFiles().filter { idSet.contains($0.chatId) }
            for file in files {
                try nativeStorageHandler.deleteFile(uuid: file.uuid)
            }
            for chatID in chatIDs {
                try nativeStorageHandler.deleteChat(chatId: chatID)
            }
            return .success(())
        } catch {
            Logger.aiChat.error("HistoryCleaner: Failed to clear local storage: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}
