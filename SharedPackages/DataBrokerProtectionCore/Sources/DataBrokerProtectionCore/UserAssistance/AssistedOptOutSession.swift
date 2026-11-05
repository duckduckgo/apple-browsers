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

/// One assisted attempt, shared by the runner and the window that shows it.
@MainActor
public final class AssistedOptOutSession: ObservableObject, OptOutAssistanceObserving, Identifiable {
    public let id: AssistedOptOutID
    public let broker: AssistedOptOut.DataBroker
    public let recordCount: Int
    public let steps: AssistedOptOutSteps

    @Published public private(set) var phase: AssistedAttemptPhase = .queued
    @Published public private(set) var currentStepIndex = 0
    @Published public private(set) var webView: WKWebView?

    /// Kept up to date by the window, so the dashboard can tell "needs you" from "you're in control".
    public var isWindowKey = false

    var onWebViewCreated: ((AssistedOptOutSession) -> Void)?
    var onUserTurnStarted: ((AssistedOptOutSession) -> Void)?
    var onCancelRequested: ((AssistedOptOutSession) -> Void)?

    private var userTurnActionID: String?
    private(set) var isCancelled = false

    public init(id: AssistedOptOutID, broker: AssistedOptOut.DataBroker, recordCount: Int, steps: AssistedOptOutSteps) {
        self.id = id
        self.broker = broker
        self.recordCount = recordCount
        self.steps = steps
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
                              recordCount: recordCount,
                              state: AssistedOptOut.State(phase: phase, isWindowKey: isWindowKey),
                              step: step)
    }

    /// Closing the window ends the attempt; the opt-out goes back to waiting for the user.
    public func requestCancel() {
        guard !isCancelled, phase != .submitted else { return }
        isCancelled = true
        onCancelRequested?(self)
    }

    func markSubmitted() {
        phase = .submitted
        userTurnActionID = nil
        if let lastStep = steps.titles.indices.last {
            currentStepIndex = lastStep + 1
        }
    }

    // MARK: - OptOutAssistanceObserving

    public func attemptDidCreate(webView: WKWebView) {
        self.webView = webView
        onWebViewCreated?(self)
    }

    public func attemptWillRun(_ action: Action) {
        guard phase != .submitted else { return }
        if let index = steps.index(of: action) {
            currentStepIndex = index
        }
        if action.id != userTurnActionID {
            userTurnActionID = nil
            phase = .agentInControl
        }
    }

    public func attemptNeedsUser(actionID: String) {
        guard phase != .submitted, userTurnActionID != actionID else { return }
        userTurnActionID = actionID
        phase = .userTurn
        onUserTurnStarted?(self)
    }
}
