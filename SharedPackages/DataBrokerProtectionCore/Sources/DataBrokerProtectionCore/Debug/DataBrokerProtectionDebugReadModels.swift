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

public enum DataBrokerProtectionDebugServerDefaults {
    public static let defaultPort: UInt16 = 8474
}

// MARK: - /api/runtime-status

public struct DBPDebugIOSRuntimeStatus: Encodable, Equatable {
    public let profileState: String
    public let vault: VaultStatus

    public init(profileState: String, vault: VaultStatus) {
        self.profileState = profileState
        self.vault = vault
    }

    public struct VaultStatus: Encodable, Equatable {
        public let initialized: Bool
        public let lastInitReason: String?

        public init(initialized: Bool, lastInitReason: String?) {
            self.initialized = initialized
            self.lastInitReason = lastInitReason
        }
    }
}

// MARK: - /api/resource-usage

public struct DBPDebugResourceUsage: Encodable, Equatable, Sendable {
    public let isMonitoring: Bool
    public let latestSample: Sample?

    public init(isMonitoring: Bool, latestSample: Sample?) {
        self.isMonitoring = isMonitoring
        self.latestSample = latestSample
    }

    public struct Sample: Encodable, Equatable, Sendable {
        public struct CPUUsage: Encodable, Equatable, Sendable {
            public let totalTimeSeconds: TimeInterval
            public let agentTimeSeconds: TimeInterval
            public let webContentTimeSeconds: TimeInterval
            public let averagePercent: Double

            public init(totalTimeSeconds: TimeInterval,
                        agentTimeSeconds: TimeInterval,
                        webContentTimeSeconds: TimeInterval,
                        averagePercent: Double) {
                self.totalTimeSeconds = totalTimeSeconds
                self.agentTimeSeconds = agentTimeSeconds
                self.webContentTimeSeconds = webContentTimeSeconds
                self.averagePercent = averagePercent
            }
        }

        public struct MemoryUsage: Encodable, Equatable, Sendable {
            public struct Agent: Encodable, Equatable, Sendable {
                public let footprintBytes: UInt64
                public let peakFootprintBytes: UInt64

                public init(footprintBytes: UInt64, peakFootprintBytes: UInt64) {
                    self.footprintBytes = footprintBytes
                    self.peakFootprintBytes = peakFootprintBytes
                }
            }

            public struct WebContent: Encodable, Equatable, Sendable {
                public let footprintBytes: UInt64?
                public let peakFootprintBytes: UInt64?
                public let processCount: Int?

                public init(footprintBytes: UInt64?, peakFootprintBytes: UInt64?, processCount: Int?) {
                    self.footprintBytes = footprintBytes
                    self.peakFootprintBytes = peakFootprintBytes
                    self.processCount = processCount
                }
            }

            public let agent: Agent
            public let webContent: WebContent
            public let hadCriticalPressure: Bool

            public init(agent: Agent, webContent: WebContent, hadCriticalPressure: Bool) {
                self.agent = agent
                self.webContent = webContent
                self.hadCriticalPressure = hadCriticalPressure
            }
        }

        public let reportedAt: Date
        public let cpu: CPUUsage
        public let memory: MemoryUsage

        public init(reportedAt: Date, cpu: CPUUsage, memory: MemoryUsage) {
            self.reportedAt = reportedAt
            self.cpu = cpu
            self.memory = memory
        }
    }
}

// MARK: - /api

public struct DebugSnapshot: Encodable, Equatable {
    public let agentVersion: String
    public let schedulerState: String
    public let lastSchedulerTrigger: Date?
    public let environment: String
    public let endpointURL: String
    public let brokerUpdate: BrokerUpdate
    public let brokers: [BrokerSummary]
    public let profileQueries: [DebugProfileQuery]

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
}

// MARK: - /api/brokers/{broker}

public struct DebugBrokerDetail: Encodable, Equatable {
    public let id: Int64?
    public let name: String
    public let url: String
    public let version: String
    public let parent: String?
    public let isRemoved: Bool
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

public struct DebugProfileQuery: Encodable, Equatable {
    public let id: Int64?
    public let deprecated: Bool
    public let addressCount: Int
}

public struct DebugExtractedRecord: Encodable, Equatable {
    public let id: Int64?
    public let reportId: String?
    public let removedDate: Date?
    public let hasName: Bool
    public let alternativeNameCount: Int
    public let addressCount: Int
    public let phoneCount: Int
    public let relativeCount: Int
    public let hasAge: Bool
    public let hasEmail: Bool
    public let hasProfileURL: Bool
}

// MARK: - /api/events

public struct DebugBrokerEvent: Encodable, Equatable {
    public let broker: String
    public let profileQueryId: Int64
    public let extractedProfileId: Int64?
    public let type: String
    public let date: Date
    public var matchCount: Int?
    public var error: DebugError?
}

public struct DebugAPIResponse: Encodable, Equatable {
    public let snapshot: DebugSnapshot
    public let endpoints: [Endpoint]

    public init(snapshot: DebugSnapshot, endpoints: [Endpoint]) {
        self.snapshot = snapshot
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
