//
//  PIRResults.swift
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
import DataBrokerProtectionCore

/// One extracted profile serialized with the stable IDs needed to drive a later opt-out
/// (possibly in a different process — `DebugHelper.stableId` is deterministic).
public struct PIRExtractedProfileRecord: Codable, Sendable, Equatable {
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let profileQueryLabel: String
    /// The extracted profile, carrying its stable `id`.
    public let extractedProfile: ExtractedProfile

    public init(brokerId: Int64,
                profileQueryId: Int64,
                profileQueryLabel: String,
                extractedProfile: ExtractedProfile) {
        self.brokerId = brokerId
        self.profileQueryId = profileQueryId
        self.profileQueryLabel = profileQueryLabel
        self.extractedProfile = extractedProfile
    }
}

/// Result of ``PIRDebugSession/scan(broker:profile:)``.
public struct PIRScanResult: Codable, Sendable, Equatable {

    public enum QueryOutcome: String, Codable, Sendable {
        case matches
        case noMatch
        case error
    }

    public struct QueryStatus: Codable, Sendable, Equatable {
        public let profileQueryId: Int64
        public let profileQueryLabel: String
        public let outcome: QueryOutcome
        public let extractedProfileCount: Int
        public let error: String?

        public init(profileQueryId: Int64,
                    profileQueryLabel: String,
                    outcome: QueryOutcome,
                    extractedProfileCount: Int,
                    error: String?) {
            self.profileQueryId = profileQueryId
            self.profileQueryLabel = profileQueryLabel
            self.outcome = outcome
            self.extractedProfileCount = extractedProfileCount
            self.error = error
        }
    }

    public let brokerName: String
    public let brokerURL: String
    public let brokerVersion: String
    public let brokerId: Int64
    public let queryStatuses: [QueryStatus]
    public let extractedProfiles: [PIRExtractedProfileRecord]
    public let duration: TimeInterval
    public let eventCount: Int

    public init(brokerName: String,
                brokerURL: String,
                brokerVersion: String,
                brokerId: Int64,
                queryStatuses: [QueryStatus],
                extractedProfiles: [PIRExtractedProfileRecord],
                duration: TimeInterval,
                eventCount: Int) {
        self.brokerName = brokerName
        self.brokerURL = brokerURL
        self.brokerVersion = brokerVersion
        self.brokerId = brokerId
        self.queryStatuses = queryStatuses
        self.extractedProfiles = extractedProfiles
        self.duration = duration
        self.eventCount = eventCount
    }
}

/// Result of ``PIRDebugSession/optOut(broker:profile:extractedProfile:)`` (and the
/// email-confirmation continuation).
public struct PIROptOutResult: Codable, Sendable, Equatable {
    public let brokerName: String
    public let brokerURL: String
    public let brokerVersion: String
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let profileQueryLabel: String
    public let extractedProfileId: Int64?
    /// Last stage detail observed (from the final recorded debug event), for diagnosis.
    public let lastStage: String?
    public let success: Bool
    public let awaitingEmailConfirmation: Bool
    public let error: String?
    public let duration: TimeInterval
    public let eventCount: Int

    public init(brokerName: String,
                brokerURL: String,
                brokerVersion: String,
                brokerId: Int64,
                profileQueryId: Int64,
                profileQueryLabel: String,
                extractedProfileId: Int64?,
                lastStage: String?,
                success: Bool,
                awaitingEmailConfirmation: Bool,
                error: String?,
                duration: TimeInterval,
                eventCount: Int) {
        self.brokerName = brokerName
        self.brokerURL = brokerURL
        self.brokerVersion = brokerVersion
        self.brokerId = brokerId
        self.profileQueryId = profileQueryId
        self.profileQueryLabel = profileQueryLabel
        self.extractedProfileId = extractedProfileId
        self.lastStage = lastStage
        self.success = success
        self.awaitingEmailConfirmation = awaitingEmailConfirmation
        self.error = error
        self.duration = duration
        self.eventCount = eventCount
    }
}
