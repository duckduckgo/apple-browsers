//
//  DuckAISelectionJourneyInstrumentationTests.swift
//  DuckDuckGoTests
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
import PixelKitTestingUtilities
import Testing
@testable import DuckDuckGo

@Suite("DuckAI Selection Journey Instrumentation")
@MainActor
struct DuckAISelectionJourneyInstrumentationTests {

    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    private struct TestContext {
        let sut: DefaultDuckAISelectionJourneyInstrumentation
        let wideEvent: WideEventMock
        let clock: TestClock
    }

    private func makeSUT(seededFlows: [DuckAISelectionJourneyWideEventData] = []) -> TestContext {
        let wideEvent = WideEventMock()
        seededFlows.forEach { wideEvent.startFlow($0) }
        let clock = TestClock()
        let sut = DefaultDuckAISelectionJourneyInstrumentation(
            wideEvent: wideEvent,
            localScopeID: "test-scope",
            dateProvider: { clock.now }
        )
        return TestContext(sut: sut, wideEvent: wideEvent, clock: clock)
    }

    private func lastCompletion(_ wideEvent: WideEventMock) -> (DuckAISelectionJourneyWideEventData, WideEventStatus)? {
        guard let completion = wideEvent.completions.last,
              let data = completion.0 as? DuckAISelectionJourneyWideEventData else { return nil }
        return (data, completion.1)
    }

    @available(iOS 16, *)
    @Test("First attachment starts one journey and later attachments update its bounded maximum", .timeLimit(.minutes(1)))
    func attachmentsStartAndUpdateJourney() {
        let context = makeSUT()
        let (sut, wideEvent) = (context.sut, context.wideEvent)

        sut.selectionAttached(currentCount: 1)
        sut.selectionAttached(currentCount: 2)
        sut.selectionAttached(currentCount: 5)

        #expect(wideEvent.started.count == 1)
        #expect(wideEvent.updates.count == 2)
        let data = wideEvent.started.first as? DuckAISelectionJourneyWideEventData
        #expect(data?.maxSelectionCount == 5)
    }

    @available(iOS 16, *)
    @Test("Dismissal keeps the journey open and a later prompt succeeds", .timeLimit(.minutes(1)))
    func dismissalThenPromptSubmission() throws {
        let context = makeSUT()
        let sut = context.sut
        let wideEvent = context.wideEvent
        let clock = context.clock
        sut.selectionAttached(currentCount: 1)
        clock.advance(by: 2)
        sut.surfaceDismissed()
        clock.advance(by: 8)

        sut.promptSubmitted()

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.1 == .success)
        #expect(completion.0.terminalReason == .submitted)
        #expect(completion.0.submissionAction == .prompt)
        #expect(completion.0.dismissalCount == 1)
        #expect(completion.0.firstDismissalInterval.end != nil)
        #expect(completion.0.postDismissalSubmissionInterval.end != nil)
    }

    @available(iOS 16, *)
    @Test("Selection suggestion identifies the successful submission action", .timeLimit(.minutes(1)))
    func selectionSuggestionSubmission() throws {
        let context = makeSUT()
        let (sut, wideEvent) = (context.sut, context.wideEvent)
        sut.selectionAttached(currentCount: 1)
        sut.selectionSuggestionSelected(.translate)

        sut.promptSubmitted()

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.0.submissionAction == .translate)
    }

    @available(iOS 16, *)
    @Test("A non-selection suggestion clears a previously pending selection action", .timeLimit(.minutes(1)))
    func nonSelectionSuggestionClearsPendingAction() throws {
        let context = makeSUT()
        let (sut, wideEvent) = (context.sut, context.wideEvent)
        sut.selectionAttached(currentCount: 1)
        sut.selectionSuggestionSelected(.summarize)
        sut.selectionSuggestionSelected(nil)

        sut.promptSubmitted()

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.0.submissionAction == .prompt)
    }

    @available(iOS 16, *)
    @Test("Delivery timeout is retained while a later submission can still succeed", .timeLimit(.minutes(1)))
    func deliveryTimeoutThenSubmission() throws {
        let context = makeSUT()
        let (sut, wideEvent) = (context.sut, context.wideEvent)
        sut.selectionAttached(currentCount: 1)
        sut.selectionSuggestionSelected(.summarize)
        sut.selectionSuggestionDeliveryTimedOut()

        sut.promptSubmitted()

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.1 == .success)
        #expect(completion.0.hadDeliveryTimeout)
        #expect(completion.0.submissionAction == .prompt)
    }

    @available(iOS 16, *)
    @Test("Removing the final unsubmitted selection explicitly abandons the journey", .timeLimit(.minutes(1)))
    func removingLastSelectionFailsJourney() throws {
        let context = makeSUT()
        let (sut, wideEvent) = (context.sut, context.wideEvent)
        sut.selectionAttached(currentCount: 2)
        sut.selectionRemoved(remainingCount: 1)

        sut.selectionRemoved(remainingCount: 0)

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.1 == .failure)
        #expect(completion.0.terminalReason == .selectionsRemoved)
    }

    @available(iOS 16, *)
    @Test("Explicit clearing actions complete as conversion failures", .timeLimit(.minutes(1)), arguments: [
        DuckAISelectionJourneyWideEventData.TerminalReason.newChat,
        .chatCleared,
        .tabClosed,
    ])
    func explicitClearFailsJourney(reason: DuckAISelectionJourneyWideEventData.TerminalReason) throws {
        let context = makeSUT()
        let (sut, wideEvent) = (context.sut, context.wideEvent)
        sut.selectionAttached(currentCount: 1)

        sut.selectionsCleared(reason: reason)

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.1 == .failure)
        #expect(completion.0.terminalReason == reason)
    }

    @available(iOS 16, *)
    @Test("Persisted journeys from a previous process complete as unknown on initialization", .timeLimit(.minutes(1)))
    func orphanedJourneyCompletesUnknown() throws {
        let orphan = DuckAISelectionJourneyWideEventData(
            selectionCount: 1,
            localScopeID: "test-scope",
            processSessionID: UUID()
        )
        let wideEvent = makeSUT(seededFlows: [orphan]).wideEvent

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.1 == .unknown(reason: DuckAISelectionJourneyWideEventData.appTerminatedReason))
        #expect(completion.0.terminalReason == nil)
    }

    @available(iOS 16, *)
    @Test("Creating another tab instrumentation does not terminate a journey from this process", .timeLimit(.minutes(1)))
    func currentProcessJourneyIsResumed() throws {
        let active = DuckAISelectionJourneyWideEventData(selectionCount: 1, localScopeID: "test-scope")
        let context = makeSUT(seededFlows: [active])
        let (sut, wideEvent) = (context.sut, context.wideEvent)

        sut.promptSubmitted()

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.1 == .success)
        #expect(completion.0.globalData.id == active.globalData.id)
    }

    @available(iOS 16, *)
    @Test("Tab closure completes a persisted journey even when its controller was evicted", .timeLimit(.minutes(1)))
    func persistedJourneyCompletesOnTabClose() throws {
        let active = DuckAISelectionJourneyWideEventData(selectionCount: 1, localScopeID: "evicted-tab")
        let wideEvent = WideEventMock()
        wideEvent.startFlow(active)

        DefaultDuckAISelectionJourneyInstrumentation.completePersistedFlow(
            localScopeID: "evicted-tab",
            reason: .tabClosed,
            wideEvent: wideEvent
        )

        let completion = try #require(lastCompletion(wideEvent))
        #expect(completion.1 == .failure)
        #expect(completion.0.terminalReason == .tabClosed)
    }

    @available(iOS 16, *)
    @Test("Payload contains only closed and bucketed journey data", .timeLimit(.minutes(1)))
    func payloadIsBounded() throws {
        let context = makeSUT()
        let sut = context.sut
        let wideEvent = context.wideEvent
        let clock = context.clock
        sut.selectionAttached(currentCount: 5)
        clock.advance(by: 7)
        sut.surfaceDismissed()
        sut.surfaceDismissed()
        sut.selectionSuggestionsViewed()
        sut.selectionSuggestionsViewed()
        clock.advance(by: 70)
        sut.selectionSuggestionSelected(.summarize)
        sut.promptSubmitted()

        let data = try #require(lastCompletion(wideEvent)?.0)
        let parameters = data.jsonParameters()
        #expect(parameters[WideEventParameter.DuckAISelectionJourneyFeature.selectionCountBucketed] as? String == "3-5")
        #expect(parameters[WideEventParameter.DuckAISelectionJourneyFeature.dismissalCountBucketed] as? String == "2+")
        #expect(parameters[WideEventParameter.DuckAISelectionJourneyFeature.journeyDurationMsBucketed] as? String == "60000")
        #expect(parameters[WideEventParameter.DuckAISelectionJourneyFeature.dismissedBeforeSubmission] as? Bool == true)
        #expect(parameters[WideEventParameter.DuckAISelectionJourneyFeature.sawSelectionSuggestions] as? Bool == true)
    }

    @available(iOS 16, *)
    @Test("Wide event metadata matches the registered schema", .timeLimit(.minutes(1)))
    func metadataMatchesSchema() {
        #expect(DuckAISelectionJourneyWideEventData.metadata.pixelName == "duckai_selection_journey")
        #expect(DuckAISelectionJourneyWideEventData.metadata.featureName == "duckai-selection-journey")
        #expect(DuckAISelectionJourneyWideEventData.metadata.type == "ios-duckai-selection-journey")
        #expect(DuckAISelectionJourneyWideEventData.metadata.version == "1.1.0")
    }

    @available(iOS 16, *)
    @Test("Only a flow from a previous process is eligible for launch cleanup", .timeLimit(.minutes(1)))
    func launchCleanupDecision() async {
        let current = DuckAISelectionJourneyWideEventData(selectionCount: 1, localScopeID: "current")
        let previous = DuckAISelectionJourneyWideEventData(
            selectionCount: 1,
            localScopeID: "previous",
            processSessionID: UUID()
        )

        if case .keepPending = await current.completionDecision(for: .appLaunch) {
        } else {
            Issue.record("Expected the current-process flow to remain pending")
        }

        if case .complete(let status) = await previous.completionDecision(for: .appLaunch) {
            #expect(status == .unknown(reason: "app_terminated"))
        } else {
            Issue.record("Expected the previous-process flow to complete")
        }
    }
}
