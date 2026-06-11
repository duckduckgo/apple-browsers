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
protocol DuckAIGridItemProviding {
    func gridItem(for tab: Tab) -> DuckAIGridItem?
}

/// Resolves the content shown for a Duck.ai chat tab in the tab switcher grid,
/// reading from native chat storage.
@MainActor
final class DuckAIGridContentResolver: DuckAIGridItemProviding {

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
            guard try storageHandler.isMigrationDone(key: DuckAiMigrationKey.chats),
                  let record = try storageHandler.getChat(chatId: chatID) else {
                return nil
            }
            let decoded = try DuckAiChat.decode(from: record.data)
            return DuckAIGridItem.from(chat: decoded.chat)
        } catch {
            Logger.aiChat.error("DuckAIGridContentResolver: failed to read chat: \(error.localizedDescription)")
            return nil
        }
    }

    /// Loads an image referenced by a chat from the native file store. Returns `nil`
    /// when the file is missing or is not a decodable image.
    func loadImage(fileRef: String) -> UIImage? {
        guard let storageHandler,
              let file = try? storageHandler.getFile(uuid: fileRef) else {
            return nil
        }
        return UIImage(data: file.data)
    }
}

// TODO: - Remove this when proper resolver is wired up
#if DEBUG
/// Debug-only `DuckAIGridItemProviding` that returns a deterministic rotating cycle
/// of `DuckAIGridItem` values keyed by the tab's stable `uid`. Used to scaffold and
/// visually iterate on the rich-card cell UI before the real
/// `DuckAIGridContentResolver` is wired into the tab switcher. Never ships in release
/// builds — the entire type is gated behind `#if DEBUG`.
@MainActor
final class DummyDuckAIGridItemProvider: DuckAIGridItemProviding {

    private static let cycle: [DuckAIGridItem?] = [
        .text(title: "Cute ducks",
              snippet: "Sure! Ducks are highly social birds that live in flocks called rafts when on water and waddles when on land. They have waterproof feathers thanks to a preen gland near the tail."),
        nil
    ]

    func gridItem(for tab: Tab) -> DuckAIGridItem? {
        // Stable per-tab assignment so the same tab always picks the same dummy variant
        // across cell reuse / collection-view reloads. `String.hashValue` is randomized
        // per process but stable within it, which is sufficient for dev iteration.
        let index = abs(tab.uid.hashValue) % Self.cycle.count
        return Self.cycle[index]
    }
}
#endif
