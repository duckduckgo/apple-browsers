//
//  BackgroundTaskEvent.swift
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

import Foundation

public struct BackgroundTaskEvent: Identifiable, Sendable {
    public enum EventType: String, Codable, CaseIterable, Sendable {
        case started
        case completed
        case terminated
    }

    public struct Metadata: Codable, Sendable {
        public let duration: TimeInterval

        public init(durationInMs: TimeInterval) {
            self.duration = durationInMs
        }
    }

    public enum Error: Swift.Error {
        case invalidEventType
    }

    public let id: Int64?
    public let sessionId: String
    public let eventType: EventType
    public let timestamp: Date
    public let metadata: Metadata?

    public init(id: Int64? = nil, sessionId: String, eventType: EventType, timestamp: Date = Date(), metadata: Metadata? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.eventType = eventType
        self.timestamp = timestamp
        self.metadata = metadata
    }

    public static func calculateSessionMetrics(from events: [BackgroundTaskEvent],
                                               orphanedThreshold: TimeInterval,
                                               durationRange: ClosedRange<Double>? = nil,
                                               now: Date = Date()) -> BackgroundTaskSessionMetrics {
        guard !events.isEmpty else {
            return BackgroundTaskSessionMetrics(started: 0,
                                                completed: 0,
                                                terminated: 0,
                                                orphaned: 0,
                                                durations: [])
        }

        let sessionGroups = Dictionary(grouping: events, by: \.sessionId)

        var startedCount = 0
        var completedCount = 0
        var terminatedCount = 0
        var orphanedCount = 0
        var durations: [Double] = []

        for (_, sessionEvents) in sessionGroups where sessionEvents[.started] != nil {
            startedCount += 1

            if let endEvent = sessionEvents[.completed] ?? sessionEvents[.terminated] {
                if endEvent.eventType == .completed {
                    completedCount += 1
                } else {
                    terminatedCount += 1
                }

                if let durationMs = endEvent.metadata?.duration,
                   durationRange?.contains(durationMs) ?? true {
                    durations.append(durationMs)
                }
            } else if let startEvent = sessionEvents[.started],
                      now.timeIntervalSince(startEvent.timestamp) > orphanedThreshold {
                orphanedCount += 1
            }
        }

        return BackgroundTaskSessionMetrics(started: startedCount,
                                            completed: completedCount,
                                            terminated: terminatedCount,
                                            orphaned: orphanedCount,
                                            durations: durations)
    }
}

public struct BackgroundTaskSessionMetrics: Sendable {
    public let started: Int
    public let completed: Int
    public let terminated: Int
    public let orphaned: Int
    public let durations: [Double]

    public init(started: Int, completed: Int, terminated: Int, orphaned: Int, durations: [Double]) {
        self.started = started
        self.completed = completed
        self.terminated = terminated
        self.orphaned = orphaned
        self.durations = durations
    }

    public var durationMinMs: Double {
        durations.min() ?? 0
    }

    public var durationMaxMs: Double {
        durations.max() ?? 0
    }

    public var durationMedianMs: Double {
        durations.median()
    }
}

extension BackgroundTaskSessionMetrics {
    public struct Session: Sendable {
        public let start: BackgroundTaskEvent
        public let end: BackgroundTaskEvent?

        public init(start: BackgroundTaskEvent, end: BackgroundTaskEvent?) {
            self.start = start
            self.end = end
        }

        public var isCompleted: Bool {
            end?.eventType == .completed
        }

        public var isTerminated: Bool {
            end?.eventType == .terminated
        }

        public var isInProgress: Bool {
            end == nil
        }

        public var durationMs: Double? {
            end?.metadata?.duration
        }
    }

    public static func lastBackgroundTaskSession(from events: [BackgroundTaskEvent]) -> Session? {
        guard !events.isEmpty,
              let lastStart = events.filter({ $0.eventType == .started }).max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        let sessionEnd = events
            .filter { $0.sessionId == lastStart.sessionId && ($0.eventType == .completed || $0.eventType == .terminated) }
            .max(by: { $0.timestamp < $1.timestamp })

        return Session(start: lastStart, end: sessionEnd)
    }
}

extension Array where Element == BackgroundTaskEvent {
    public subscript(_ eventType: BackgroundTaskEvent.EventType) -> Element? {
        first { $0.eventType == eventType }
    }
}

private extension Array where Element == Double {
    func median() -> Double {
        guard !isEmpty else { return 0 }

        let sorted = self.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            return Double((sorted[count / 2 - 1] + sorted[count / 2]) / 2)
        } else {
            return Double(sorted[count / 2])
        }
    }
}
