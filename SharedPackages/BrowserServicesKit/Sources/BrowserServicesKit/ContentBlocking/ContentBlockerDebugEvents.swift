//
//  ContentBlockerDebugEvents.swift
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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

public enum ContentBlockerDebugEvents {

    struct Parameters {
        static let etag = "etag"
        static let errorDescription = "error_desc"
    }

    public enum Component: String, CustomStringConvertible, CaseIterable {

        public var description: String { rawValue }

        case tds
        case allowlist
        case tempUnprotected
        case localUnprotected
        case fallbackTds

    }

    case trackerDataParseFailed
    case trackerDataReloadFailed
    case trackerDataCouldNotBeLoaded
    case privacyConfigurationReloadFailed
    case privacyConfigurationParseFailed
    case privacyConfigurationCouldNotBeLoaded

    case contentBlockingCompilationFailed(listName: String, component: Component)

    case contentBlockingLookupRulesSucceeded
    case contentBlockingFetchLRCSucceeded
    case contentBlockingLRCMissing
    case contentBlockingNoMatchInLRC
    case contentBlockingCompilationTaskPerformance(iterationCount: Int, timeBucketAggregation: Double)
}
