//
//  DuckAIWideEventInstrumentation.swift
//  DuckDuckGo
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
import AIChat
import PixelKit

/// Submission-scoped hooks for the Duck.ai prompt-submission wide event.
///
/// The instrumentation owns the wide-event state machine so callers only need
/// to forward observable events (submit, chat status change). Only one
/// submission may be in flight at a time; a new `submissionStarted()` while
/// another is active discards the previous flow.
protocol DuckAIWideEventInstrumentation: AnyObject {

    /// User submitted a Duck.ai prompt. Starts a new wide-event flow.
    func submissionStarted(modelId: String?, userTier: AIChatUserTier)

    /// The Duck.ai chat status published a new value. The instrumentation
    /// completes the active flow as SUCCESS the first time `.ready` is observed
    /// after at least one non-`.ready` value during the flow's lifetime. A page-
    /// reported `.error` or `.blocked` status completes the flow as FAILURE.
    func chatStatusChanged(_ status: AIChatStatusValue)

    /// User tapped the stop-generating button. Completes the active flow as
    /// CANCELLED. After this, any subsequent `.ready` status is ignored.
    func stopGeneratingTapped()
}

final class DefaultDuckAIWideEventInstrumentation: DuckAIWideEventInstrumentation {

    private let wideEvent: WideEventManaging
    private let dateProvider: () -> Date
    private var activeFlow: DuckAIPromptSubmissionWideEventData?
    /// Gates completion so a `.ready` replayed by the publisher at submit time
    /// can't auto-complete the freshly started flow. Flips true on the first
    /// non-`.ready` status observed after `submissionStarted()`.
    private var hasObservedNonReady = false

    init(wideEvent: WideEventManaging,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.dateProvider = dateProvider
    }

    func submissionStarted(modelId: String?, userTier: AIChatUserTier) {
        // Complete any orphaned flows left in storage from a previous app
        // lifecycle (e.g., the app was killed mid-stream). Runs synchronously
        // before the new flow is created, avoiding a race with
        // WideEventService.resume() which would otherwise complete new flows
        // as UNKNOWN.
        completeOrphanedFlows()

        if let activeFlow {
            // Defensive: a previous submission is still in flight (concurrent
            // submit before the previous one finished). Discard it so the new
            // submission is the only one tracked.
            wideEvent.discardFlow(activeFlow)
            self.activeFlow = nil
        }

        let data = DuckAIPromptSubmissionWideEventData(
            modelId: modelId,
            userTier: userTier.rawValue,
            startedAt: dateProvider()
        )
        activeFlow = data
        hasObservedNonReady = false
        wideEvent.startFlow(data)
    }

    func chatStatusChanged(_ status: AIChatStatusValue) {
        guard let activeFlow else { return }

        if status == .ready {
            guard hasObservedNonReady else { return }
            activeFlow.completeInterval.end = dateProvider()
            wideEvent.completeFlow(activeFlow, status: .success(), onComplete: { _, _ in })
            self.activeFlow = nil
            return
        }

        if let failingStep = Self.failingStep(for: status) {
            activeFlow.failingStep = failingStep
            wideEvent.completeFlow(activeFlow, status: .failure, onComplete: { _, _ in })
            self.activeFlow = nil
            return
        }

        let now = dateProvider()
        hasObservedNonReady = true
        if activeFlow.startThinkingInterval.end == nil {
            activeFlow.startThinkingInterval.end = now
        }
        if status == .streaming, activeFlow.startGeneratingInterval.end == nil {
            activeFlow.startGeneratingInterval.end = now
        }
    }

    private static func failingStep(for status: AIChatStatusValue) -> DuckAIPromptSubmissionWideEventData.FailingStep? {
        switch status {
        case .error: return .responseStateError
        case .blocked: return .responseStateBlocked
        default: return nil
        }
    }

    func stopGeneratingTapped() {
        guard let activeFlow else { return }
        wideEvent.completeFlow(activeFlow, status: .cancelled, onComplete: { _, _ in })
        self.activeFlow = nil
    }

    // MARK: - Helpers

    private func completeOrphanedFlows() {
        for orphan in wideEvent.getAllFlowData(DuckAIPromptSubmissionWideEventData.self) {
            wideEvent.completeFlow(
                orphan,
                status: .unknown(reason: DuckAIPromptSubmissionWideEventData.appTerminatedReason),
                onComplete: { _, _ in })
        }
    }
}
