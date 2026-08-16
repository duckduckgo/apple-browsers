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
import PixelKit

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

    static func completePersistedFlow(localScopeID: String,
                                      reason: DuckAISelectionJourneyWideEventData.TerminalReason,
                                      wideEvent: WideEventManaging,
                                      endedAt: Date = Date()) {
        for data in wideEvent.getAllFlowData(DuckAISelectionJourneyWideEventData.self)
            where data.localScopeID == localScopeID {
            if data.processSessionID == DuckAISelectionJourneyWideEventData.currentProcessSessionID {
                data.terminalReason = reason
                data.journeyInterval.end = endedAt
                wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
            } else {
                wideEvent.completeFlow(
                    data,
                    status: .unknown(reason: DuckAISelectionJourneyWideEventData.appTerminatedReason),
                    onComplete: { _, _ in })
            }
        }
    }

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

        for storedFlow in wideEvent.getAllFlowData(DuckAISelectionJourneyWideEventData.self) {
            if storedFlow.processSessionID != DuckAISelectionJourneyWideEventData.currentProcessSessionID {
                wideEvent.completeFlow(
                    storedFlow,
                    status: .unknown(reason: DuckAISelectionJourneyWideEventData.appTerminatedReason),
                    onComplete: { _, _ in })
            } else if storedFlow.localScopeID == localScopeID {
                activeFlow = storedFlow
            }
        }
    }

    func selectionAttached(currentCount: Int) {
        guard currentCount > 0 else { return }
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
        let now = dateProvider()
        activeFlow.dismissalCount += 1
        if activeFlow.firstDismissalInterval.end == nil {
            activeFlow.firstDismissalInterval.end = now
            activeFlow.postDismissalSubmissionInterval.start = now
        }
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
        if activeFlow.postDismissalSubmissionInterval.start != nil {
            activeFlow.postDismissalSubmissionInterval.end = dateProvider()
        }
        complete(activeFlow, reason: .submitted, status: .success)
    }

    func selectionsCleared(reason: DuckAISelectionJourneyWideEventData.TerminalReason) {
        guard let activeFlow else { return }
        complete(activeFlow, reason: reason, status: .failure)
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
