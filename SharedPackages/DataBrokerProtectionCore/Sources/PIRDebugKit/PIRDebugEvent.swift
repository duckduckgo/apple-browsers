//
//  PIRDebugEvent.swift
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

/// A UI-agnostic, `Codable` debug event emitted by a ``PIRDebugSession``.
///
/// The `timestamp` is serialized as an ISO-8601 string. `kind` maps 1:1 from the engine's
/// `DebugEventKind`.
public struct PIRDebugEvent: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable {
        case actionPayload
        case actionResponse
        case actionRetry
        case wait
        case history

        init(_ kind: DebugEventKind) {
            switch kind {
            case .actionPayload: self = .actionPayload
            case .actionResponse: self = .actionResponse
            case .actionRetry: self = .actionRetry
            case .wait: self = .wait
            case .history: self = .history
            }
        }
    }

    public let timestamp: Date
    public let profileQueryLabel: String
    public let kind: Kind
    public let actionType: String?
    public let details: String

    public init(timestamp: Date = Date(),
                profileQueryLabel: String,
                kind: Kind,
                actionType: String?,
                details: String) {
        self.timestamp = timestamp
        self.profileQueryLabel = profileQueryLabel
        self.kind = kind
        self.actionType = actionType
        self.details = details
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case profileQueryLabel
        case kind
        case actionType
        case details
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        self.timestamp = Self.iso8601.date(from: timestampString) ?? Date(timeIntervalSince1970: 0)
        self.profileQueryLabel = try container.decode(String.self, forKey: .profileQueryLabel)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.actionType = try container.decodeIfPresent(String.self, forKey: .actionType)
        self.details = try container.decode(String.self, forKey: .details)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.iso8601.string(from: timestamp), forKey: .timestamp)
        try container.encode(profileQueryLabel, forKey: .profileQueryLabel)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(actionType, forKey: .actionType)
        try container.encode(details, forKey: .details)
    }
}
