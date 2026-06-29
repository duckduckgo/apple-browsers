//
//  DataBrokerProtectionDebugReadModels.swift
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

// Read-only JSON payloads exposed by the PIR debug HTTP server. All `Encodable`; the server encodes
// them with an ISO-8601 date strategy. Platform-agnostic so macOS and iOS hosts share them.
//
// Three data endpoints: a one-shot `DebugSnapshot` (current standing), a per-broker `DebugBrokerDetail`
// (drill-in), and a `[DebugBrokerEvent]` change stream (progress).

// MARK: - /api/snapshot

public struct DebugSnapshot: Encodable, Equatable {
    public let agentVersion: String
    /// Human-readable scheduler/queue state.
    public let schedulerState: String
    /// Last `NSBackgroundActivityScheduler` fire — NOT the last immediate scan.
    public let lastSchedulerTrigger: Date?
    public let auth: Auth
    public let brokerUpdate: BrokerUpdate
    public let brokers: [BrokerSummary]
    public let profileQueries: [ProfileQuery]

    public struct Auth: Encodable, Equatable {
        public let isAuthenticated: Bool
        public let hasAccessToken: Bool
        public let hasValidEntitlement: Bool
        public let environment: String
        public let endpointURL: String
    }

    public struct BrokerUpdate: Encodable, Equatable {
        public let mainConfigETag: String?
        public let lastSuccessfulCheck: Date?
    }

    public struct BrokerSummary: Encodable, Equatable {
        public let id: Int64?
        public let name: String
        public let url: String
        public let version: String
        public let parent: String?
        public let isRemoved: Bool
        public let profileQueryCount: Int
        public let matchCount: Int
        public let errorCount: Int
        public let lastScanDate: Date?
    }

    public struct ProfileQuery: Encodable, Equatable {
        public let id: Int64?
        public let firstName: String
        public let lastName: String
        public let middleName: String?
        public let suffix: String?
        public let city: String
        public let state: String
        public let street: String?
        public let zip: String?
        public let birthYear: Int
        public let age: Int
        public let phone: String?
        public let deprecated: Bool
    }
}

// MARK: - /api/brokers/{broker}

public struct DebugBrokerDetail: Encodable, Equatable {
    public let id: Int64?
    public let name: String
    public let url: String
    public let version: String
    public let parent: String?
    public let isRemoved: Bool
    /// Pretty-printed raw broker JSON definition (parse client-side).
    public let definition: String?
    public let profileQueries: [ProfileQueryDetail]

    public struct ProfileQueryDetail: Encodable, Equatable {
        public let profileQueryId: Int64
        public let scan: ScanState
        public let optOuts: [OptOutState]
    }

    public struct ScanState: Encodable, Equatable {
        public let preferredRunDate: Date?
        public let lastRunDate: Date?
        public let history: [DebugHistoryEvent]
    }

    public struct OptOutState: Encodable, Equatable {
        public let extractedProfileId: Int64?
        public let attemptCount: Int64
        public let createdDate: Date
        public let preferredRunDate: Date?
        public let lastRunDate: Date?
        public let submittedSuccessfullyDate: Date?
        public let removedDate: Date?
        public let history: [DebugHistoryEvent]
        public let extractedRecord: DebugExtractedRecord
    }
}

// MARK: - /api/events

/// A history event with its broker/profile-query owner, for the cross-broker progress stream.
public struct DebugBrokerEvent: Encodable, Equatable {
    public let broker: String
    public let profileQueryId: Int64
    public let extractedProfileId: Int64?
    public let type: String
    public let date: Date
    public var matchCount: Int?
    public var error: DebugError?
}

// MARK: - /api (self-describing index)

public struct DebugAPIIndex: Encodable, Equatable {
    public let endpoints: [Endpoint]

    public init(endpoints: [Endpoint]) {
        self.endpoints = endpoints
    }

    public struct Endpoint: Encodable, Equatable {
        public let path: String
        public let description: String

        public init(path: String, description: String) {
            self.path = path
            self.description = description
        }
    }
}

// MARK: - Shared

public struct DebugExtractedRecord: Encodable, Equatable {
    public let id: Int64?
    public let name: String?
    public let alternativeNames: [String]?
    public let addressFull: String?
    public let addresses: [String]?
    public let phoneNumbers: [String]?
    public let relatives: [String]?
    public let profileUrl: String?
    public let reportId: String?
    public let age: String?
    public let email: String?
    public let removedDate: Date?
}

public struct DebugHistoryEvent: Encodable, Equatable {
    public let type: String
    public let date: Date
    public var matchCount: Int?
    public var error: DebugError?
}

public struct DebugError: Encodable, Equatable {
    public let name: String
    public let code: Int
    public let description: String
}

// MARK: - /api/logs

/// One unified-log line, JSON-serialized by `/api/logs`. Produced by a platform `DebugLogReading`.
public struct DebugLogLine: Encodable, Equatable {
    public let timestamp: Date
    public let level: String
    public let category: String
    public let subsystem: String
    public let process: String
    public let message: String

    public init(timestamp: Date, level: String, category: String, subsystem: String, process: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.subsystem = subsystem
        self.process = process
        self.message = message
    }
}
