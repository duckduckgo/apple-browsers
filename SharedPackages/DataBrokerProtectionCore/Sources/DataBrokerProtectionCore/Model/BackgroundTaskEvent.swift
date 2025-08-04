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
}

extension Array where Element == BackgroundTaskEvent {
    public subscript(_ eventType: BackgroundTaskEvent.EventType) -> Element? {
        first { $0.eventType == eventType }
    }
}
