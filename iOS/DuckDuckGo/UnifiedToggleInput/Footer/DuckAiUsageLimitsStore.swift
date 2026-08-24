//
//  DuckAiUsageLimitsStore.swift
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

import AIChat
import Core
import FeatureFlags_iOS
import Foundation
import os.log
import PrivacyConfig

struct DuckAiUsageLimitsStore {

#if DEBUG || ALPHA
    @MainActor static var debugOverride: DuckAiUsageLimits?
#endif

    private let provider: DuckAiUsageLimitsProviding?
    private let featureFlagger: FeatureFlagger

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         dateProvider: @escaping () -> Date = Date.init) {
        self.provider = storageHandler.map {
            DuckAiUsageLimitsProvider(storage: $0,
                                      pixelFiring: DuckAiNativeStoragePixelAdapter(),
                                      dateProvider: dateProvider)
        }
        self.featureFlagger = featureFlagger
    }

    func currentLimits() -> DuckAiUsageLimits? {
        guard featureFlagger.isFeatureOn(.utiDuckAIWarnings) else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] store inactive: utiDuckAIWarnings flag is off")
            return nil
        }
#if DEBUG || ALPHA
        if let override = MainActor.assumeIsolated({ Self.debugOverride }) {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] using debug override snapshot")
            return override
        }
#endif
        guard let provider else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] store inactive: no native-storage bridge")
            return nil
        }
        let limits = provider.currentUsageLimits()
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] limits read: daily=\(Self.describe(limits.daily), privacy: .private) weekly=\(Self.describe(limits.weekly), privacy: .private)")
        return limits
    }

    private static func describe(_ usage: DuckAiUsageLimitWindow?) -> String {
        guard let usage else { return "none" }
        return "\(usage.percentUsed)% resets \(usage.resetsAt)"
    }
}
