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

/// One entry on the dashboard's "Needs you" list: an opt-out whose broker page has a step only the user can do.
public struct AssistedOptOut: Codable, Equatable, Sendable {
    public struct DataBroker: Codable, Equatable, Sendable {
        public let name: String
        public let url: String

        public init(name: String, url: String) {
            self.name = name
            self.url = url
        }
    }

    /// What the dashboard shows for an entry. A running attempt tracks its own `AssistedAttemptPhase`,
    /// and `init(phase:isWindowKey:)` turns that into the state shown here.
    public enum State: String, Codable, Sendable {
        /// Not running. Either the user hasn't started it yet, or they just did and the app is about to take over.
        case waiting
        /// The app is filling in the broker's opt-out form.
        case agentInControl
        /// The broker page is waiting for the user, but its window isn't in front, so the dashboard asks them to come back.
        case needsUser
        /// The broker page is waiting for the user and its window is in front, so they are working on it.
        case userInControl
        /// The opt-out request was sent to the broker.
        case submitted
    }

    /// Progress through the broker's opt-out steps, shown while the attempt runs. `index` counts from zero.
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
    public let state: State
    public let step: Step?

    public init(id: String, dataBroker: DataBroker, state: State, step: Step? = nil) {
        self.id = id
        self.dataBroker = dataBroker
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

/// Where an assisted attempt is, as tracked by `AssistedOptOutSession`. Unlike `AssistedOptOut.State`,
/// it doesn't know whether the user is looking at the window, so the dashboard state combines the two.
public enum AssistedAttemptPhase: Equatable, Sendable {
    /// The window shows the introduction and waits for the user to press start.
    case ready
    /// The user pressed start and the app hasn't run the first opt-out action yet.
    case queued
    /// The app is running the broker's opt-out actions on the page.
    case agentInControl
    /// The run reached a `userAssist` action, such as a CAPTCHA, and is paused until the user finishes it.
    case userTurn
    /// The run finished and sent the opt-out request.
    case submitted
}

public extension AssistedOptOut.State {
    /// `ready` and `userTurn` both wait on the user. If the window is in front they are already on it (`userInControl`),
    /// otherwise the dashboard has to bring them back (`needsUser`).
    init(phase: AssistedAttemptPhase, isWindowKey: Bool) {
        switch phase {
        case .ready, .userTurn: self = isWindowKey ? .userInControl : .needsUser
        case .queued: self = .waiting
        case .agentInControl: self = .agentInControl
        case .submitted: self = .submitted
        }
    }
}
