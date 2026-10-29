//
//  PIRAssist.swift
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

#if os(macOS) && DEBUG
import Combine
import Foundation
import WebKit

/// Identifies a held opt-out, or a held scan when `extractedProfileId` is nil.
public struct PIRAssistItemID: Hashable, Codable, Sendable {
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let extractedProfileId: Int64?

    public init(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?) {
        self.brokerId = brokerId
        self.profileQueryId = profileQueryId
        self.extractedProfileId = extractedProfileId
    }

    public init(_ optOut: PIRAssistedOptOut) {
        self.init(brokerId: optOut.brokerId, profileQueryId: optOut.profileQueryId, extractedProfileId: optOut.extractedProfileId)
    }
}

public enum PIRAssistUserTurnKind: String, Codable, Sendable {
    case turnstile
    case recaptcha
    case managedChallenge
    case generic

    var tokenSelector: String? {
        switch self {
        case .turnstile: return "input[name='cf-turnstile-response']"
        case .recaptcha: return "textarea[name='g-recaptcha-response']"
        case .managedChallenge, .generic: return nil
        }
    }
}

struct PIRAssistModeParams: Encodable {
    let enabled: Bool
}

struct PIRUserTurnStartedParams: Encodable {
    let kind: PIRAssistUserTurnKind
    let tokenSelector: String?
}

struct PIRUserTurnEndedParams: Encodable {
    enum Reason: String, Encodable {
        case completed
        case userConfirmed
        case stopped
    }

    let reason: Reason
}

public enum PIRAssistStepState: Equatable, Sendable {
    case done
    case running
    case upcoming
    /// Not reached yet, but the broker's flow says the user will have to do it.
    case needsUserLater
    case userTurn
}

public struct PIRAssistStep: Equatable, Sendable {
    public let title: String
    public let state: PIRAssistStepState
}

/// One running assisted job: its web view, where it is in the broker's flow, and whether it is waiting for the user.
@MainActor
public final class PIRAssistSession: ObservableObject, Identifiable {
    public let id: PIRAssistItemID
    public let brokerName: String
    public let brokerURL: String
    public let webView: WKWebView

    @Published public private(set) var checklist: PIRAssistChecklist?
    @Published public private(set) var userTurn: PIRAssistUserTurnKind?

    public var steps: [PIRAssistStep] { checklist?.steps(userTurn: userTurn) ?? [] }

    var onUserConfirmedDone: (() -> Void)?
    var onStop: (() -> Void)?

    init(id: PIRAssistItemID, brokerName: String, brokerURL: String, webView: WKWebView) {
        self.id = id
        self.brokerName = brokerName
        self.brokerURL = brokerURL
        self.webView = webView
    }

    public func userConfirmedDone() {
        onUserConfirmedDone?()
    }

    public func stop() {
        onStop?()
    }

    func update(checklist: PIRAssistChecklist) {
        guard checklist != self.checklist else { return }
        self.checklist = checklist
    }

    func setUserTurn(_ kind: PIRAssistUserTurnKind?) {
        guard kind != userTurn else { return }
        userTurn = kind
        PIRAssistCenter.shared.sessionStateDidChange()
    }
}

/// Shows sessions to the user. The agent implements it with the "Removing you from…" window.
@MainActor
public protocol PIRAssistPresenting: AnyObject {
    func present(_ session: PIRAssistSession)
    func dismiss(_ session: PIRAssistSession)
}

/// Tracks the assisted jobs running in this process and which ones the user asked to see.
@MainActor
public final class PIRAssistCenter {
    public static let shared = PIRAssistCenter()

    public enum State: String, Codable, Sendable {
        /// Running on its own; the user doesn't need to do anything.
        case running
        /// Paused until the user solves a challenge.
        case needsYou
    }

    public weak var presenter: PIRAssistPresenting?
    /// Called whenever a session starts, ends or changes whether it needs the user.
    public var onChange: (() -> Void)?
    /// Called with true while any session is paused for the user, so the queue can make room for other jobs.
    public var onUserTurnChange: ((PIRAssistItemID, Bool) -> Void)?

    private(set) var sessions: [PIRAssistItemID: PIRAssistSession] = [:]
    private var openRequests: Set<PIRAssistItemID> = []

    init() {}

    public func state(of id: PIRAssistItemID) -> State? {
        guard let session = sessions[id] else { return nil }
        return session.userTurn == nil ? .running : .needsYou
    }

    /// Shows the item's window now if it is running, or as soon as it starts.
    public func open(_ id: PIRAssistItemID) {
        if let session = sessions[id] {
            presenter?.present(session)
        } else {
            openRequests.insert(id)
        }
    }

    func register(_ session: PIRAssistSession) {
        sessions[session.id] = session
        if openRequests.remove(session.id) != nil {
            presenter?.present(session)
        }
        onChange?()
    }

    func unregister(_ session: PIRAssistSession) {
        guard sessions[session.id] === session else { return }
        sessions[session.id] = nil
        presenter?.dismiss(session)
        onUserTurnChange?(session.id, false)
        onChange?()
    }

    func sessionStateDidChange() {
        for session in sessions.values {
            onUserTurnChange?(session.id, session.userTurn != nil)
        }
        onChange?()
    }
}
#endif
