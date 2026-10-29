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
public struct PIRAssistItemID: Hashable, Sendable {
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

    static let turnstileTokenField = "cf-turnstile-response"

    var tokenSelector: String? {
        switch self {
        case .turnstile: return "input[name='\(Self.turnstileTokenField)']"
        case .recaptcha: return "textarea[name='g-recaptcha-response']"
        case .managedChallenge, .generic: return nil
        }
    }

    /// What the dashboard says the user has to do.
    var shortInstruction: String {
        switch self {
        case .recaptcha: return "Check \u{201C}I\u{2019}m not a robot\u{201D} to continue"
        case .turnstile, .managedChallenge, .generic: return "Complete the security check to continue"
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

/// An assisted opt-out that reached the end of the broker's form.
public struct PIRAssistSubmission: Equatable, Sendable {
    /// The broker still has to email a confirmation link, which PIR follows on its own.
    public let awaitsEmailConfirmation: Bool

    public init(awaitsEmailConfirmation: Bool) {
        self.awaitsEmailConfirmation = awaitsEmailConfirmation
    }
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
    @Published public private(set) var submission: PIRAssistSubmission?

    public var steps: [PIRAssistStep] { checklist?.steps(userTurn: userTurn) ?? [] }

    /// One line for the dashboard: what the user has to do, or how far the request has got.
    public var needsYouDetail: String? {
        if let userTurn { return userTurn.shortInstruction }
        guard let checklist, checklist.items.indices.contains(checklist.currentIndex) else { return nil }
        return "Step \(checklist.currentIndex + 1) of \(checklist.items.count) \u{00B7} \(checklist.items[checklist.currentIndex])"
    }

    var onUserConfirmedDone: (() -> Void)?
    var onStop: (() -> Void)?

    public init(id: PIRAssistItemID, brokerName: String, brokerURL: String, webView: WKWebView) {
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

    public func update(checklist: PIRAssistChecklist) {
        guard checklist != self.checklist else { return }
        self.checklist = checklist
    }

    public func didSubmit(_ submission: PIRAssistSubmission) {
        self.submission = submission
    }

    public func setUserTurn(_ kind: PIRAssistUserTurnKind?) {
        guard kind != userTurn else { return }
        userTurn = kind
        PIRAssistCenter.shared.userTurnDidChange(in: self)
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

    public enum State: String, Sendable {
        case running
        case needsYou
    }

    public weak var presenter: PIRAssistPresenting?
    /// Called with true while any session is paused for the user, so the queue can make room for other jobs.
    public var onUserTurnChange: ((PIRAssistItemID, Bool) -> Void)?

    private(set) var sessions: [PIRAssistItemID: PIRAssistSession] = [:]
    private var openRequests: Set<PIRAssistItemID> = []

    init() {}

    public func state(of id: PIRAssistItemID) -> State? {
        guard let session = sessions[id] else { return nil }
        return session.userTurn == nil ? .running : .needsYou
    }

    public var runningItems: [PIRNeedsYou.RunningItem] {
        sessions.values.map {
            PIRNeedsYou.RunningItem(id: $0.id, brokerName: $0.brokerName, brokerURL: $0.brokerURL,
                                    state: $0.userTurn == nil ? .running : .needsYou, detail: $0.needsYouDetail)
        }
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
    }

    func unregister(_ session: PIRAssistSession) {
        guard sessions[session.id] === session else { return }
        sessions[session.id] = nil
        presenter?.dismiss(session)
        onUserTurnChange?(session.id, false)
    }

    func userTurnDidChange(in session: PIRAssistSession) {
        onUserTurnChange?(session.id, session.userTurn != nil)
    }
}
#endif
