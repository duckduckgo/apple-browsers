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
import ImageIO
import AIChat
import PrivacyConfig
import os.log

/// Resolves a `DuckAIGridItem` for a tab. Returns `nil` when the tab should fall
/// back to the existing screenshot path (flag off, not a Duck.ai chat tab, native
/// data unavailable, decode failure, …).
@MainActor
protocol DuckAIGridItemProviding: AnyObject {
    /// - Parameter liveVoiceActive: when `true`, the tab has a live voice session in progress
    /// and must render the live voice card regardless of any persisted classification.
    func gridItem(for tab: Tab, liveVoiceActive: Bool) -> DuckAIGridItem?
}

/// Loads thumbnail images for `DuckAIGridItem.image` cards.
@MainActor
protocol DuckAIThumbnailLoading: AnyObject {
    func loadImage(fileRef: String) async -> UIImage?
    /// Decodes on the calling thread; only used for the single cell being snapshotted.
    func loadImageSynchronously(fileRef: String) -> UIImage?
}

/// Composition of both grid-content capabilities.
@MainActor
protocol DuckAIGridContentProviding: DuckAIGridItemProviding, DuckAIThumbnailLoading {}

/// Resolves the content shown for a Duck.ai chat tab in the tab switcher grid,
/// reading from native chat storage.
@MainActor
final class DuckAIGridContentResolver: DuckAIGridContentProviding {
    
    private enum Constants {
        // Card thumbnail is 80×145pt; 512px covers it at 3× + aspectFill crop with margin.
        static let thumbnailMaxPixelSize = 512
    }

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

    /// `DuckAIGridItemProviding` entry point. Applies the outer feature-flag gate, the live-voice
    /// override, and the no-chat-ID case, then defers to `gridItem(forChatID:)`. Returns `nil` only
    /// when the rich card can't be shown at all (flag off) — the caller falls back to the screenshot.
    func gridItem(for tab: Tab, liveVoiceActive: Bool) -> DuckAIGridItem? {
        guard featureFlagger.isFeatureOn(.aiChatTabSwitcherRichCard) else { return nil }
        // A live voice session overrides any persisted classification
        if liveVoiceActive {
            return .voice
        }
        // No chatID (e.g. a brand-new Duck.ai tab) → the bare empty card, not the screenshot.
        guard let chatID = tab.link?.url.duckAIChatID else { return .empty(title: nil, chip: nil) }
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
        guard let storageHandler,
              aiChatFeatureFlagProvider.isNativeDataAccessEnabled() else {
            return nil
        }
        // Decode off the main thread — this path runs during normal grid scrolling.
        return await Task.detached {
            Self.readAndDecodeImage(fileRef: fileRef, storageHandler: storageHandler)
        }.value
    }

    func loadImageSynchronously(fileRef: String) -> UIImage? {
        guard let storageHandler,
              aiChatFeatureFlagProvider.isNativeDataAccessEnabled() else {
            return nil
        }
        return Self.readAndDecodeImage(fileRef: fileRef, storageHandler: storageHandler)
    }

    nonisolated private static func readAndDecodeImage(fileRef: String, storageHandler: DuckAiNativeStorageHandling) -> UIImage? {
        do {
            guard let file = try storageHandler.getFile(uuid: fileRef) else { return nil }
            return decodeImage(from: file.data)
        } catch {
            Logger.aiChat.error("DuckAIGridContentResolver: failed to read file: \(error.localizedDescription)")
            return nil
        }
    }

    /// Native files may be raw image bytes OR a `{data: <base64>, mimeType: ...}` JSON
    /// wrapper (debug-server dashboard is the reference). Try wrapper first, then raw,
    /// then downsample to the card's display size so the full-res bitmap is never decoded.
    nonisolated private static func decodeImage(from data: Data) -> UIImage? {
        let bytes: Data
        if let wrapper = try? JSONDecoder().decode(FileWrapper.self, from: data),
           let decoded = Data(base64Encoded: wrapper.data) {
            bytes = decoded
        } else {
            bytes = data
        }
        return downsample(bytes, maxPixelSize: Constants.thumbnailMaxPixelSize)
    }

    /// Decodes straight from the encoded bytes to a thumbnail-sized `CGImage` via ImageIO
    nonisolated private static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private struct FileWrapper: Decodable {
        let data: String
        let mimeType: String?
    }
}
