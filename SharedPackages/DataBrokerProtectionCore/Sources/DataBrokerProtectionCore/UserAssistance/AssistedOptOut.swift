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
        case .ready, .userTurn: self = isWindowKey ? .userInControl : .needsUser
        case .queued: self = .waiting
        case .agentInControl: self = .agentInControl
        case .submitted: self = .submitted
        }
    }
}
