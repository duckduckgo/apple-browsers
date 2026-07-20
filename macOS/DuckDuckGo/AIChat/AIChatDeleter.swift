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
    /// Deletes a chat from native storage synchronously (tombstone written before returning), then
    /// continues clearing JS-layer storage and propagating the deletion to sync in the background.
    /// Callers that need the chat gone before re-querying (e.g. a suggestions re-fetch) only need
    /// to wait for this call to return, not for the deletion to fully complete.
    ///
    /// `onComplete`, if provided, runs once the full deletion pipeline (JS-layer clear and, on
    /// success, sync propagation) has finished — regardless of whether it succeeded. Use it to
    /// refresh UI that reads from a source the synchronous native-storage phase alone might not
    /// have updated: on success the chat is gone everywhere; on failure it may still be present,
    /// so re-fetching honestly reflects the real state rather than the optimistic removal.
    @MainActor func deleteChat(chatID: String, onComplete: (() -> Void)?)
}

extension AIChatDeleting {
    @MainActor func deleteChat(chatID: String) {
        deleteChat(chatID: chatID, onComplete: nil)
    }
}

/// Mirrors iOS's `AIChatDeleter`: deletes a single Duck.ai chat via the shared `HistoryCleaner` and,
/// on success, records the deletion with `AIChatSyncCleaning` so it propagates to the sync server.
/// Unlike iOS, native storage deletion and JS-layer clearing are split so a caller can respond to a
/// UI request as soon as the chat is gone from native storage, without waiting on the JS clear
/// (which runs a headless WebView and can take up to 5 seconds).
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

            // Same failure precedence as HistoryCleaner.performClear: a native-storage failure wins,
            // otherwise the JS-clear result (success or failure) is what matters.
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
                // Mirror iOS: surface the JS-load diagnostic when the failure was a headless-WebView
                // script load failure, so delete-path breakages are attributable.
                if let userScriptError = error as? UserScriptError {
                    userScriptError.fireLoadJSFailedPixelIfNeeded()
                }
            }
            onComplete?()
        }
    }
}
