//
//  AssistedOptOut.swift
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

/// A Needs you row in the PIR dashboard: one opt-out for a broker enabled for user assistance.
public struct AssistedOptOut: Codable, Equatable, Sendable {
    public struct DataBroker: Codable, Equatable, Sendable {
        public let name: String
        public let url: String

        public init(name: String, url: String) {
            self.name = name
            self.url = url
        }
    }

    public enum State: String, Codable, Sendable {
        case waiting
        case agentInControl
        case needsUser
        case userInControl
        case submitted
    }

    public struct Step: Codable, Equatable, Sendable {
        public let index: Int
        public let count: Int
        public let title: String

        public init(index: Int, count: Int, title: String) {
            self.index = index
            self.count = count
            self.title = title
        }
    }

    public let id: String
    public let dataBroker: DataBroker
    public let recordCount: Int
    public let state: State
    public let step: Step?

    public init(id: String, dataBroker: DataBroker, recordCount: Int = 1, state: State, step: Step? = nil) {
        self.id = id
        self.dataBroker = dataBroker
        self.recordCount = recordCount
        self.state = state
        self.step = step
    }
}

public struct AssistedOptOutList: Codable, Equatable, Sendable {
    public let optOuts: [AssistedOptOut]

    public init(optOuts: [AssistedOptOut]) {
        self.optOuts = optOuts
    }
}

/// Identifies an assisted opt-out, so starting the same one again reopens its attempt.
public struct AssistedOptOutID: Hashable, Sendable, CustomStringConvertible {
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let extractedProfileId: Int64

    public init(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) {
        self.brokerId = brokerId
        self.profileQueryId = profileQueryId
        self.extractedProfileId = extractedProfileId
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int64($0) }
        guard parts.count == 3 else { return nil }
        self.init(brokerId: parts[0], profileQueryId: parts[1], extractedProfileId: parts[2])
    }

    public var description: String { "\(brokerId)-\(profileQueryId)-\(extractedProfileId)" }
}

/// Where an assisted attempt is, from the user's point of view.
public enum AssistedAttemptPhase: Equatable, Sendable {
    case ready
    case queued
    case agentInControl
    case userTurn
    case submitted
}

public extension AssistedOptOut.State {
    init(phase: AssistedAttemptPhase, isWindowKey: Bool) {
        switch phase {
        case .ready: self = isWindowKey ? .userInControl : .needsUser
        case .queued: self = .waiting
        case .agentInControl: self = .agentInControl
        case .userTurn: self = isWindowKey ? .userInControl : .needsUser
        case .submitted: self = .submitted
        }
    }
}

/// The ordered step titles shown for an opt-out, taken from the distinct `step` labels in its actions,
/// including those inside conditions, in order of first appearance.
public struct AssistedOptOutSteps: Equatable, Sendable {
    public let titles: [String]

    public init(titles: [String]) {
        self.titles = titles
    }

    public init(actions: [Action]) {
        var titles: [String] = []
        for label in actions.flatMap(Self.labels(in:)) where !titles.contains(label) {
            titles.append(label)
        }
        self.titles = titles
    }

    public func index(of action: Action) -> Int? {
        action.step.flatMap { titles.firstIndex(of: $0) }
    }

    private static func labels(in action: Action) -> [String] {
        guard let json = action.json, let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        return labels(in: object)
    }

    private static func labels(in object: [String: Any]) -> [String] {
        let own = (object["step"] as? String).map { [$0] } ?? []
        let nested = (object["actions"] as? [[String: Any]])?.flatMap(labels(in:)) ?? []
        return own + nested
    }
}
