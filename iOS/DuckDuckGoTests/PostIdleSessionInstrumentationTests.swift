//
//  PostIdleSessionInstrumentationTests.swift
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
import Testing
import PixelKit
import PixelKitTestingUtilities
@testable import DuckDuckGo

@Suite("Post Idle Session Instrumentation")
struct PostIdleSessionInstrumentationTests {

    private final class MockClock {
        var now: Date
        init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.now = start }
        func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func makeSUT() -> (DefaultPostIdleSessionInstrumentation, WideEventMock, MockClock) {
        let wideEvent = WideEventMock()
        let clock = MockClock()
        let sut = DefaultPostIdleSessionInstrumentation(
            wideEvent: wideEvent,
            dateProvider: { clock.now }
        )
        return (sut, wideEvent, clock)
    }

    private func startedData(_ wideEvent: WideEventMock) -> PostIdleSessionWideEventData? {
        wideEvent.started.compactMap { $0 as? PostIdleSessionWideEventData }.last
    }

    private func startedReturnData(_ wideEvent: WideEventMock) -> ReturnSessionWideEventData? {
        wideEvent.started.compactMap { $0 as? ReturnSessionWideEventData }.last
    }

    private func lastUpdate(_ wideEvent: WideEventMock) -> PostIdleSessionWideEventData? {
        wideEvent.updates.compactMap { $0 as? PostIdleSessionWideEventData }.last
    }

    private func lastReturnUpdate(_ wideEvent: WideEventMock) -> ReturnSessionWideEventData? {
        wideEvent.updates.compactMap { $0 as? ReturnSessionWideEventData }.last
    }

    private func lastCompletion(_ wideEvent: WideEventMock) -> (PostIdleSessionWideEventData, WideEventStatus)? {
        guard let last = wideEvent.completions.last(where: { $0.0 is PostIdleSessionWideEventData }),
              let data = last.0 as? PostIdleSessionWideEventData else { return nil }
        return (data, last.1)
    }

    private func lastReturnCompletion(_ wideEvent: WideEventMock) -> (ReturnSessionWideEventData, WideEventStatus)? {
        guard let last = wideEvent.completions.last(where: { $0.0 is ReturnSessionWideEventData }),
              let data = last.0 as? ReturnSessionWideEventData else { return nil }
        return (data, last.1)
    }

    // MARK: - No active session

    @available(iOS 16, *)
    @Test("When no active session then sessionEnded is a no-op", .timeLimit(.minutes(1)))
    func sessionEndedWithoutActiveSessionIsNoop() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionEnded(reason: .searchSubmitted)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("When no active session then sessionCancelledByBackground is a no-op", .timeLimit(.minutes(1)))
    func sessionCancelledWithoutActiveSessionIsNoop() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionCancelledByBackground()
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("When no active session then non-terminal updates are no-ops", .timeLimit(.minutes(1)))
    func nonTerminalUpdatesWithoutActiveSessionAreNoop() {
        let (sut, wideEvent, _) = makeSUT()
        sut.pageEngaged()
        sut.toggleUsed()
        sut.backPressed()
        sut.openingScreenChanged()
        sut.closeTabTapped()
        sut.burnTabTapped()
        #expect(wideEvent.updates.isEmpty)
    }

    // MARK: - sessionStarted

    @available(iOS 16, *)
    @Test("When sessionStarted with ntp then a flow is started with surface=ntp", .timeLimit(.minutes(1)))
    func sessionStartedNtpStartsFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        #expect(startedData(wideEvent)?.surface == .ntp)
    }

    @available(iOS 16, *)
    @Test("When sessionStarted with lut then a flow is started with surface=lut", .timeLimit(.minutes(1)))
    func sessionStartedLutStartsFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .web, afterIdleSurface: .lut, focused: false)
        #expect(startedData(wideEvent)?.surface == .lut)
    }

    @available(iOS 16, *)
    @Test("An after-idle return starts both the return-session and post-idle flows", .timeLimit(.minutes(1)))
    func afterIdleReturnStartsBothFlows() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: true)

        #expect(wideEvent.started.count == 2)
        #expect(startedData(wideEvent)?.surface == .ntp)
        #expect(startedReturnData(wideEvent)?.landedOn == .ntp)
        #expect(startedReturnData(wideEvent)?.afterIdle == true)
        #expect(startedReturnData(wideEvent)?.focused == true)
    }

    @available(iOS 16, *)
    @Test("An ordinary return starts only the return-session flow", .timeLimit(.minutes(1)))
    func ordinaryReturnStartsOnlyReturnSessionFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .serp, afterIdleSurface: nil, focused: false)

        #expect(wideEvent.started.count == 1)
        #expect(startedData(wideEvent) == nil)
        #expect(startedReturnData(wideEvent)?.landedOn == .serp)
        #expect(startedReturnData(wideEvent)?.afterIdle == false)
    }

    @available(iOS 16, *)
    @Test("The post-idle surface follows the treatment, not the landing", .timeLimit(.minutes(1)))
    func postIdleSurfaceFollowsTreatment() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntpUserInitiated, afterIdleSurface: .lut, focused: false)
        #expect(startedData(wideEvent)?.surface == .lut)
    }

    @available(iOS 16, *)
    @Test("Both flows share the session start date", .timeLimit(.minutes(1)))
    func bothFlowsShareStartDate() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        #expect(startedData(wideEvent)?.sessionInterval.start == clock.now)
        #expect(startedReturnData(wideEvent)?.sessionInterval.start == clock.now)
    }

    @available(iOS 16, *)
    @Test("noteReturn's time away is consumed by the next sessionStarted only", .timeLimit(.minutes(1)))
    func noteReturnTimeAwayConsumedOnce() {
        let (sut, wideEvent, _) = makeSUT()
        sut.noteReturn(timeAwayMs: 42_000)

        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        #expect(startedReturnData(wideEvent)?.timeAwayMs == 42_000)

        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        #expect(startedReturnData(wideEvent)?.timeAwayMs == nil)
    }

    @available(iOS 16, *)
    @Test("Restarting cancels the previous active session", .timeLimit(.minutes(1)))
    func restartingSessionCancelsPrevious() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 1)
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)

        guard let cancelled = wideEvent.completions.first(where: { $0.0 is PostIdleSessionWideEventData }),
              let data = cancelled.0 as? PostIdleSessionWideEventData else {
            Issue.record("Expected a cancelled completion")
            return
        }
        #expect(data.statusReason == .appBackgrounded)
        if case .cancelled = cancelled.1 {} else {
            Issue.record("Expected .cancelled status, got \(cancelled.1)")
        }
        #expect(wideEvent.started.count == 4)
    }

    @available(iOS 16, *)
    @Test("An ordinary return after an after-idle session cancels the post-idle flow", .timeLimit(.minutes(1)))
    func ordinaryReturnCancelsLingeringPostIdleFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        sut.sessionStarted(landedOn: .web, afterIdleSurface: nil, focused: false)

        #expect(lastCompletion(wideEvent)?.0.statusReason == .appBackgrounded)
        #expect(startedReturnData(wideEvent)?.afterIdle == false)
    }

    // MARK: - Non-terminal updates

    @available(iOS 16, *)
    @Test("pageEngaged sets pageEngaged=true and marks first interaction", .timeLimit(.minutes(1)))
    func pageEngagedSetsFlagsAndFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 0.5)
        sut.pageEngaged()

        #expect(lastUpdate(wideEvent)?.pageEngaged == true)
        #expect(lastUpdate(wideEvent)?.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("Interactions are recorded on both in-flight flows", .timeLimit(.minutes(1)))
    func interactionsRecordedOnBothFlows() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 0.5)
        sut.pageEngaged()

        #expect(lastUpdate(wideEvent)?.pageEngaged == true)
        #expect(lastReturnUpdate(wideEvent)?.pageEngaged == true)
        #expect(lastReturnUpdate(wideEvent)?.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("Interactions on an ordinary return only touch the return-session flow", .timeLimit(.minutes(1)))
    func interactionsOnOrdinaryReturnOnlyTouchReturnFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .web, afterIdleSurface: nil, focused: false)
        sut.toggleUsed()

        #expect(lastReturnUpdate(wideEvent)?.toggleUsed == true)
        #expect(lastUpdate(wideEvent) == nil)
    }

    @available(iOS 16, *)
    @Test("toggleUsed sets toggleUsed=true", .timeLimit(.minutes(1)))
    func toggleUsedSetsFlag() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        sut.toggleUsed()
        #expect(lastUpdate(wideEvent)?.toggleUsed == true)
    }

    @available(iOS 16, *)
    @Test("backPressed sets backPressed=true", .timeLimit(.minutes(1)))
    func backPressedSetsFlag() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        sut.backPressed()
        #expect(lastUpdate(wideEvent)?.backPressed == true)
    }

    @available(iOS 16, *)
    @Test("openingScreenChanged sets flag and marks first interaction", .timeLimit(.minutes(1)))
    func openingScreenChangedSetsFlagsAndFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 0.75)
        sut.openingScreenChanged()

        #expect(lastUpdate(wideEvent)?.openingScreenChanged == true)
        #expect(lastUpdate(wideEvent)?.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("closeTabTapped sets closeTabTapped=true and marks first interaction", .timeLimit(.minutes(1)))
    func closeTabTappedSetsFlagAndFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 0.5)
        sut.closeTabTapped()

        #expect(lastUpdate(wideEvent)?.closeTabTapped == true)
        #expect(lastUpdate(wideEvent)?.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("burnTabTapped sets burnTabTapped=true and marks first interaction", .timeLimit(.minutes(1)))
    func burnTabTappedSetsFlagAndFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 0.75)
        sut.burnTabTapped()

        #expect(lastUpdate(wideEvent)?.burnTabTapped == true)
        #expect(lastUpdate(wideEvent)?.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("First interaction is only set once across multiple updates", .timeLimit(.minutes(1)))
    func firstInteractionMarkedOnlyOnce() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)

        clock.advance(by: 0.5)
        let firstStamp = clock.now
        sut.pageEngaged()

        clock.advance(by: 1.0)
        sut.toggleUsed()

        #expect(lastUpdate(wideEvent)?.firstInteractionInterval.end == firstStamp)
        #expect(lastReturnUpdate(wideEvent)?.firstInteractionInterval.end == firstStamp)
    }

    // MARK: - Terminal events

    @available(iOS 16, *)
    @Test("sessionEnded completes flow as success with given reason", .timeLimit(.minutes(1)))
    func sessionEndedCompletesAsSuccess() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 2)
        sut.sessionEnded(reason: .searchSubmitted)

        guard let completion = lastReturnCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.statusReason == .searchSubmitted)
        #expect(completion.0.sessionInterval.end == clock.now)
        if case .success(let reason) = completion.1 {
            #expect(reason == "search_submitted")
        } else {
            Issue.record("Expected .success status, got \(completion.1)")
        }
    }

    @available(iOS 16, *)
    @Test("The post-idle flow collapses the submission split back onto bar_used", .timeLimit(.minutes(1)))
    func postIdleFlowCollapsesSubmissionsOntoBarUsed() {
        for reason in [ReturnSessionWideEventData.StatusReason.searchSubmitted, .aiPromptSubmitted, .urlSubmitted] {
            let (sut, wideEvent, _) = makeSUT()
            sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
            sut.sessionEnded(reason: reason)

            guard let completion = lastCompletion(wideEvent) else {
                Issue.record("Expected a post-idle completion for \(reason)")
                return
            }
            #expect(completion.0.statusReason == .barUsed)
            if case .success(let statusReason) = completion.1 {
                #expect(statusReason == "bar_used")
            } else {
                Issue.record("Expected .success status, got \(completion.1)")
            }
        }
    }

    @available(iOS 16, *)
    @Test("Non-submission reasons pass through to the post-idle flow unchanged", .timeLimit(.minutes(1)))
    func nonSubmissionReasonsPassThroughUnchanged() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        sut.sessionEnded(reason: .returnToPageTapped)
        #expect(lastCompletion(wideEvent)?.0.statusReason == .returnToPageTapped)
    }

    @available(iOS 16, *)
    @Test("sessionEnded on an ordinary return completes only the return-session flow", .timeLimit(.minutes(1)))
    func sessionEndedOnOrdinaryReturnCompletesOnlyReturnFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .web, afterIdleSurface: nil, focused: false)
        sut.sessionEnded(reason: .urlSubmitted)

        #expect(wideEvent.completions.count == 1)
        #expect(lastReturnCompletion(wideEvent)?.0.statusReason == .urlSubmitted)
    }

    @available(iOS 16, *)
    @Test("sessionEnded sets first interaction if not yet set", .timeLimit(.minutes(1)))
    func sessionEndedMarksFirstInteractionIfNotSet() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 1.5)
        sut.sessionEnded(reason: .searchSubmitted)
        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.firstInteractionInterval.end == clock.now)
        #expect(lastReturnCompletion(wideEvent)?.0.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("sessionEnded preserves prior first-interaction timestamp", .timeLimit(.minutes(1)))
    func sessionEndedPreservesEarlierFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 0.5)
        let firstStamp = clock.now
        sut.pageEngaged()
        clock.advance(by: 2)
        sut.sessionEnded(reason: .searchSubmitted)
        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.firstInteractionInterval.end == firstStamp)
    }

    @available(iOS 16, *)
    @Test("sessionEnded clears the active session", .timeLimit(.minutes(1)))
    func sessionEndedClearsActiveSession() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        sut.sessionEnded(reason: .searchSubmitted)
        // Subsequent signals should be no-ops.
        sut.pageEngaged()
        sut.sessionEnded(reason: .returnToPageTapped)
        #expect(wideEvent.completions.count == 2)
    }

    // MARK: - Cancellation

    @available(iOS 16, *)
    @Test("sessionCancelledByBackground completes as cancelled with app_backgrounded", .timeLimit(.minutes(1)))
    func sessionCancelledCompletesAsCancelled() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        clock.advance(by: 3)
        sut.sessionCancelledByBackground()

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.statusReason == .appBackgrounded)
        #expect(completion.0.sessionInterval.end == clock.now)
        if case .cancelled = completion.1 {} else {
            Issue.record("Expected .cancelled status, got \(completion.1)")
        }
        #expect(lastReturnCompletion(wideEvent)?.0.statusReason == .appBackgrounded)
    }

    @available(iOS 16, *)
    @Test("sessionCancelledByBackground clears the active session", .timeLimit(.minutes(1)))
    func sessionCancelledClearsActiveSession() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        sut.sessionCancelledByBackground()
        sut.sessionCancelledByBackground()
        #expect(wideEvent.completions.count == 2)
    }

    // MARK: - Orphan cleanup

    @available(iOS 16, *)
    @Test("sessionStarted completes orphaned flows as UNKNOWN with app_terminated", .timeLimit(.minutes(1)))
    func sessionStartedCompletesOrphansAsAppTerminated() {
        let (sut, wideEvent, _) = makeSUT()
        let orphan = PostIdleSessionWideEventData(surface: .ntp)
        wideEvent.startFlow(orphan)

        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)

        let orphanCompletion = wideEvent.completions.first {
            ($0.0 as? PostIdleSessionWideEventData)?.globalData.id == orphan.globalData.id
        }
        guard let orphanCompletion else {
            Issue.record("Expected the orphan to be completed")
            return
        }
        if case .unknown(let reason) = orphanCompletion.1 {
            #expect(reason == PostIdleSessionWideEventData.appTerminatedReason)
        } else {
            Issue.record("Expected .unknown status, got \(orphanCompletion.1)")
        }
    }

    @available(iOS 16, *)
    @Test("Orphaned return-session flows are completed too", .timeLimit(.minutes(1)))
    func orphanedReturnSessionFlowsAreCompleted() {
        let (sut, wideEvent, _) = makeSUT()
        let orphan = ReturnSessionWideEventData(landedOn: .web, afterIdle: false)
        wideEvent.startFlow(orphan)

        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)

        let orphanCompletion = wideEvent.completions.first {
            ($0.0 as? ReturnSessionWideEventData)?.globalData.id == orphan.globalData.id
        }
        guard let orphanCompletion else {
            Issue.record("Expected the orphan to be completed")
            return
        }
        if case .unknown(let reason) = orphanCompletion.1 {
            #expect(reason == ReturnSessionWideEventData.appTerminatedReason)
        } else {
            Issue.record("Expected .unknown status, got \(orphanCompletion.1)")
        }
    }

    @available(iOS 16, *)
    @Test("Orphan cleanup happens before the new flow is started", .timeLimit(.minutes(1)))
    func orphanCleanupHappensBeforeNewFlowStarts() {
        let (sut, wideEvent, _) = makeSUT()
        let orphan = PostIdleSessionWideEventData(surface: .ntp)
        wideEvent.startFlow(orphan)

        sut.sessionStarted(landedOn: .web, afterIdleSurface: .lut, focused: false)

        #expect(wideEvent.started.count == 3)
        #expect(startedData(wideEvent)?.surface == .lut)
        let orphanCompleted = wideEvent.completions.contains {
            ($0.0 as? PostIdleSessionWideEventData)?.globalData.id == orphan.globalData.id
        }
        #expect(orphanCompleted)
    }

    @available(iOS 16, *)
    @Test("Multiple orphans are all completed", .timeLimit(.minutes(1)))
    func multipleOrphansAllCompleted() {
        let (sut, wideEvent, _) = makeSUT()
        let firstOrphan = PostIdleSessionWideEventData(surface: .ntp)
        let secondOrphan = PostIdleSessionWideEventData(surface: .lut)
        wideEvent.startFlow(firstOrphan)
        wideEvent.startFlow(secondOrphan)

        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)

        let unknownCompletions = wideEvent.completions.filter {
            if case .unknown = $0.1 { return true } else { return false }
        }
        #expect(unknownCompletions.count == 2)
    }

    @available(iOS 16, *)
    @Test("sessionStarted with no orphans does not produce spurious completions", .timeLimit(.minutes(1)))
    func sessionStartedWithoutOrphansProducesNoCompletions() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(landedOn: .ntp, afterIdleSurface: .ntp, focused: false)
        #expect(wideEvent.completions.isEmpty)
    }
}
