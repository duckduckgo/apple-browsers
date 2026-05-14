//
//  AIChatSessionStore.swift
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

import AIChat
import Combine
import Foundation
import FeatureFlags
import PrivacyConfig

typealias TabIdentifier = String
typealias AIChatStatesByTab = [TabIdentifier: AIChatState]
typealias AIChatSessionsByTab = [TabIdentifier: AIChatSession]

/// Registry and lifecycle manager for per-tab AI Chat sessions.
protocol AIChatSessionStoring: AnyObject {

    /// All active sessions keyed by tab identifier.
    var sessions: AIChatSessionsByTab { get }

    /// Publishes whenever `sessions` changes.
    var sessionsPublisher: AnyPublisher<AIChatSessionsByTab, Never> { get }

    /// Convenience: states extracted from sessions (used for serialization).
    var statesByTab: AIChatStatesByTab { get }

    /// Returns the existing session for a tab, or creates a new one.
    func getOrCreateSession(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSession

    /// Tears down the session for a tab and removes it if state persistence is disabled.
    func endSession(for tabID: TabIdentifier)

    /// Removes sessions whose tab identifiers are no longer present in `currentTabIDs`.
    func removeOrphanedSessions(currentTabIDs: [TabIdentifier])

    /// Immediately removes the session for a tab without teardown.
    func removeSession(for tabID: TabIdentifier)

    @discardableResult
    func expireSessionIfNeeded(for tabID: TabIdentifier) -> Bool

    /// Snapshots live VC URLs into their states, then returns the states for serialization.
    func statesForSerialization() -> AIChatStatesByTab

    /// Restores sessions from previously saved states.
    func restoreState(_ statesByTab: AIChatStatesByTab)
}

final class AIChatSessionStore: AIChatSessionStoring {

    private let featureFlagger: FeatureFlagger

    @Published private(set) var sessions: AIChatSessionsByTab

    var sessionsPublisher: AnyPublisher<AIChatSessionsByTab, Never> {
        $sessions.dropFirst().eraseToAnyPublisher()
    }

    var statesByTab: AIChatStatesByTab {
        sessions.mapValues { $0.state }
    }

    private var shouldKeepSession: Bool {
        featureFlagger.isFeatureOn(.aiChatKeepSession)
    }

    init(sessions: AIChatSessionsByTab? = nil,
         featureFlagger: FeatureFlagger) {
        self.sessions = sessions ?? [:]
        self.featureFlagger = featureFlagger
    }

    func getOrCreateSession(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSession {
        if let existing = sessions[tabID] {
            if existing.state.isSessionExpired {
                existing.tearDown(persistingState: shouldKeepSession)
                sessions.removeValue(forKey: tabID)
            } else {
                return existing
            }
        }

        let state = AIChatState()
        let session = AIChatSession(state: state, burnerMode: burnerMode)
        sessions[tabID] = session
        return session
    }

    func endSession(for tabID: TabIdentifier) {
        sessions[tabID]?.tearDown(persistingState: shouldKeepSession)

        if !shouldKeepSession {
            sessions.removeValue(forKey: tabID)
        }
    }

    func removeOrphanedSessions(currentTabIDs: [TabIdentifier]) {
        let tabIDsForRemoval = Set(sessions.keys).subtracting(currentTabIDs)

        for tabID in tabIDsForRemoval {
            sessions[tabID]?.tearDown(persistingState: false)
            sessions.removeValue(forKey: tabID)
        }
    }

    func restoreState(_ statesByTab: AIChatStatesByTab) {
        removeOrphanedSessions(currentTabIDs: [])
        self.sessions = statesByTab.mapValues { AIChatSession(state: $0, burnerMode: .regular) }
    }

    func removeSession(for tabID: TabIdentifier) {
        sessions.removeValue(forKey: tabID)
    }

    @discardableResult
    func expireSessionIfNeeded(for tabID: TabIdentifier) -> Bool {
        guard let session = sessions[tabID],
              session.state.isSessionExpired else {
            return false
        }

        session.tearDown(persistingState: shouldKeepSession)
        sessions.removeValue(forKey: tabID)
        return true
    }

    func statesForSerialization() -> AIChatStatesByTab {
        for (_, session) in sessions {
            session.snapshotCurrentURL()
        }
        return statesByTab
    }
}
