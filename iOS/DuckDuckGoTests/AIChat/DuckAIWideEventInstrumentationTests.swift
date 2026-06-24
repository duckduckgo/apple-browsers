//
//  DuckAIWideEventInstrumentationTests.swift
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

import AIChat
import Foundation
import PixelKit
import PixelKitTestingUtilities
import Testing
@testable import DuckDuckGo

@Suite("DuckAI Wide Event Instrumentation")
@MainActor
struct DuckAIWideEventInstrumentationTests {

    // MARK: - Test helpers

    private final class TestClock {
        var now: Date
        init(_ start: Date) { self.now = start }
        func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private static let baseNow = Date(timeIntervalSince1970: 1_700_000_000)
    private static let activeTab: TabUID = "active-tab"
    private static let otherTab: TabUID = "other-tab"
    private static let contextualID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func makeSUT(
        now: Date = baseNow,
        completeOrphanedFlowsOnInit: Bool = false,
        seededFlows: [DuckAIPromptWideEventData] = []
    ) -> (DefaultDuckAIWideEventInstrumentation, WideEventMock, TestClock) {
        let clock = TestClock(now)
        let wideEvent = WideEventMock()
        seededFlows.forEach { wideEvent.startFlow($0) }
        let sut = DefaultDuckAIWideEventInstrumentation(
            wideEvent: wideEvent,
            completeOrphanedFlowsOnInit: completeOrphanedFlowsOnInit,
            dateProvider: { clock.now }
        )
        return (sut, wideEvent, clock)
    }

    private func startPromptSubmission(on tabID: TabUID, sut: DefaultDuckAIWideEventInstrumentation) {
        sut.submissionStarted(
            scope: .tab(tabID),
            modelId: nil,
            userTier: .free,
            reasoningEffort: nil,
            entryPoint: .aiTab,
            inputMode: .keyboard,
            fireMode: false,
            isFirstPrompt: true,
            frontendDeliveryPath: .userScript,
            hasPageContext: false,
            toolsSelected: false,
            attachmentsSelected: false
        )
    }

    private func startContextualSubmission(on uuid: UUID, sut: DefaultDuckAIWideEventInstrumentation) {
        sut.submissionStarted(
            scope: .contextual(uuid),
            modelId: nil,
            userTier: .free,
            reasoningEffort: nil,
            entryPoint: .contextualChat,
            inputMode: .keyboard,
            fireMode: false,
            isFirstPrompt: true,
            frontendDeliveryPath: .contextualNativeInput,
            hasPageContext: true,
            toolsSelected: false,
            attachmentsSelected: false
        )
    }

    private func lastStartedData(_ wideEvent: WideEventMock) -> DuckAIPromptWideEventData? {
        wideEvent.started.compactMap { $0 as? DuckAIPromptWideEventData }.last
    }

    private func lastCompletion(_ wideEvent: WideEventMock) -> (DuckAIPromptWideEventData, WideEventStatus)? {
        guard let last = wideEvent.completions.last,
              let data = last.0 as? DuckAIPromptWideEventData else { return nil }
        return (data, last.1)
    }

    private func lastUpdatedData(_ wideEvent: WideEventMock) -> DuckAIPromptWideEventData? {
        wideEvent.updates.compactMap { $0 as? DuckAIPromptWideEventData }.last
    }

    private func makeData(
        modelId: String? = "claude-3",
        userTier: String = "plus",
        reasoningEffort: String? = "medium",
        entryPoint: DuckAIPromptWideEventData.EntryPoint = .omnibar,
        inputMode: DuckAIPromptWideEventData.InputMode = .keyboard,
        fireMode: Bool = true,
        isFirstPrompt: Bool = false,
        frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath = .urlAutoSubmit,
        hasPageContext: Bool = true,
        toolsSelected: Bool = true,
        attachmentsSelected: Bool = true,
        startedAt: Date = Self.baseNow
    ) -> DuckAIPromptWideEventData {
        DuckAIPromptWideEventData(
            modelId: modelId,
            userTier: userTier,
            reasoningEffort: reasoningEffort,
            entryPoint: entryPoint,
            inputMode: inputMode,
            fireMode: fireMode,
            isFirstPrompt: isFirstPrompt,
            frontendDeliveryPath: frontendDeliveryPath,
            hasPageContext: hasPageContext,
            toolsSelected: toolsSelected,
            attachmentsSelected: attachmentsSelected,
            startedAt: startedAt
        )
    }

    // MARK: - Submission start

    @available(iOS 16, *)
    @Test("A new tab submission starts a flow with last_step submitted", .timeLimit(.minutes(1)))
    func newTabSubmissionStartsFlow() {
        let (sut, wideEvent, _) = makeSUT()

        startPromptSubmission(on: Self.activeTab, sut: sut)

        let data = lastStartedData(wideEvent)
        #expect(data != nil)
        #expect(data?.lastStep == .submitted)
        #expect(data?.entryPoint == .aiTab)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("A new contextual submission starts a flow with last_step submitted", .timeLimit(.minutes(1)))
    func newContextualSubmissionStartsFlow() {
        let (sut, wideEvent, _) = makeSUT()

        startContextualSubmission(on: Self.contextualID, sut: sut)

        let data = lastStartedData(wideEvent)
        #expect(data != nil)
        #expect(data?.lastStep == .submitted)
        #expect(data?.entryPoint == .contextualChat)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("A second submission on the same scope supersedes the first", .timeLimit(.minutes(1)))
    func secondSubmissionOnSameScopeSupersedesFirst() {
        let (sut, wideEvent, _) = makeSUT()

        startPromptSubmission(on: Self.activeTab, sut: sut)
        startPromptSubmission(on: Self.activeTab, sut: sut)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion for the first submission")
            return
        }
        #expect(completion.1 == .cancelled)
        #expect(completion.0.cancellationReason == .supersededByNewSubmission)
    }

    @available(iOS 16, *)
    @Test("Submissions on different scopes do not interfere", .timeLimit(.minutes(1)))
    func submissionsOnDifferentScopesStayActive() {
        let (sut, wideEvent, _) = makeSUT()

        startPromptSubmission(on: Self.activeTab, sut: sut)
        startContextualSubmission(on: Self.contextualID, sut: sut)

        #expect(wideEvent.completions.isEmpty)
    }

    // MARK: - Prompt delivery

    @available(iOS 16, *)
    @Test("promptDeliveryUpdated wasQueued=true sets frontendDeliveryQueued", .timeLimit(.minutes(1)))
    func promptDeliveryUpdatedSetsQueued() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: true, didSendBridgeMessage: nil)

        let update = lastUpdatedData(wideEvent)
        #expect(wideEvent.updates.count == 1)
        #expect(update?.frontendDeliveryQueued == true)
        #expect(update?.didSendBridgeMessage == nil)
    }

    @available(iOS 16, *)
    @Test("promptDeliveryUpdated nil arguments leave existing values intact", .timeLimit(.minutes(1)))
    func promptDeliveryUpdatedNilArgsPreserveExisting() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: true, didSendBridgeMessage: nil)
        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: nil, didSendBridgeMessage: true)

        let update = lastUpdatedData(wideEvent)
        #expect(wideEvent.updates.count == 2)
        #expect(update?.frontendDeliveryQueued == true)
        #expect(update?.didSendBridgeMessage == true)
    }

    @available(iOS 16, *)
    @Test("promptDeliveryUpdated on an unknown scope is a no-op", .timeLimit(.minutes(1)))
    func promptDeliveryUpdatedOnUnknownScopeIsNoop() {
        let (sut, wideEvent, _) = makeSUT()

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: true, didSendBridgeMessage: true)

        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("promptDeliveryUpdated wasQueued=false marks did_attempt_delivery", .timeLimit(.minutes(1)))
    func deliveryNotQueuedMarksAttempted() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: false, didSendBridgeMessage: nil)

        let update = lastUpdatedData(wideEvent)
        #expect(update?.didAttemptDelivery == true)
    }

    @available(iOS 16, *)
    @Test("promptDeliveryUpdated wasQueued=nil marks did_attempt_delivery", .timeLimit(.minutes(1)))
    func deliveryNilQueuedMarksAttempted() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: nil, didSendBridgeMessage: true)

        let update = lastUpdatedData(wideEvent)
        #expect(update?.didAttemptDelivery == true)
    }

    @available(iOS 16, *)
    @Test("promptDeliveryUpdated wasQueued=true does not mark did_attempt_delivery", .timeLimit(.minutes(1)))
    func queuedDeliveryDoesNotMarkAttempted() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: true, didSendBridgeMessage: nil)

        let update = lastUpdatedData(wideEvent)
        #expect(update?.didAttemptDelivery == false)
    }

    @available(iOS 16, *)
    @Test("A queued delivery that later flushes marks did_attempt_delivery", .timeLimit(.minutes(1)))
    func queuedThenFlushedMarksAttempted() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: true, didSendBridgeMessage: nil)
        #expect(lastUpdatedData(wideEvent)?.didAttemptDelivery == false)

        sut.promptDeliveryUpdated(scope: .tab(Self.activeTab), wasQueued: nil, didSendBridgeMessage: true)
        #expect(lastUpdatedData(wideEvent)?.didAttemptDelivery == true)
    }

    // MARK: - Frontend acknowledgement

    @available(iOS 16, *)
    @Test("frontendSubmissionAcknowledged sets the ack interval end", .timeLimit(.minutes(1)))
    func frontendAckSetsIntervalEnd() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.frontendSubmissionAcknowledged(scope: .tab(Self.activeTab))

        let update = lastUpdatedData(wideEvent)
        #expect(wideEvent.updates.count == 1)
        #expect(update?.frontendSubmissionAckInterval.end == Self.baseNow.addingTimeInterval(1.0))
    }

    @available(iOS 16, *)
    @Test("A second frontendSubmissionAcknowledged does not overwrite the first", .timeLimit(.minutes(1)))
    func secondFrontendAckDoesNotOverwrite() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.frontendSubmissionAcknowledged(scope: .tab(Self.activeTab))
        clock.advance(by: 5.0)
        sut.frontendSubmissionAcknowledged(scope: .tab(Self.activeTab))

        let update = lastUpdatedData(wideEvent)
        #expect(wideEvent.updates.count == 1)
        #expect(update?.frontendSubmissionAckInterval.end == Self.baseNow.addingTimeInterval(1.0))
    }

    @available(iOS 16, *)
    @Test("frontendSubmissionAcknowledged on an unknown scope is a no-op", .timeLimit(.minutes(1)))
    func frontendAckOnUnknownScopeIsNoop() {
        let (sut, wideEvent, _) = makeSUT()

        sut.frontendSubmissionAcknowledged(scope: .tab(Self.activeTab))

        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("frontendSubmissionAcknowledged before any chat status still completes the flow as success", .timeLimit(.minutes(1)))
    func frontendAckBeforeAnyStatusStillSucceeds() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.frontendSubmissionAcknowledged(scope: .tab(Self.activeTab))
        clock.advance(by: 1.0)
        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        clock.advance(by: 2.0)
        sut.chatStatusChanged(.ready, scope: .tab(Self.activeTab))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a success completion")
            return
        }
        #expect(completion.1 == .success())
        #expect(completion.0.frontendSubmissionAckInterval.end == Self.baseNow.addingTimeInterval(1.0))
        #expect(completion.0.startThinkingInterval.end == Self.baseNow.addingTimeInterval(2.0))
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(4.0))
    }

    // MARK: - Chat status, success path

    @available(iOS 16, *)
    @Test("First non-ready status sets startThinking end and last_step", .timeLimit(.minutes(1)))
    func firstNonReadyStatusSetsStartThinking() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))

        let update = lastUpdatedData(wideEvent)
        #expect(wideEvent.updates.count == 1)
        #expect(update?.startThinkingInterval.end == Self.baseNow.addingTimeInterval(1.0))
        #expect(update?.lastStep == .loading)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("First streaming status sets startGenerating end", .timeLimit(.minutes(1)))
    func firstStreamingStatusSetsStartGenerating() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        clock.advance(by: 2.0)
        sut.chatStatusChanged(.streaming, scope: .tab(Self.activeTab))

        let update = lastUpdatedData(wideEvent)
        #expect(wideEvent.updates.count == 2)
        #expect(update?.startGeneratingInterval.end == Self.baseNow.addingTimeInterval(3.0))
        #expect(update?.lastStep == .streaming)
    }

    @available(iOS 16, *)
    @Test("Every non-ready non-terminal chat status updates last_step", .timeLimit(.minutes(1)))
    func nonReadyNonTerminalStatusesUpdateLastStep() {
        let cases: [(AIChatStatusValue, DuckAIPromptWideEventData.LastStep)] = [
            (.loading, .loading),
            (.streaming, .streaming),
            (.startStreamNewPrompt, .startStreamNewPrompt),
            (.startStreamRestartStream, .startStreamRestartStream),
            (.unknown, .unknownStatus)
        ]

        for (status, expectedLastStep) in cases {
            let (sut, wideEvent, clock) = makeSUT()
            startPromptSubmission(on: Self.activeTab, sut: sut)

            clock.advance(by: 1.0)
            sut.chatStatusChanged(status, scope: .tab(Self.activeTab))

            let update = lastUpdatedData(wideEvent)
            #expect(wideEvent.updates.count == 1)
            #expect(update?.lastStep == expectedLastStep)
            #expect(update?.startThinkingInterval.end == Self.baseNow.addingTimeInterval(1.0))
            #expect(wideEvent.completions.isEmpty)
        }
    }

    @available(iOS 16, *)
    @Test("Ready after a non-ready status completes the flow as success", .timeLimit(.minutes(1)))
    func readyAfterNonReadyCompletesSuccess() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        clock.advance(by: 2.0)
        sut.chatStatusChanged(.ready, scope: .tab(Self.activeTab))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a success completion")
            return
        }
        #expect(completion.1 == .success())
        #expect(completion.0.lastStep == nil)
        #expect(completion.0.generatingCompletedInterval.end == Self.baseNow.addingTimeInterval(3.0))
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(3.0))
    }

    @available(iOS 16, *)
    @Test("A full loading→streaming→ready sequence records every interval", .timeLimit(.minutes(1)))
    func fullSuccessSequenceRecordsAllIntervals() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        clock.advance(by: 2.0)
        sut.chatStatusChanged(.streaming, scope: .tab(Self.activeTab))
        clock.advance(by: 2.0)
        sut.chatStatusChanged(.ready, scope: .tab(Self.activeTab))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a success completion")
            return
        }
        #expect(completion.0.startThinkingInterval.end == Self.baseNow.addingTimeInterval(1.0))
        #expect(completion.0.startGeneratingInterval.end == Self.baseNow.addingTimeInterval(3.0))
        #expect(completion.0.generatingCompletedInterval.end == Self.baseNow.addingTimeInterval(5.0))
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(5.0))
    }

    // MARK: - Chat status, no-op and failure paths

    @available(iOS 16, *)
    @Test("Ready with no prior non-ready status is a no-op", .timeLimit(.minutes(1)))
    func readyWithoutNonReadyIsNoop() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.ready, scope: .tab(Self.activeTab))

        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Error status completes the flow as failure with response_state_error", .timeLimit(.minutes(1)))
    func errorStatusCompletesFailure() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.error, scope: .tab(Self.activeTab))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a failure completion")
            return
        }
        #expect(completion.1 == .failure)
        #expect(completion.0.lastStep == .responseStateError)
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(1.0))
    }

    @available(iOS 16, *)
    @Test("Blocked status completes the flow as failure with response_state_blocked", .timeLimit(.minutes(1)))
    func blockedStatusCompletesFailure() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.blocked, scope: .tab(Self.activeTab))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a failure completion")
            return
        }
        #expect(completion.1 == .failure)
        #expect(completion.0.lastStep == .responseStateBlocked)
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(1.0))
    }

    @available(iOS 16, *)
    @Test("chatStatusChanged on an unknown scope is a no-op", .timeLimit(.minutes(1)))
    func chatStatusChangedOnUnknownScopeIsNoop() {
        let (sut, wideEvent, _) = makeSUT()

        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))

        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.updates.isEmpty)
    }

    @available(iOS 16, *)
    @Test("chatStatusChanged after the flow has completed is a no-op", .timeLimit(.minutes(1)))
    func chatStatusChangedAfterCompletionIsNoop() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)
        sut.chatStatusChanged(.error, scope: .tab(Self.activeTab))
        let completionsAfterFailure = wideEvent.completions.count

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        sut.chatStatusChanged(.ready, scope: .tab(Self.activeTab))

        #expect(wideEvent.completions.count == completionsAfterFailure)
    }

    // MARK: - Cancellations

    @available(iOS 16, *)
    @Test("stopGeneratingTapped cancels the active flow with stop_button", .timeLimit(.minutes(1)))
    func stopGeneratingTappedCancels() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.stopGeneratingTapped(scope: .tab(Self.activeTab))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion")
            return
        }
        #expect(completion.1 == .cancelled)
        #expect(completion.0.cancellationReason == .stopButton)
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(1.0))
    }

    @available(iOS 16, *)
    @Test("A second stopGeneratingTapped is a no-op", .timeLimit(.minutes(1)))
    func secondStopGeneratingTappedIsNoop() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)
        sut.stopGeneratingTapped(scope: .tab(Self.activeTab))
        let completionsAfterFirst = wideEvent.completions.count

        sut.stopGeneratingTapped(scope: .tab(Self.activeTab))

        #expect(wideEvent.completions.count == completionsAfterFirst)
    }

    @available(iOS 16, *)
    @Test("Closing a different tab does not cancel the active prompt submission", .timeLimit(.minutes(1)))
    func closingDifferentTabDoesNotCancelActiveSubmission() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        sut.tabClosedDuringGeneration(tabID: Self.otherTab)

        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Closing the active tab cancels the active prompt submission", .timeLimit(.minutes(1)))
    func closingActiveTabCancelsActiveSubmission() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        sut.tabClosedDuringGeneration(tabID: Self.activeTab)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion")
            return
        }
        #expect(completion.1 == .cancelled)
        #expect(completion.0.cancellationReason == .tabClosed)
    }

    @available(iOS 16, *)
    @Test("Switching away from the active tab cancels with switched_tabs", .timeLimit(.minutes(1)))
    func tabSwitchedAwayCancelsMatchingTab() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.tabSwitchedAwayDuringGeneration(tabID: Self.activeTab)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion")
            return
        }
        #expect(completion.1 == .cancelled)
        #expect(completion.0.cancellationReason == .switchedTabs)
    }

    @available(iOS 16, *)
    @Test("Fire button clearing the active tab cancels with fire_button", .timeLimit(.minutes(1)))
    func fireButtonClearedTabCancelsMatchingTab() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.fireButtonClearedTabDuringGeneration(tabID: Self.activeTab)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion")
            return
        }
        #expect(completion.1 == .cancelled)
        #expect(completion.0.cancellationReason == .fireButton)
    }

    @available(iOS 16, *)
    @Test("Fire button cancellation is not overwritten by a later tab switch", .timeLimit(.minutes(1)))
    func fireButtonCancellationWinsOverLaterTabSwitch() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.fireButtonClearedTabDuringGeneration(tabID: Self.activeTab)
        sut.tabSwitchedAwayDuringGeneration(tabID: Self.activeTab)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion")
            return
        }
        #expect(wideEvent.completions.count == 1)
        #expect(completion.0.cancellationReason == .fireButton)
    }

    @available(iOS 16, *)
    @Test("Switching away from a different tab does not cancel the active flow", .timeLimit(.minutes(1)))
    func tabSwitchedAwayDoesNotCancelDifferentTab() {
        let (sut, wideEvent, _) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        sut.tabSwitchedAwayDuringGeneration(tabID: Self.otherTab)

        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("sheetDismissedDuringGeneration cancels the contextual flow with sheet_dismissed", .timeLimit(.minutes(1)))
    func sheetDismissedCancelsContextualFlow() {
        let (sut, wideEvent, _) = makeSUT()
        startContextualSubmission(on: Self.contextualID, sut: sut)

        sut.sheetDismissedDuringGeneration(scope: .contextual(Self.contextualID))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion")
            return
        }
        #expect(completion.1 == .cancelled)
        #expect(completion.0.cancellationReason == .sheetDismissed)
    }

    @available(iOS 16, *)
    @Test("Cancellation methods are no-ops when no flow is active", .timeLimit(.minutes(1)))
    func cancellationMethodsNoopWithoutActiveFlow() {
        let (sut, wideEvent, _) = makeSUT()

        sut.stopGeneratingTapped(scope: .tab(Self.activeTab))
        sut.tabClosedDuringGeneration(tabID: Self.activeTab)
        sut.tabSwitchedAwayDuringGeneration(tabID: Self.activeTab)
        sut.fireButtonClearedTabDuringGeneration(tabID: Self.activeTab)
        sut.sheetDismissedDuringGeneration(scope: .contextual(Self.contextualID))

        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("promptInterpretedAsURL cancels the active flow with interpreted_as_url", .timeLimit(.minutes(1)))
    func promptInterpretedAsURLCancels() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)

        clock.advance(by: 1.0)
        sut.promptInterpretedAsURL(scope: .tab(Self.activeTab))

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a cancellation completion")
            return
        }
        #expect(completion.1 == .cancelled)
        #expect(completion.0.cancellationReason == .interpretedAsURL)
        #expect(completion.0.didAttemptDelivery == false)
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(1.0))
    }

    @available(iOS 16, *)
    @Test("promptInterpretedAsURL on an unknown scope is a no-op", .timeLimit(.minutes(1)))
    func promptInterpretedAsURLOnUnknownScopeIsNoop() {
        let (sut, wideEvent, _) = makeSUT()

        sut.promptInterpretedAsURL(scope: .tab(Self.activeTab))

        #expect(wideEvent.completions.isEmpty)
    }

    // MARK: - Page load failures

    @available(iOS 16, *)
    @Test("pageLoadFailed completes the flow as failure with navigation_failed and error data", .timeLimit(.minutes(1)))
    func pageLoadFailedCompletesFailure() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)
        let error = NSError(domain: "TestDomain", code: 42)

        clock.advance(by: 1.0)
        sut.pageLoadFailed(scope: .tab(Self.activeTab), error: error)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a failure completion")
            return
        }
        #expect(completion.1 == .failure)
        #expect(completion.0.lastStep == .navigationFailed)
        #expect(completion.0.errorData?.domain == "TestDomain")
        #expect(completion.0.errorData?.code == 42)
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(1.0))
    }

    @available(iOS 16, *)
    @Test("pageLoadFailed on an unknown scope is a no-op", .timeLimit(.minutes(1)))
    func pageLoadFailedOnUnknownScopeIsNoop() {
        let (sut, wideEvent, _) = makeSUT()
        let error = NSError(domain: "TestDomain", code: 42)

        sut.pageLoadFailed(scope: .tab(Self.activeTab), error: error)

        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("pageLoadFailed after streaming preserves earlier interval ends", .timeLimit(.minutes(1)))
    func pageLoadFailedAfterProgressionPreservesIntervals() {
        let (sut, wideEvent, clock) = makeSUT()
        startPromptSubmission(on: Self.activeTab, sut: sut)
        let error = NSError(domain: "TestDomain", code: 42)

        clock.advance(by: 1.0)
        sut.chatStatusChanged(.loading, scope: .tab(Self.activeTab))
        clock.advance(by: 2.0)
        sut.chatStatusChanged(.streaming, scope: .tab(Self.activeTab))
        clock.advance(by: 2.0)
        sut.pageLoadFailed(scope: .tab(Self.activeTab), error: error)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a failure completion")
            return
        }
        #expect(completion.1 == .failure)
        #expect(completion.0.lastStep == .navigationFailed)
        #expect(completion.0.startThinkingInterval.end == Self.baseNow.addingTimeInterval(1.0))
        #expect(completion.0.startGeneratingInterval.end == Self.baseNow.addingTimeInterval(3.0))
        #expect(completion.0.generatingCompletedInterval.end == nil)
        #expect(completion.0.endedInterval.end == Self.baseNow.addingTimeInterval(5.0))
    }

    // MARK: - Orphan recovery on init

    @available(iOS 16, *)
    @Test("Init with completeOrphanedFlowsOnInit=true completes seeded flows as unknown(app_terminated)", .timeLimit(.minutes(1)))
    func orphanRecoveryCompletesSeededFlows() {
        let orphan = DuckAIPromptWideEventData(
            modelId: nil,
            userTier: "free",
            reasoningEffort: nil,
            entryPoint: .aiTab,
            inputMode: .keyboard,
            fireMode: false,
            isFirstPrompt: true,
            frontendDeliveryPath: .userScript,
            hasPageContext: false,
            toolsSelected: false,
            attachmentsSelected: false,
            startedAt: Self.baseNow
        )
        let (_, wideEvent, _) = makeSUT(
            completeOrphanedFlowsOnInit: true,
            seededFlows: [orphan]
        )

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected an orphan completion")
            return
        }
        #expect(completion.1 == .unknown(reason: DuckAIPromptWideEventData.appTerminatedReason))
    }

    @available(iOS 16, *)
    @Test("Init with completeOrphanedFlowsOnInit=false leaves seeded flows untouched", .timeLimit(.minutes(1)))
    func orphanRecoveryFlagOffDoesNotComplete() {
        let orphan = DuckAIPromptWideEventData(
            modelId: nil,
            userTier: "free",
            reasoningEffort: nil,
            entryPoint: .aiTab,
            inputMode: .keyboard,
            fireMode: false,
            isFirstPrompt: true,
            frontendDeliveryPath: .userScript,
            hasPageContext: false,
            toolsSelected: false,
            attachmentsSelected: false,
            startedAt: Self.baseNow
        )
        let (_, wideEvent, _) = makeSUT(seededFlows: [orphan])

        #expect(wideEvent.completions.isEmpty)
    }

    // MARK: - Event data

    @available(iOS 16, *)
    @Test("Metadata exposes expected names and schema version", .timeLimit(.minutes(1)))
    func metadataExposesExpectedValues() {
        #expect(DuckAIPromptWideEventData.metadata.pixelName == "duckai_prompt")
        #expect(DuckAIPromptWideEventData.metadata.featureName == "duckai-prompt")
        #expect(DuckAIPromptWideEventData.metadata.type == "ios-duckai-prompt")
        #expect(DuckAIPromptWideEventData.metadata.version == "1.1.0")
    }

    @available(iOS 16, *)
    @Test("Default JSON parameters include stable dimensions and omit unset optionals", .timeLimit(.minutes(1)))
    func defaultJSONParametersIncludeStableDimensions() {
        let data = makeData(modelId: nil, reasoningEffort: nil)

        let params = data.jsonParameters()

        #expect(params["feature.data.ext.prompt.model_id"] == nil)
        #expect(params["feature.data.ext.prompt.reasoning_effort"] == nil)
        #expect(params["feature.data.ext.outcome.last_step"] == nil)
        #expect(params["feature.data.ext.outcome.cancellation_reason"] == nil)
        #expect(params["feature.data.ext.delivery.did_send_bridge_message"] == nil)
        #expect(params["feature.data.ext.prompt.user_tier"] as? String == "plus")
        #expect(params["feature.data.ext.prompt.entry_point"] as? String == "omnibar")
        #expect(params["feature.data.ext.prompt.input_mode"] as? String == "keyboard")
        #expect(params["feature.data.ext.delivery.path"] as? String == "url_autosubmit")
        #expect(params["feature.data.ext.prompt.fire_mode"] as? Bool == true)
        #expect(params["feature.data.ext.prompt.is_first_prompt"] as? Bool == false)
        #expect(params["feature.data.ext.delivery.queued"] as? Bool == false)
        #expect(params["feature.data.ext.delivery.did_receive_bridge_message"] as? Bool == false)
        #expect(params["feature.data.ext.delivery.did_attempt_delivery"] as? Bool == false)
        #expect(params["feature.data.ext.prompt.has_page_context"] as? Bool == true)
        #expect(params["feature.data.ext.prompt.tools_selected"] as? Bool == true)
        #expect(params["feature.data.ext.prompt.attachments_selected"] as? Bool == true)
    }

    @available(iOS 16, *)
    @Test("did_attempt_delivery is emitted true once set", .timeLimit(.minutes(1)))
    func didAttemptDeliveryEmittedWhenSet() {
        let data = makeData()
        data.didAttemptDelivery = true

        let params = data.jsonParameters()

        #expect(params["feature.data.ext.delivery.did_attempt_delivery"] as? Bool == true)
    }

    @available(iOS 16, *)
    @Test("Latency fields are bucketed when intervals are closed", .timeLimit(.minutes(1)))
    func latencyFieldsAreBucketed() {
        let data = makeData()
        data.startThinkingInterval.end = Self.baseNow.addingTimeInterval(0.1)
        data.startGeneratingInterval.end = Self.baseNow.addingTimeInterval(0.5)
        data.generatingCompletedInterval.end = Self.baseNow.addingTimeInterval(3.1)
        data.endedInterval.end = Self.baseNow.addingTimeInterval(11.0)
        data.frontendSubmissionAckInterval.end = Self.baseNow.addingTimeInterval(2.0)

        let params = data.jsonParameters()

        #expect(params["feature.data.ext.latency.start_thinking_ms"] as? Int == 100)
        #expect(params["feature.data.ext.latency.start_generating_ms"] as? Int == 500)
        #expect(params["feature.data.ext.latency.generating_completed_ms"] as? Int == 5_000)
        #expect(params["feature.data.ext.latency.ended_ms"] as? Int == 30_000)
        #expect(params["feature.data.ext.latency.frontend_submission_ack_ms"] as? Int == 2_000)
        #expect(params["feature.data.ext.delivery.did_receive_bridge_message"] as? Bool == true)
    }

    @available(iOS 16, *)
    @Test("Completion decision keeps pending for app launch cleanup", .timeLimit(.minutes(1)))
    func completionDecisionKeepsPendingForAppLaunch() async {
        let data = makeData()

        let decision = await data.completionDecision(for: .appLaunch)

        if case .keepPending = decision {
            // Expected: app-session orphan cleanup is owned by DefaultDuckAIWideEventInstrumentation.
        } else {
            Issue.record("Expected .keepPending, got \(decision)")
        }
    }

    @available(iOS 16, *)
    @Test("Codable round trip preserves prompt submission fields", .timeLimit(.minutes(1)))
    func codableRoundTripPreservesFields() throws {
        let data = makeData()
        data.lastStep = .streaming
        data.cancellationReason = .switchedTabs
        data.frontendDeliveryQueued = true
        data.didSendBridgeMessage = false
        data.didAttemptDelivery = true
        data.startThinkingInterval.end = Self.baseNow.addingTimeInterval(1.0)
        data.startGeneratingInterval.end = Self.baseNow.addingTimeInterval(2.0)
        data.generatingCompletedInterval.end = Self.baseNow.addingTimeInterval(3.0)
        data.endedInterval.end = Self.baseNow.addingTimeInterval(4.0)
        data.frontendSubmissionAckInterval.end = Self.baseNow.addingTimeInterval(5.0)

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(DuckAIPromptWideEventData.self, from: encoded)

        #expect(decoded.modelId == "claude-3")
        #expect(decoded.userTier == "plus")
        #expect(decoded.reasoningEffort == "medium")
        #expect(decoded.entryPoint == .omnibar)
        #expect(decoded.inputMode == .keyboard)
        #expect(decoded.fireMode == true)
        #expect(decoded.isFirstPrompt == false)
        #expect(decoded.lastStep == .streaming)
        #expect(decoded.cancellationReason == .switchedTabs)
        #expect(decoded.frontendDeliveryPath == .urlAutoSubmit)
        #expect(decoded.frontendDeliveryQueued == true)
        #expect(decoded.didSendBridgeMessage == false)
        #expect(decoded.didAttemptDelivery == true)
        #expect(decoded.hasPageContext == true)
        #expect(decoded.toolsSelected == true)
        #expect(decoded.attachmentsSelected == true)
        #expect(decoded.startThinkingInterval.end == Self.baseNow.addingTimeInterval(1.0))
        #expect(decoded.startGeneratingInterval.end == Self.baseNow.addingTimeInterval(2.0))
        #expect(decoded.generatingCompletedInterval.end == Self.baseNow.addingTimeInterval(3.0))
        #expect(decoded.endedInterval.end == Self.baseNow.addingTimeInterval(4.0))
        #expect(decoded.frontendSubmissionAckInterval.end == Self.baseNow.addingTimeInterval(5.0))
    }
}
