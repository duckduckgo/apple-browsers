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

/// Reads the Duck.ai usage-limit snapshot from the native-storage bridge for the Duck.ai input surfaces
/// (address bar omnibar, Prompt Bar, New Tab Page omnibar), gated on the usage-warnings feature flag.
///
/// Mirrors `CustomizeResponsesStore`: the shared reader stays flag-agnostic and this owns the app-side gating,
/// so call sites don't repeat it. The store is cheap to build — construct it with a burner-aware handler at the
/// surface's construction site, the same way `CustomizeResponsesStore` is.
final class DuckAiUsageLimitsStore {

    private let provider: DuckAiUsageLimitsProviding?
    private let featureFlagger: FeatureFlagger

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.provider = storageHandler.map { DuckAiUsageLimitsProvider(storage: $0) }
        self.featureFlagger = featureFlagger
    }

    /// `nil` when there is nothing to read at all: the feature flag is off, or native storage is unavailable
    /// (flag off, outside the `nativeStorage` rollout, bridge never installed). `.noData` when the read happened
    /// but produced no usable window. Callers must keep the two apart — the first means "feature inactive",
    /// the second means "active, but we don't know this user's usage".
    func currentLimits() -> DuckAiUsageLimits? {
        guard featureFlagger.isFeatureOn(.aiChatUsageWarnings), let provider else { return nil }
        let limits = provider.currentUsageLimits()
        // Which windows we got is public so the read is verifiable from Console; the percentages themselves
        // are the user's usage and stay redacted.
        Logger.aiChat.debug("""
            Duck.ai usage limits read: daily=\(limits.daily == nil ? "none" : "present", privacy: .public) \
            weekly=\(limits.weekly == nil ? "none" : "present", privacy: .public) \
            values=[\(limits.daily?.percentUsed ?? -1, privacy: .private), \(limits.weekly?.percentUsed ?? -1, privacy: .private)]
            """)
        return limits
    }
}
