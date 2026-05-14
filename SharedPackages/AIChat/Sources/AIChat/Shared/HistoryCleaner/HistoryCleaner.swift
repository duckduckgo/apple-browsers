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
}

public final class HistoryCleaner: HistoryCleaning {
    private let nativeStorageHandler: DuckAiNativeStorageHandling?
    private let featureFlagProvider: AIChatFeatureFlagProviding?
    private let jsDataCleaner: AIChatJSDataCleaning

    /// Creates a history cleaner that clears Duck.ai data from both native storage and the JS layer.
    ///
    /// When `nativeStorageHandler` and `featureFlagProvider` are provided and the feature flag is enabled
    /// with migration done, chats and files are deleted from native storage. The JS clearing path
    /// (localStorage + IndexedDB) always runs, since JS-side data is kept in sync regardless of whether
    /// native storage is in use — without it, fire button cleanup leaves traces behind.
    public init(featureFlagger: FeatureFlagger,
                privacyConfig: PrivacyConfigurationManaging,
                websiteDataStore: WKWebsiteDataStore? = nil,
                nativeStorageHandler: DuckAiNativeStorageHandling? = nil,
                featureFlagProvider: AIChatFeatureFlagProviding? = nil,
                jsDataCleaner: AIChatJSDataCleaning? = nil) {
        self.nativeStorageHandler = nativeStorageHandler
        self.featureFlagProvider = featureFlagProvider
        self.jsDataCleaner = jsDataCleaner ?? WebViewAIChatJSDataCleaner(
            featureFlagger: featureFlagger,
            privacyConfig: privacyConfig,
            websiteDataStore: websiteDataStore ?? .default()
        )
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

    @MainActor
    private func performClear(chatID: String?) async -> Result<Void, Error> {
        let nativeResult = clearLocalStorageIfAvailable(chatID: chatID)
        let jsResult = await jsDataCleaner.clearJSData(chatID: chatID)

        if case .failure = nativeResult {
            return nativeResult ?? jsResult
        }
        return jsResult
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
}
