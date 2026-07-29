//
//  UnifiedToggleInputFeature.swift
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

import Foundation
import Common
import FoundationExtensions
import Core
import PrivacyConfig

protocol UnifiedToggleInputFeatureProviding {
    var isAvailable: Bool { get }
    /// When true, the UTI hides the Search↔Duck.ai toggle on Duck.ai tabs regardless of the
    /// user's toggle-enabled setting. Backed by `FeatureFlag.aiChatTabHideToggle`.
    ///
    /// No protocol-extension default: every conformer (including test mocks) must declare an
    /// explicit value so test coverage isn't silently masked by a convenient fallback.
    var isToggleHiddenOnDuckAITab: Bool { get }

    /// When true, a native image/file paste is routed into the attachment strip. Backed by `FeatureFlag.unifiedToggleInputAttachmentPaste`.
    var isAttachmentPasteEnabled: Bool { get }
}

struct UnifiedToggleInputFeature: UnifiedToggleInputFeatureProviding {

    private static let isEligibleKey = "com.duckduckgo.unifiedToggleInput.eligible"
    private static let isToggleHiddenOnDuckAITabKey = "com.duckduckgo.unifiedToggleInput.aiChatTabHideToggle.session.enabled"
    private static let isAttachmentPasteEnabledKey = "com.duckduckgo.unifiedToggleInput.attachmentPaste.session.enabled"

    /// Forward-only "this device has had UTI" bit. Persists across launches and flag flips and is
    /// cleared only by uninstall. Lets the new-user cutoff (`unifiedToggleInputIncludeNewUsers`)
    /// stop *new* users without revoking UTI from anyone already granted.
    private static let hasGrantedKey = "com.duckduckgo.unifiedToggleInput.hasGranted"

    /// Snapshot the feature flags once per session. Call early at launch, before any consumer reads `isAvailable` / `isToggleHiddenOnDuckAITab`.
    static func resolve(using featureFlagger: FeatureFlagger,
                        devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        let featureOn = featureFlagger.isFeatureOn(.unifiedToggleInput)
        let includeNewUsers = featureFlagger.isFeatureOn(.unifiedToggleInputIncludeNewUsers)
        let hasGranted = UserDefaults.app.bool(forKey: hasGrantedKey)

        // Eligible when the `unifiedToggleInput` flag is on AND the user either already had UTI
        // (sticky grant) or new users are still being included. That flag off revokes UTI from everyone.
        let isEligible = featureOn && (hasGranted || includeNewUsers)
        UserDefaults.app.set(isEligible, forKey: isEligibleKey)
        UserDefaults.app.set(featureFlagger.isFeatureOn(.aiChatTabHideToggle), forKey: isToggleHiddenOnDuckAITabKey)
        UserDefaults.app.set(featureFlagger.isFeatureOn(.unifiedToggleInputAttachmentPaste), forKey: isAttachmentPasteEnabledKey)

        // Lock in the grant the first launch UTI is actually available on this device, so a later
        // new-user cutoff never revokes it. Device-gated so a device that never showed UTI is not
        // wrongly treated as granted if UTI later expands beyond iPhone.
        if isEligible && devicePlatform.isIphone && !hasGranted {
            UserDefaults.app.set(true, forKey: hasGrantedKey)
        }
    }

    private let devicePlatform: DevicePlatformProviding.Type

    init(devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.devicePlatform = devicePlatform
    }

    private var isEligible: Bool {
        UserDefaults.app.bool(forKey: Self.isEligibleKey)
    }

    var isAvailable: Bool {
        isEligible && devicePlatform.isIphone
    }

    var isToggleHiddenOnDuckAITab: Bool {
        UserDefaults.app.bool(forKey: Self.isToggleHiddenOnDuckAITabKey)
    }

    var isAttachmentPasteEnabled: Bool {
        UserDefaults.app.bool(forKey: Self.isAttachmentPasteEnabledKey)
    }

#if DEBUG
    /// Test-only: clears the persisted UTI state (sticky grant + eligibility snapshot) so each test
    /// starts from a clean, un-granted device without depending on a follow-up `resolve(...)`.
    static func resetPersistedStateForTesting() {
        UserDefaults.app.removeObject(forKey: hasGrantedKey)
        UserDefaults.app.removeObject(forKey: isEligibleKey)
    }
#endif
}
