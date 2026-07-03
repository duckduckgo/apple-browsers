//
//  DuckAiVoiceChatShieldScope.swift
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

import FeatureFlags
import Foundation
import PrivacyConfig

/// Predicate shared by the address-bar shield's visibility and click-routing logic for the
/// Duck.ai voice-chat flow. Returns `true` when, on `duck.ai` with the native voice-chat
/// flag on, the only permission in play is `.microphone`. In that state the Permission
/// Center would be empty (mic is filtered out as a row by `PermissionCenterViewModel`), so
/// the shield should either be hidden (when no remediation is needed) or routed straight
/// to the OS-disabled mic popover (when it is) instead of opening the Permission Center.
enum DuckAiVoiceChatShieldScope {

    /// - Parameters:
    ///   - domain: Host of the page currently displayed in the address bar.
    ///   - usedPermissions: In-session permission states (e.g. mic currently active).
    ///   - persistedPermissionTypes: Per-site decisions persisted by `PermissionManager`.
    ///   - featureFlagger: Feature flag source. The predicate is gated on
    ///     `aiChatNativeVoicePermissionFlow`; with the flag off it always returns `false`.
    ///   - aiChatHost: Host to compare `domain` against. Defaults to `URL.duckAi.host`,
    ///     which honors the AI Chat Debug menu override on internal builds.
    static func isOnlyMicInPlay(
        domain: String,
        usedPermissions: Permissions,
        persistedPermissionTypes: [PermissionType],
        featureFlagger: FeatureFlagger,
        aiChatHost: String? = URL.duckAi.host
    ) -> Bool {
        guard featureFlagger.isFeatureOn(.aiChatNativeVoicePermissionFlow),
              let aiChatHost,
              domain == aiChatHost else {
            return false
        }
        let hasOtherPersisted = persistedPermissionTypes.contains { $0 != .microphone }
        let hasOtherUsed = usedPermissions.keys.contains { $0 != .microphone }
        return !hasOtherPersisted && !hasOtherUsed
    }
}
