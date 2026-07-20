//
//  AIChatDeleter.swift
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
import Foundation
import PixelKit
import UserScript
import os.log

protocol AIChatDeleting: AnyObject {
    /// Deletes the chat from native storage synchronously (tombstone written before returning), then
    /// clears JS-layer storage and propagates the deletion to sync in the background. A caller that
    /// only needs the chat gone from native storage can return as soon as this call does.
    ///
    /// `onComplete` runs once the background work finishes, success or failure. Use it to refresh UI
    /// that the JS clear (not the native phase) is responsible for, so a failed delete reappears
    /// honestly instead of staying optimistically hidden.
    @MainActor func deleteChat(chatID: String, onComplete: (() -> Void)?)
}

extension AIChatDeleting {
    @MainActor func deleteChat(chatID: String) {
        deleteChat(chatID: chatID, onComplete: nil)
    }
}

/// Mirrors iOS's `AIChatDeleter`: deletes a Duck.ai chat via the shared `HistoryCleaner` and, on
/// success, records it with `AIChatSyncCleaning` to propagate to the sync server. Unlike iOS it
/// splits the native delete from the JS clear, so a caller needn't wait on the up-to-5s headless
/// WebView clear before responding.
final class AIChatDeleter: AIChatDeleting {
    private let historyCleaner: PhasedAIChatHistoryCleaning
    private let syncCleaner: () -> AIChatSyncCleaning?
    private let recordsSyncDeletion: Bool
    private let firePixel: (PixelKitEvent) -> Void

    init(historyCleaner: PhasedAIChatHistoryCleaning,
         syncCleaner: @escaping () -> AIChatSyncCleaning? = { Application.appDelegate.aiChatSyncCleaner },
         recordsSyncDeletion: Bool = true,
         firePixel: @escaping (PixelKitEvent) -> Void = { PixelKit.fire($0, frequency: .dailyAndCount) }) {
        self.historyCleaner = historyCleaner
        self.syncCleaner = syncCleaner
        self.recordsSyncDeletion = recordsSyncDeletion
        self.firePixel = firePixel
    }

    @MainActor
    func deleteChat(chatID: String, onComplete: (() -> Void)?) {
        let nativeResult = historyCleaner.deleteAIChatFromNativeStorage(chatID: chatID)

        Task { @MainActor [historyCleaner, syncCleaner, recordsSyncDeletion, firePixel] in
            let jsResult = await historyCleaner.clearJSData(chatID: chatID)

            // Failure precedence matches HistoryCleaner.performClear: a native-storage failure wins;
            // otherwise the JS-clear result decides.
            let overallResult: Result<Void, Error>
            if case .failure = nativeResult {
                overallResult = nativeResult ?? jsResult
            } else {
                overallResult = jsResult
            }

            switch overallResult {
            case .success:
                firePixel(AIChatPixel.aiChatSingleDeleteSuccessful)
                if recordsSyncDeletion, let syncCleaner = syncCleaner() {
                    await syncCleaner.recordChatDeletion(chatID: chatID)
                    syncCleaner.scheduleSync()
                }
            case .failure(let error):
                Logger.aiChat.debug("AIChatDeleter: failed to delete chat \(chatID): \(error.localizedDescription)")
                firePixel(AIChatPixel.aiChatSingleDeleteFailed)
                // Mirror iOS: attribute headless-WebView script-load failures via the JS-load pixel.
                if let userScriptError = error as? UserScriptError {
                    userScriptError.fireLoadJSFailedPixelIfNeeded()
                }
            }
            onComplete?()
        }
    }
}
