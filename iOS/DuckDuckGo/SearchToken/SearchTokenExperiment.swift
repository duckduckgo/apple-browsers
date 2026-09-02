//
//  SearchTokenExperiment.swift
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

import BrowserServicesKit
import Core
import Foundation
import PixelKit
import PrivacyConfig
import FeatureFlags_iOS

/// Temporary diagnostic pixels for the Search Token (Dindex) experiment (treatment cohort only).
/// Fired via PixelKit, which appends the `_ios_phone`/`_ios_tablet` platform suffix automatically —
/// so names are grouped by feature with no `m_` prefix. Both expire 2026-10-12; see search_token.json5.
enum SearchTokenPixel: PixelKit.Event {
    /// This pixel signature is non-standard and not aligned to the current PixelKit defaults. This policy freezes the signature to a legacy, and incorrect, suffix ordering.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyBeforeFrequencySuffix }

    /// A treatment variant-b SERP navigation the interceptor decorated: whether a token was attached and its length bucket.
    case serpAttach(outcome: String, tokenLength: String)
    /// A warm token-fetch attempt and its result.
    case fetch(result: String)

    var name: String {
        switch self {
        case .serpAttach: return "search-token_serp-attach"
        case .fetch: return "search-token_fetch"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .serpAttach(let outcome, let tokenLength):
            return ["outcome": outcome, "token_length": tokenLength]
        case .fetch(let result):
            return ["result": result]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: PixelKitNamePrefix { .none }
}

struct SearchTokenExperiment {

    private let featureFlagger: FeatureFlagger
    private let statisticsStore: StatisticsStore

    init(featureFlagger: FeatureFlagger,
         statisticsStore: StatisticsStore = StatisticsUserDefaults()) {
        self.featureFlagger = featureFlagger
        self.statisticsStore = statisticsStore
    }

    /// Resolves — and thereby enrols — the cohort for an eligible new user. No-op for returning users.
    func enrollIfEligible() {
        guard statisticsStore.variant != VariantIOS.returningUser.name else { return }
        _ = featureFlagger.resolveCohort(for: FeatureFlag.searchTokenExperimentV4)
    }

    /// The assigned cohort, or `nil` when not enrolled.
    var cohort: FeatureFlag.SearchTokenExperimentCohort? {
        FeatureFlag.SearchTokenExperimentCohort.treatment
    }
}
