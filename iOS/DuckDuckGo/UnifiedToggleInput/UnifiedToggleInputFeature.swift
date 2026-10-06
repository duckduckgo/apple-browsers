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
import Core
import PrivacyConfig
import FeatureFlags_iOS

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

    private static let isToggleHiddenOnDuckAITabKey = "com.duckduckgo.unifiedToggleInput.aiChatTabHideToggle.session.enabled"
    private static let isAttachmentPasteEnabledKey = "com.duckduckgo.unifiedToggleInput.attachmentPaste.session.enabled"

    /// Snapshot the feature flags once per session. Call early at launch, before any consumer reads them.
    static func resolve(using featureFlagger: FeatureFlagger) {
        UserDefaults.app.set(featureFlagger.isFeatureOn(.aiChatTabHideToggle), forKey: isToggleHiddenOnDuckAITabKey)
        UserDefaults.app.set(featureFlagger.isFeatureOn(.unifiedToggleInputAttachmentPaste), forKey: isAttachmentPasteEnabledKey)
    }

    private let devicePlatform: DevicePlatformProviding.Type

    init(devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.devicePlatform = devicePlatform
    }

    var isAvailable: Bool {
        devicePlatform.isIphone
    }

    var isToggleHiddenOnDuckAITab: Bool {
        UserDefaults.app.bool(forKey: Self.isToggleHiddenOnDuckAITabKey)
    }

    var isAttachmentPasteEnabled: Bool {
        UserDefaults.app.bool(forKey: Self.isAttachmentPasteEnabledKey)
    }

}
