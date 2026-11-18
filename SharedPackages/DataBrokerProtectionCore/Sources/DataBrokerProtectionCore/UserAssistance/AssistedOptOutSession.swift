//
//  AssistedOptOutSession.swift
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

import Combine
import Foundation
import WebKit

@MainActor
/// One assisted opt-out from the moment its window opens until it closes. The window observes it, and the running
/// opt-out reports each action to it so it knows whose turn it is on the broker page.
public final class AssistedOptOutSession: ObservableObject, OptOutAssistanceObserving, Identifiable {
    public let id: AssistedOptOutID
    public let broker: AssistedOptOut.DataBroker
    public let steps: AssistedOptOutSteps

    @Published public private(set) var phase: AssistedAttemptPhase = .ready
    @Published public private(set) var currentStepIndex = 0
    @Published public private(set) var webView: WKWebView?

    /// Whether the attempt's window is in front, meaning the user is looking at it.
    @Published public var isWindowKey = false

    public var onBeginRequested: ((AssistedOptOutSession) -> Void)?
    public var onUserTurnStarted: ((AssistedOptOutSession) -> Void)?
    public var onCancelRequested: ((AssistedOptOutSession) -> Void)?

    private let instrumentation: AssistedOptOutInstrumentation?
    private let now: () -> Date
    private var startedAt: Date?
    private var firstUserTurnRecorded = false
    private var userTurnStartedAt: Date?
    private var userTurnDuration: TimeInterval = 0
    private var ended = false
    private var userTurnActionID: String?
    public private(set) var isCancelled = false

    public init(id: AssistedOptOutID, broker: AssistedOptOut.DataBroker, steps: AssistedOptOutSteps,
                instrumentation: AssistedOptOutInstrumentation? = nil, now: @escaping () -> Date = Date.init) {
        self.id = id
        self.broker = broker
        self.steps = steps
        self.instrumentation = instrumentation
        self.now = now
    }

    public var currentStepTitle: String? {
        steps.titles.indices.contains(currentStepIndex) ? steps.titles[currentStepIndex] : nil
    }

    public var dashboardItem: AssistedOptOut {
        let step = currentStepTitle.flatMap { title -> AssistedOptOut.Step? in
            guard phase == .agentInControl || phase == .userTurn else { return nil }
            return AssistedOptOut.Step(index: currentStepIndex, count: steps.titles.count, title: title)
        }
        return AssistedOptOut(id: id.description,
                              dataBroker: broker,
                              state: AssistedOptOut.State(phase: phase, isWindowKey: isWindowKey),
                              step: step)
    }

    /// Called when the user presses start in the window.
    public func begin() {
        guard phase == .ready, !isCancelled else { return }
        startedAt = now()
        instrumentation?.started()
        phase = .queued
        onBeginRequested?(self)
    }

    /// Called when the user stops the attempt or closes the window of a finished one. The queue then drops it.
    public func requestCancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancelRequested?(self)
    }

    /// Called by the queue when it cancels the attempt, so late reports from the page are ignored.
    public func markCancelled() { isCancelled = true }

    func finish(outcome: AssistedOptOutOutcome) {
        guard !ended else { return }
        ended = true
        endUserTurn()
        webView = nil
        if let startedAt {
            instrumentation?.ended(outcome: outcome, totalDuration: max(0, now().timeIntervalSince(startedAt)),
                                   userTurnDuration: userTurnDuration)
        }
    }

    private func endUserTurn() {
        if let userTurnStartedAt {
            userTurnDuration += max(0, now().timeIntervalSince(userTurnStartedAt))
            self.userTurnStartedAt = nil
        }
    }

    public func markSubmitted() {
        endUserTurn()
        phase = .submitted
        userTurnActionID = nil
        if let lastStep = steps.titles.indices.last {
            currentStepIndex = lastStep + 1
        }
    }

    public func attemptDidCreate(webView: WKWebView) {
        guard !ended, !isCancelled else { return }
        self.webView = webView
    }

    public func attemptWillRun(_ action: Action) {
        guard !ended, !isCancelled, phase != .submitted else { return }
        if let index = steps.index(of: action) {
            currentStepIndex = index
        }
        if action.id != userTurnActionID {
            endUserTurn()
            userTurnActionID = nil
            phase = .agentInControl
        }
    }

    public func attemptNeedsUser(actionID: String) {
        guard !ended, !isCancelled, phase != .submitted, userTurnActionID != actionID else { return }
        endUserTurn()
        userTurnStartedAt = now()
        if !firstUserTurnRecorded, let startedAt {
            firstUserTurnRecorded = true
            instrumentation?.reachedUserTurn(after: max(0, now().timeIntervalSince(startedAt)))
        }
        userTurnActionID = actionID
        phase = .userTurn
        onUserTurnStarted?(self)
    }
}
