//
//  DuckAiVoiceChatPermissionMigration.swift
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

protocol DuckAiVoiceChatPermissionMigrating {
    func tryToMigrateVoiceChatPermission()
}

/// At launch, reconciles browser-level microphone permission for duck.ai. Voice is
/// a first-party Duck.ai surface gated by the in-app consent prompt, not the WebKit
/// permission UI, so we keep the persisted decision pinned to `.allow`:
///
/// - `.deny`: clear the stored voice-mode consent (so the in-app prompt re-appears
///   instead of claiming consent for a capability the user just blocked), then flip
///   the decision to `.allow`.
/// - `.ask`: flip to `.allow` (no consent clear — the user hasn't blocked anything).
/// - `.allow`: nothing to do.
final class DuckAiVoiceChatPermissionMigration: DuckAiVoiceChatPermissionMigrating {

    private static let voiceModeConsentKey = "hasVoiceModeConsent"

    private let permissionManager: PermissionManagerProtocol
    private let storageHandler: DuckAiNativeStorageHandling?
    private let aiChatURL: URL
    private let pixelFiring: PixelFiring?

    init(permissionManager: PermissionManagerProtocol,
         storageHandler: DuckAiNativeStorageHandling?,
         aiChatURL: URL = .duckAi,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.permissionManager = permissionManager
        self.storageHandler = storageHandler
        self.aiChatURL = aiChatURL
        self.pixelFiring = pixelFiring
    }

    func tryToMigrateVoiceChatPermission() {
        guard let host = aiChatURL.host else { return }

        let isPersisted = permissionManager.hasPermissionPersisted(forDomain: host, permissionType: .microphone)

        switch permissionManager.permission(forDomain: host, permissionType: .microphone) {
        case .deny:
            // `aiChatNativeStorage` is at 100% rollout in production, so `storageHandler`
            // is effectively always non-nil here. In dev builds with that flag off the
            // FE's `hasVoiceModeConsent` lives in localStorage out of native's reach,
            // and the consent-clear becomes a no-op — accepted since it can't reach prod.
            try? storageHandler?.deleteEntry(key: Self.voiceModeConsentKey)
            permissionManager.setPermission(.allow, forDomain: host, permissionType: .microphone)
            pixelFiring?.fire(AIChatPixel.aiChatVoiceChatPermissionAutoGranted(from: .deny), frequency: .dailyAndCount)
        case .ask:
            permissionManager.setPermission(.allow, forDomain: host, permissionType: .microphone)
            // `.ask` is also the fallback when nothing is persisted, so fresh installs read
            // as `.ask` too. Only fire the migration pixel when the user actually had a
            // persisted `.ask` decision — otherwise telemetry conflates "fresh user we
            // pre-allowed" with "explicit `.ask` we migrated".
            if isPersisted {
                pixelFiring?.fire(AIChatPixel.aiChatVoiceChatPermissionAutoGranted(from: .ask), frequency: .dailyAndCount)
            }
        case .allow:
            break
        }
    }
}
