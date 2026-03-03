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

/// Source of tracker data and surrogates for the C-S-S trackerProtection feature.
///
/// Provides the full tracker data set (not the surrogate-filtered subset) and
/// the raw surrogates.txt payload for injection into the privacy config.
/// The JS-side TrackerResolver needs all trackers to detect both surrogate
/// and non-surrogate tracker requests, and the surrogates text to build the
/// runtime surrogate function map.
public protocol TrackerProtectionDataSource {
    var trackerData: TrackerData? { get }
    var encodedTrackerData: String? { get }
    /// Raw surrogates.txt content for C-S-S to parse into callable surrogate functions.
    var surrogatesText: String? { get }
}

/// Default implementation using `CompiledRuleListsSource` (typically `ContentBlockerRulesManager`).
///
/// The `surrogatesProvider` closure lets platform code supply the surrogates.txt
/// content from its own configuration store without coupling BSK to the
/// `Configuration` module.
public struct DefaultTrackerProtectionDataSource: TrackerProtectionDataSource {

    private let contentBlockingManager: CompiledRuleListsSource
    private let surrogatesProvider: () -> String?

    public init(contentBlockingManager: CompiledRuleListsSource,
                surrogatesProvider: @escaping () -> String? = { nil }) {
        self.contentBlockingManager = contentBlockingManager
        self.surrogatesProvider = surrogatesProvider
    }

    public var surrogatesText: String? {
        surrogatesProvider()
    }

    public var trackerData: TrackerData? {
        contentBlockingManager.currentMainRules?.trackerData
    }

    /// Returns JSON-encoded full tracker data for the C-S-S trackerProtection feature.
    ///
    /// Encodes the full `trackerData`, not the pre-filtered `encodedTrackerData` from
    /// `Rules`. The `Rules.encodedTrackerData` only contains trackers with surrogates
    /// (filtered by `extractSurrogates`), but trackerProtection needs all trackers.
    public var encodedTrackerData: String? {
        guard let trackerData = contentBlockingManager.currentMainRules?.trackerData else {
            Logger.contentBlocking.warning("TrackerProtectionDataSource: currentMainRules is nil")
            return nil
        }

        guard let encodedData = try? JSONEncoder().encode(trackerData),
              let encodedString = String(data: encodedData, encoding: .utf8) else {
            Logger.contentBlocking.warning("TrackerProtectionDataSource: Failed to encode trackerData")
            return nil
        }

        return encodedString
    }
}
