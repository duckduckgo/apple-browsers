//
//  DuckAISelectionJourneyInstrumentation.swift
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
import WideEvent

@MainActor
protocol DuckAISelectionJourneyInstrumenting: AnyObject {
    func selectionAttached(currentCount: Int)
    func selectionRemoved(remainingCount: Int)
    func surfaceDismissed()
    func selectionSuggestionsViewed()
    func selectionSuggestionSelected(_ action: AIChatTextSelectionAction?)
    func selectionSuggestionDeliveryTimedOut()
    func promptSubmitted()
    func selectionsCleared(reason: DuckAISelectionJourneyWideEventData.TerminalReason)
}

@MainActor
final class DefaultDuckAISelectionJourneyInstrumentation: DuckAISelectionJourneyInstrumenting {

    /// Ends a journey owned by a scope the user has just destroyed (tab closed, tabs burned), where no
    /// instance is around to do it. Stale flows are dropped in `init`, so only live ones are matched here.
    static func completeFlow(localScopeID: String,
                             reason: DuckAISelectionJourneyWideEventData.TerminalReason,
                             wideEvent: WideEventManaging,
                             endedAt: Date = Date()) {
        for data in wideEvent.getAllFlowData(DuckAISelectionJourneyWideEventData.self)
            where data.localScopeID == localScopeID {
            data.terminalReason = reason
            data.journeyInterval.end = endedAt
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
        }
    }

    /// Discards journeys left on disk by a terminated process, without reporting them.
    ///
    /// The store is file-backed, so a journey interrupted by app termination outlives its process. This
    /// event describes a single in-session interaction, so such a flow is not a measurable outcome — it
    /// is dropped rather than reported. Runs synchronously from `init`, matching
    /// `NewTabPageSessionWideEventData`: a background launch task would race a journey the user starts
    /// early in the session, and here losing that race would silently delete a live journey.
    private static func discardStaleFlows(_ storedFlows: [DuckAISelectionJourneyWideEventData],
                                          wideEvent: WideEventManaging) {
        let currentProcess = DuckAISelectionJourneyWideEventData.currentProcessSessionID
        for data in storedFlows where data.processSessionID != currentProcess {
            wideEvent.discardFlow(data)
        }
    }

    /// Matches the largest duration bucket: past this the journey is no longer a single interaction.
    private static let maxJourneyDuration: TimeInterval = 300

    private let wideEvent: WideEventManaging
    private let localScopeID: String
    private let dateProvider: () -> Date
    private var activeFlow: DuckAISelectionJourneyWideEventData?
    private var pendingSubmissionAction: DuckAISelectionJourneyWideEventData.SubmissionAction?

    init(wideEvent: WideEventManaging,
         localScopeID: String,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.localScopeID = localScopeID
        self.dateProvider = dateProvider

        let storedFlows = wideEvent.getAllFlowData(DuckAISelectionJourneyWideEventData.self)
        Self.discardStaleFlows(storedFlows, wideEvent: wideEvent)
        activeFlow = storedFlows.first {
            $0.processSessionID == DuckAISelectionJourneyWideEventData.currentProcessSessionID
                && $0.localScopeID == localScopeID
        }
    }

    func selectionAttached(currentCount: Int) {
        guard currentCount > 0 else { return }
        endActiveFlowIfExpired()
        if let activeFlow {
            activeFlow.maxSelectionCount = max(activeFlow.maxSelectionCount, currentCount)
            wideEvent.updateFlow(activeFlow)
            return
        }

        let data = DuckAISelectionJourneyWideEventData(
            selectionCount: currentCount,
            localScopeID: localScopeID,
            startedAt: dateProvider()
        )
        activeFlow = data
        wideEvent.startFlow(data)
    }

    func selectionRemoved(remainingCount: Int) {
        guard let activeFlow else { return }
        guard remainingCount > 0 else {
            complete(activeFlow, reason: .selectionsRemoved, status: .failure)
            return
        }
        wideEvent.updateFlow(activeFlow)
    }

    func surfaceDismissed() {
        guard let activeFlow else { return }
        activeFlow.dismissalCount += 1
        pendingSubmissionAction = nil
        wideEvent.updateFlow(activeFlow)
    }

    func selectionSuggestionsViewed() {
        guard let activeFlow, !activeFlow.sawSelectionSuggestions else { return }
        activeFlow.sawSelectionSuggestions = true
        wideEvent.updateFlow(activeFlow)
    }

    func selectionSuggestionSelected(_ action: AIChatTextSelectionAction?) {
        guard activeFlow != nil else { return }
        switch action {
        case .summarize: pendingSubmissionAction = .summarize
        case .translate: pendingSubmissionAction = .translate
        case .ask, nil: pendingSubmissionAction = nil
        }
    }

    func selectionSuggestionDeliveryTimedOut() {
        guard let activeFlow else { return }
        activeFlow.hadDeliveryTimeout = true
        pendingSubmissionAction = nil
        wideEvent.updateFlow(activeFlow)
    }

    func promptSubmitted() {
        guard let activeFlow else { return }
        activeFlow.submissionAction = pendingSubmissionAction ?? .prompt
        complete(activeFlow, reason: .submitted, status: .success)
    }

    func selectionsCleared(reason: DuckAISelectionJourneyWideEventData.TerminalReason) {
        guard let activeFlow else { return }
        complete(activeFlow, reason: reason, status: .failure)
    }

    /// Ends a journey that has outlived the interaction it is meant to describe.
    ///
    /// The inactivity timer only runs while the surface is dismissed, so a journey left with the sheet
    /// open has no other bound. Checked on attachment rather than on a timer: an expired journey has to
    /// be closed before it can absorb a new selection, and nothing else needs it closed sooner.
    private func endActiveFlowIfExpired() {
        guard let activeFlow,
              let startedAt = activeFlow.journeyInterval.start,
              dateProvider().timeIntervalSince(startedAt) > Self.maxJourneyDuration
        else { return }
        complete(activeFlow, reason: .sessionExpired, status: .failure)
    }

    private func complete(_ data: DuckAISelectionJourneyWideEventData,
                          reason: DuckAISelectionJourneyWideEventData.TerminalReason,
                          status: WideEventStatus) {
        data.terminalReason = reason
        data.journeyInterval.end = dateProvider()
        wideEvent.completeFlow(data, status: status, onComplete: { _, _ in })
        activeFlow = nil
        pendingSubmissionAction = nil
    }
}
