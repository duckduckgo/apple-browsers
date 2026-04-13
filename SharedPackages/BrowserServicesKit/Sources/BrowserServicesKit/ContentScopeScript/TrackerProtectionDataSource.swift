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
/// `trackerData` provides the full merged TDS for native classification.
/// `surrogateFilteredTrackerData` provides the surrogate-only subset for ContentScopeProperties.
/// `encodedTrackerData` provides the surrogate-filtered JSON for C-S-S injection.
///
/// All values are computed once at construction from a `currentRules` snapshot,
/// eliminating per-access merging and encoding overhead.
public protocol TrackerProtectionDataSource {
    var trackerData: TrackerData? { get }
    var surrogateFilteredTrackerData: TrackerData? { get }
    var encodedTrackerData: String? { get }
}

/// Default implementation that pre-computes all tracker data from a rules snapshot.
///
/// On macOS, ClickToLoad rules are compiled into a separate rule list.
/// Pass the list name via `additionalRuleLists` so the merged tracker data
/// includes CTL rules (e.g. `block-ctl-fb`), making them visible to the
/// C-S-S TrackerResolver for blocking decisions and dashboard reporting.
///
/// All values are computed eagerly at init and cached as stored properties,
/// avoiding repeated merging/encoding on every access.
public struct DefaultTrackerProtectionDataSource: TrackerProtectionDataSource {

    public let trackerData: TrackerData?
    public let surrogateFilteredTrackerData: TrackerData?
    public let encodedTrackerData: String?

    public init(contentBlockingManager: CompiledRuleListsSource,
                additionalRuleLists: [String] = []) {
        let merged = Self.computeMergedTrackerData(from: contentBlockingManager, additionalRuleLists: additionalRuleLists)
        self.trackerData = merged

        if let merged {
            let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: merged)
            self.surrogateFilteredTrackerData = surrogateTDS

            if let encodedData = try? JSONEncoder().encode(JavaScriptTrackerData(from: surrogateTDS)),
               let encodedString = String(data: encodedData, encoding: .utf8) {
                self.encodedTrackerData = encodedString
            } else {
                Logger.contentBlocking.warning("TrackerProtectionDataSource: Failed to encode surrogate TDS")
                self.encodedTrackerData = nil
            }
        } else {
            Logger.contentBlocking.warning("TrackerProtectionDataSource: no tracker data available at init")
            self.surrogateFilteredTrackerData = nil
            self.encodedTrackerData = nil
        }
    }

    /// Merge main TDS tracker data with any additional compiled rule lists
    /// (e.g. ClickToLoad).  Takes a single snapshot of `currentRules` to
    /// avoid torn reads while rules are recompiling.
    private static func computeMergedTrackerData(from contentBlockingManager: CompiledRuleListsSource,
                                                 additionalRuleLists: [String]) -> TrackerData? {
        let rulesSnapshot = contentBlockingManager.currentRules
        guard let main = rulesSnapshot.first(where: {
            $0.name == DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        }) else {
            return nil
        }

        guard !additionalRuleLists.isEmpty else { return main.trackerData }

        var trackers = main.trackerData.trackers
        var entities = main.trackerData.entities
        var domains = main.trackerData.domains

        for name in additionalRuleLists {
            guard let rules = rulesSnapshot.first(where: { $0.name == name }) else { continue }
            trackers.merge(rules.trackerData.trackers) { _, new in new }
            entities.merge(rules.trackerData.entities) { _, new in new }
            domains.merge(rules.trackerData.domains) { _, new in new }
        }

        return TrackerData(trackers: trackers, entities: entities, domains: domains,
                           cnames: main.trackerData.cnames)
    }
}
