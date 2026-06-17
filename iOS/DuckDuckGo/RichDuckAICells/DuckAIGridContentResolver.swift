//
//  DuckAIGridContentResolver.swift
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

import UIKit
import AIChat
import PrivacyConfig
import os.log

/// Resolves a `DuckAIGridItem` for a tab. Returns `nil` when the tab should fall
/// back to the existing screenshot path (flag off, not a Duck.ai chat tab, native
/// data unavailable, decode failure, …).
@MainActor
protocol DuckAIGridItemProviding: AnyObject {
    func gridItem(for tab: Tab) -> DuckAIGridItem?
}

/// Loads thumbnail images for `DuckAIGridItem.image` cards.
@MainActor
protocol DuckAIThumbnailLoading: AnyObject {
    func loadImage(fileRef: String) async -> UIImage?
}

/// Composition of both grid-content capabilities.
@MainActor
protocol DuckAIGridContentProviding: DuckAIGridItemProviding, DuckAIThumbnailLoading {}

/// Resolves the content shown for a Duck.ai chat tab in the tab switcher grid,
/// reading from native chat storage.
@MainActor
final class DuckAIGridContentResolver: DuckAIGridContentProviding {

    private let featureFlagger: FeatureFlagger
    private let storageHandler: DuckAiNativeStorageHandling?
    private let aiChatFeatureFlagProvider: AIChatFeatureFlagProviding

    /// - Parameters:
    ///   - featureFlagger: Used to read `FeatureFlag.aiChatTabSwitcherRichCard`, and
    ///     internally as the source for `AIChatFeatureFlagProvider` (which gates the
    ///     `aiChatNativeDataAccess` flag).
    ///   - storageHandler: The native storage handler, or `nil` when native storage is disabled.
    init(featureFlagger: FeatureFlagger,
         storageHandler: DuckAiNativeStorageHandling?) {
        self.featureFlagger = featureFlagger
        self.storageHandler = storageHandler
        self.aiChatFeatureFlagProvider = AIChatFeatureFlagProvider(featureFlagger: featureFlagger)
    }

    /// `DuckAIGridItemProviding` entry point. Applies the outer feature-flag gate
    /// and the no-chat-ID gate, then defers to `gridItem(forChatID:)`. Returns
    /// `nil` when any gate fails — the caller falls back to the screenshot path.
    func gridItem(for tab: Tab) -> DuckAIGridItem? {
        guard featureFlagger.isFeatureOn(.aiChatTabSwitcherRichCard) else { return nil }
        guard let chatID = tab.link?.url.duckAIChatID else { return nil }
        return gridItem(forChatID: chatID)
    }

    /// Returns the grid item for the given chat id, or `nil` when native data is
    /// unavailable, incomplete, or the chat has no meaningful content. Caller is
    /// responsible for the outer feature-flag gate; see `gridItem(for:)`.
    func gridItem(forChatID chatID: String) -> DuckAIGridItem? {
        guard let storageHandler, aiChatFeatureFlagProvider.isNativeDataAccessEnabled() else {
            return nil
        }

        do {
            guard try storageHandler.isMigrationDone(),
                  let record = try storageHandler.getChat(chatId: chatID) else {
                return nil
            }
            let decoded = try DuckAiChat.decode(from: record.data)
            return DuckAIGridItem.from(chat: decoded.chat, lastMessageContent: decoded.lastMessageContent)
        } catch {
            Logger.aiChat.error("DuckAIGridContentResolver: failed to read chat: \(error.localizedDescription)")
            return nil
        }
    }

    func loadImage(fileRef: String) async -> UIImage? {
        guard let storageHandler, aiChatFeatureFlagProvider.isNativeDataAccessEnabled() else {
            return nil
        }
        return await Task.detached {
            do {
                guard let file = try storageHandler.getFile(uuid: fileRef) else { return nil }
                return Self.decodeImage(from: file.data)
            } catch {
                Logger.aiChat.error("DuckAIGridContentResolver: failed to read file: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    /// Native files may be raw image bytes OR a `{data: <base64>, mimeType: ...}` JSON
    /// wrapper (debug-server dashboard is the reference). Try wrapper first, then raw.
    nonisolated private static func decodeImage(from data: Data) -> UIImage? {
        if let wrapper = try? JSONDecoder().decode(FileWrapper.self, from: data),
           let bytes = Data(base64Encoded: wrapper.data) {
            return UIImage(data: bytes)
        }
        return UIImage(data: data)
    }

    private struct FileWrapper: Decodable {
        let data: String
        let mimeType: String?
    }
}
