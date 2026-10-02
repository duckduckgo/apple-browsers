//
//  BrokenSiteReportAppFeatureFlags.swift
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

import PrivacyConfig
import FeatureFlags_iOS

enum BrokenSiteReportAppFeatureFlags {

    private static let reportedFlags: [FeatureFlag] = [
        .floatingUIiOS26,
        .floatingUIiOS27
    ]

    static func adding(to parameters: [String: String], featureFlagger: FeatureFlagger) -> [String: String] {
        var parameters = parameters
        parameters["appFeatureFlags"] = reportedFlags
            .filter { featureFlagger.isFeatureOn($0) }
            .map { $0.rawValue }
            .joined(separator: ",")
        return parameters
    }
}
