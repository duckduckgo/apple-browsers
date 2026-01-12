//
//  DefaultTrackerStatsDataSource.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import Foundation
import os.log
import TrackerRadarKit

/// Default implementation of TrackerStatsDataSource using ContentBlockerRulesManager
///
/// Note: This data source provides tracker data for JSON config injection.
/// Surrogates are NOT passed via JSON because JavaScript functions can't be serialized.
/// Instead, surrogates are loaded via native messaging (TrackerStatsSubfeature.handleLoadSurrogate).
public struct DefaultTrackerStatsDataSource: TrackerStatsDataSource {

    private let contentBlockingManager: CompiledRuleListsSource

    /// Initialize with a content blocking manager
    /// - Parameter contentBlockingManager: Source for tracker data
    public init(contentBlockingManager: CompiledRuleListsSource) {
        self.contentBlockingManager = contentBlockingManager
    }

    public var trackerData: TrackerData? {
        contentBlockingManager.currentMainRules?.trackerData
    }

    /// Returns JSON-encoded tracker data for the C-S-S tracker-stats feature.
    ///
    /// Note: We encode the FULL trackerData here, not the pre-filtered encodedTrackerData
    /// from Rules. The Rules.encodedTrackerData only contains trackers with surrogates
    /// (filtered by extractSurrogates), but tracker-stats needs ALL trackers to detect
    /// both surrogate and non-surrogate tracker requests.
    public var encodedTrackerData: String? {
        guard let rules = contentBlockingManager.currentMainRules else {
            Logger.contentBlocking.warning("DefaultTrackerStatsDataSource: currentMainRules is nil - tracker data unavailable")
            return nil
        }

        // Encode the FULL tracker data, not the surrogate-filtered version
        guard let encodedData = try? JSONEncoder().encode(rules.trackerData),
              let encodedString = String(data: encodedData, encoding: .utf8) else {
            Logger.contentBlocking.warning("DefaultTrackerStatsDataSource: Failed to encode trackerData")
            return nil
        }

        return encodedString
    }
}
