//
//  ContentScopeUserScript+TrackerStats.swift
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

import Foundation
import UserScript

/// Extension to register tracker-stats and debug logging subfeatures
///
/// ## Usage
///
/// ```swift
/// // In Tab setup code (iOS TabViewController or macOS Tab)
/// let trackerStats = TrackerStatsSubfeature(delegate: self)
/// let debugLog = DebugLogSubfeature(instrumentation: tabInstrumentation)
///
/// contentScopeUserScript.registerTrackerStatsSubfeature(trackerStats)
/// contentScopeUserScript.registerDebugLogSubfeature(debugLog)
/// ```
extension ContentScopeUserScript {

    /// Register the tracker-stats subfeature for surrogate injection handling
    /// - Parameter subfeature: The TrackerStatsSubfeature instance
    public func registerTrackerStatsSubfeature(_ subfeature: TrackerStatsSubfeature) {
        registerSubfeature(delegate: subfeature)
    }

    /// Register the debug log subfeature for native log routing
    /// - Parameter subfeature: The DebugLogSubfeature instance
    public func registerDebugLogSubfeature(_ subfeature: DebugLogSubfeature) {
        registerSubfeature(delegate: subfeature)
    }
}
