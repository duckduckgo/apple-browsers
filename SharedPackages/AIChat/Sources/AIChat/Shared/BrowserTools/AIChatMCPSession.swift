//
//  AIChatMCPSession.swift
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

/// Per-owner-tab MCP session state, established by `initialize` and completed by
/// `notifications/initialized`.
public struct AIChatMCPSession: Equatable, Sendable {

    /// Tools traffic is refused with `not_initialized` until the FE confirms it is ready.
    public private(set) var isInitialized = false

    /// What the client declared. Recorded for diagnostics; native always answers with its own.
    public private(set) var protocolVersion: String?

    public private(set) var supportsElicitationForm = false

    public init() {}

    /// Re-initializing clears readiness — a client that hands over a fresh handshake has to
    /// complete it again before tools traffic resumes.
    public mutating func applyInitialize(protocolVersion: String?, supportsElicitationForm: Bool) {
        self.protocolVersion = protocolVersion
        self.supportsElicitationForm = supportsElicitationForm
        self.isInitialized = false
    }

    public mutating func markInitialized() {
        isInitialized = true
    }
}

/// Sessions keyed by Duck.ai owner tab, so a sidebar and the tab it is docked to share one.
///
/// Ownership sits here rather than on the sidebar's view model so `initialize` can succeed even
/// when it races the sidebar being presented.
@MainActor
public final class AIChatMCPSessionStore {

    private var sessions: [String: AIChatMCPSession] = [:]

    public init() {}

    public func session(forOwnerTabID ownerTabID: String) -> AIChatMCPSession? {
        sessions[ownerTabID]
    }

    public func applyInitialize(forOwnerTabID ownerTabID: String,
                                protocolVersion: String?,
                                supportsElicitationForm: Bool) {
        var session = sessions[ownerTabID] ?? AIChatMCPSession()
        session.applyInitialize(protocolVersion: protocolVersion, supportsElicitationForm: supportsElicitationForm)
        sessions[ownerTabID] = session
    }

    /// Creates the session if missing, so a front end whose `initialize` timed out on its side can
    /// still recover. It just has no elicitation capability.
    public func markInitialized(forOwnerTabID ownerTabID: String) {
        var session = sessions[ownerTabID] ?? AIChatMCPSession()
        session.markInitialized()
        sessions[ownerTabID] = session
    }

    public func removeSession(forOwnerTabID ownerTabID: String) {
        sessions.removeValue(forKey: ownerTabID)
    }

    /// Drops every session — used when data is burned.
    public func removeAllSessions() {
        sessions.removeAll()
    }
}
