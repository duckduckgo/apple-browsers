//
//  TrackerProtectionDataSource.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Source of tracker data for the C-S-S trackerProtection feature.
///
/// `trackerData` provides the main TDS used for native classification.
/// `surrogateFilteredTrackerData` provides the surrogate-only subset for ContentScopeProperties.
///
/// Values are computed once at construction from a `currentRules` snapshot.
public protocol TrackerProtectionDataSource {
    var trackerData: TrackerData? { get }
    var surrogateFilteredTrackerData: TrackerData? { get }
}

/// Default implementation that pre-computes tracker data from a rules snapshot.
public struct DefaultTrackerProtectionDataSource: TrackerProtectionDataSource {

    public let trackerData: TrackerData?
    public let surrogateFilteredTrackerData: TrackerData?

    public init(contentBlockingManager: CompiledRuleListsSource) {
        let mainTrackerData = Self.mainTrackerData(from: contentBlockingManager)
        self.trackerData = mainTrackerData

        if let mainTrackerData {
            let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: mainTrackerData)
            self.surrogateFilteredTrackerData = surrogateTDS
        } else {
            Logger.contentBlocking.warning("TrackerProtectionDataSource: no tracker data available at init")
            self.surrogateFilteredTrackerData = nil
        }
    }

    /// Read from a single `currentRules` snapshot to avoid torn reads while rules are recompiling.
    private static func mainTrackerData(from contentBlockingManager: CompiledRuleListsSource) -> TrackerData? {
        let rulesSnapshot = contentBlockingManager.currentRules
        return rulesSnapshot.first(where: {
            $0.name == DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        })?.trackerData
    }
}
