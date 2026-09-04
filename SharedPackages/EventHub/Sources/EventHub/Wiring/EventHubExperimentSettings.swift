//
//  EventHubExperimentSettings.swift
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
import PrivacyConfig

/// Reads the experiment subfeature settings that `EventHub`'s metrics registry is built from.
///
/// Shared by both platform integrations rather than duplicated in each: which parent features are read
/// is a correctness-relevant list, and iOS and macOS silently disagreeing about it would mean metrics
/// attaching under one parent and not the other.
public enum EventHubExperimentSettings {

    /// The parent features whose subfeatures may declare `settings.metrics`: Content Scope Scripts
    /// experiments and — on Apple and the extension, where TDS experiments live under content
    /// blocking rather than Android's `blockList` — TDS experiments. Both are read, so a metric
    /// attaches under either parent (M-SEL-8).
    public static let parentFeatures: [PrivacyFeature] = [.contentScopeExperiments, .contentBlocking]

    /// The raw `settings` JSON of every experiment subfeature that may declare metrics, keyed by
    /// subfeature ID — the shape `EventHub`'s `experimentSettings` publisher expects.
    ///
    /// Subfeature IDs are unique across the two parents in practice; on a collision the first parent
    /// listed wins, which is arbitrary but harmless — nothing depends on which parent a metric came
    /// from once it is parsed, since a conversion request names only the subfeature.
    public static func current(_ config: PrivacyConfiguration) -> [String: String] {
        parentFeatures.reduce(into: [:]) { result, feature in
            result.merge(config.allSubfeatureSettings(for: feature)) { existing, _ in existing }
        }
    }
}
