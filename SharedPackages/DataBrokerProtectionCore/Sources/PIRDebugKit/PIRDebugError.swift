//
//  PIRDebugError.swift
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

/// Errors surfaced by PIRDebugKit's configuration and rule providers.
public enum PIRDebugError: Error, LocalizedError {
    /// `operationAwaitTime` was configured with a negative value.
    case negativeOperationAwaitTime(TimeInterval)
    /// The embedded or injected privacy configuration data could not be parsed.
    case invalidPrivacyConfiguration
    /// The privacy configuration resource could not be located in the module bundle.
    case missingPrivacyConfigurationResource
    /// A rules source path could not be read.
    case unreadableRulesSource(URL)
    /// No opt-out context is available to continue (email confirmation) — call `optOut` first.
    case noPendingOptOut
    /// The profile query for an opt-out could not be resolved from the supplied profile.
    case ambiguousProfileQuery
    /// The remote rules endpoint returned "not modified" for the supplied ETag.
    case remoteRulesNotModified
    /// The remote rules endpoint returned an unexpected HTTP status.
    case remoteRulesServerError(statusCode: Int?)
    /// A remote response body could not be interpreted.
    case remoteRulesClientError

    public var errorDescription: String? {
        switch self {
        case .negativeOperationAwaitTime(let value):
            return "operationAwaitTime must be >= 0, got \(value)"
        case .invalidPrivacyConfiguration:
            return "Could not parse the privacy configuration data"
        case .missingPrivacyConfigurationResource:
            return "Could not locate macos-config.json in the PIRDebugKit bundle"
        case .unreadableRulesSource(let url):
            return "Could not read rules source at \(url.path)"
        case .noPendingOptOut:
            return "No pending opt-out to continue; run optOut(broker:profile:extractedProfile:) first"
        case .ambiguousProfileQuery:
            return "Could not resolve a single profile query for this extracted profile; pass a profile with the matching single name/address"
        case .remoteRulesNotModified:
            return "Remote rules unchanged (304 Not Modified)"
        case .remoteRulesServerError(let statusCode):
            return "Remote rules server error (status \(statusCode.map(String.init) ?? "unknown"))"
        case .remoteRulesClientError:
            return "Remote rules client error"
        }
    }
}
