//
//  DuckAiUsageLimitsStore.swift
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
import AppKit
import FeatureFlags_macOS
import os.log
import PrivacyConfig

/// Owns the app-side flag gating so the shared reader stays flag-agnostic and call sites don't repeat it.
/// Mirrors `CustomizeResponsesStore`: cheap to build, constructed with a burner-aware handler per surface.
final class DuckAiUsageLimitsStore {

    private let provider: DuckAiUsageLimitsProviding?
    private let featureFlagger: FeatureFlagger

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.provider = storageHandler.map {
            DuckAiUsageLimitsProvider(storage: $0, pixelFiring: DuckAiNativeStoragePixelAdapter())
        }
        self.featureFlagger = featureFlagger
    }

    /// `nil` means the feature is inactive (flag off, or no storage bridge); `.noData` means active but nothing
    /// worth warning about. Callers must keep the two apart.
    func currentLimits() -> DuckAiUsageLimits? {
        guard featureFlagger.isFeatureOn(.aiChatUsageWarnings), let provider else { return nil }
        let limits = provider.currentUsageLimits()
        // Marked private so the percentages are redacted wherever redaction applies; local debug builds
        // still show them, which is what makes a read verifiable while testing.
        Logger.aiChat.debug("""
            Duck.ai usage limits read: daily=\(Self.describe(limits.daily), privacy: .private) \
            weekly=\(Self.describe(limits.weekly), privacy: .private)
            """)
        return limits
    }

    private static func describe(_ window: DuckAiUsageLimitWindow?) -> String {
        guard let window else { return "none" }
        return "\(window.percentUsed)% resets \(window.resetsAt)"
    }
}
