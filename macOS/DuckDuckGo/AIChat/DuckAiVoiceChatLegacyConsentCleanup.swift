//
//  DuckAiVoiceChatLegacyConsentCleanup.swift
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

protocol DuckAiVoiceChatLegacyConsentCleaning {
    func runIfNeeded()
}

/// One-shot cleanup for users who previously persisted `.deny` for duck.ai/mic. The
/// `DuckAiVoiceChatPermissionOverride` flips the effective decision to `.allow` at read time,
/// but the FE's stored `hasVoiceModeConsent` may be a stale `true` from before the deny — and
/// claiming consent for a capability the user explicitly blocked is wrong. This clears that
/// stale FE entry once, then marks itself done in `UserDefaults` so subsequent launches skip it.
///
/// Only fires for `.deny`; `.ask` and `.allow` (and fresh installs with nothing persisted) keep
/// any existing consent intact.
final class DuckAiVoiceChatLegacyConsentCleanup: DuckAiVoiceChatLegacyConsentCleaning {

    private static let voiceModeConsentKey = "hasVoiceModeConsent"
    private static let cleanupDoneUserDefaultsKey = "com.duckduckgo.duckAiVoiceChat.legacyConsentCleanupDone"

    private let permissionManager: PermissionManagerProtocol
    private let storageHandler: DuckAiNativeStorageHandling?
    private let aiChatURL: URL
    private let userDefaults: UserDefaults

    init(permissionManager: PermissionManagerProtocol,
         storageHandler: DuckAiNativeStorageHandling?,
         aiChatURL: URL = .duckAi,
         userDefaults: UserDefaults = .standard) {
        self.permissionManager = permissionManager
        self.storageHandler = storageHandler
        self.aiChatURL = aiChatURL
        self.userDefaults = userDefaults
    }

    func runIfNeeded() {
        guard !userDefaults.bool(forKey: Self.cleanupDoneUserDefaultsKey) else { return }
        guard let host = aiChatURL.host else { return }
        defer { userDefaults.set(true, forKey: Self.cleanupDoneUserDefaultsKey) }

        // Read the underlying persisted value, not the override-masked one.
        guard permissionManager.persistedDecision(forDomain: host, permissionType: .microphone) == .deny else {
            return
        }

        // `aiChatNativeStorage` is at 100% rollout in production, so `storageHandler` is
        // effectively always non-nil here. In dev builds with that flag off the FE's
        // `hasVoiceModeConsent` lives in localStorage out of native's reach, and this is a
        // no-op — accepted since it can't reach prod.
        try? storageHandler?.deleteEntry(key: Self.voiceModeConsentKey)
    }
}
