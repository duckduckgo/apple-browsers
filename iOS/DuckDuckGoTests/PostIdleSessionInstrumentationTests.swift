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

    private func lastCompletion(_ wideEvent: WideEventMock) -> (PostIdleSessionWideEventData, WideEventStatus)? {
        guard let last = wideEvent.completions.last,
              let data = last.0 as? PostIdleSessionWideEventData else { return nil }
        return (data, last.1)
    }

    // MARK: - No active session

    @available(iOS 16, *)
    @Test("When no active session then sessionEnded is a no-op", .timeLimit(.minutes(1)))
    func sessionEndedWithoutActiveSessionIsNoop() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionEnded(reason: .barUsed)
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
        #expect(wideEvent.updates.isEmpty)
    }

    // MARK: - sessionStarted

    @available(iOS 16, *)
    @Test("When sessionStarted with ntp then a flow is started with surface=ntp", .timeLimit(.minutes(1)))
    func sessionStartedNtpStartsFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        let started = startedData(wideEvent)
        #expect(started?.surface == .ntp)
    }

    @available(iOS 16, *)
    @Test("When sessionStarted with lut then a flow is started with surface=lut", .timeLimit(.minutes(1)))
    func sessionStartedLutStartsFlow() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(surface: .lut)
        let started = startedData(wideEvent)
        #expect(started?.surface == .lut)
    }

    @available(iOS 16, *)
    @Test("Restarting cancels the previous active session", .timeLimit(.minutes(1)))
    func restartingSessionCancelsPrevious() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        clock.advance(by: 1)
        sut.sessionStarted(surface: .ntp)

        guard let cancelled = wideEvent.completions.first,
              let data = cancelled.0 as? PostIdleSessionWideEventData else {
            Issue.record("Expected a cancelled completion")
            return
        }
        #expect(data.statusReason == .appBackgrounded)
        if case .cancelled = cancelled.1 {} else {
            Issue.record("Expected .cancelled status, got \(cancelled.1)")
        }
        #expect(wideEvent.started.count == 2)
    }

    // MARK: - Non-terminal updates

    @available(iOS 16, *)
    @Test("pageEngaged sets pageEngaged=true and marks first interaction", .timeLimit(.minutes(1)))
    func pageEngagedSetsFlagsAndFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        clock.advance(by: 0.5)
        sut.pageEngaged()

        let last = wideEvent.updates.compactMap { $0 as? PostIdleSessionWideEventData }.last
        #expect(last?.pageEngaged == true)
        #expect(last?.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("toggleUsed sets toggleUsed=true", .timeLimit(.minutes(1)))
    func toggleUsedSetsFlag() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        sut.toggleUsed()
        let last = wideEvent.updates.compactMap { $0 as? PostIdleSessionWideEventData }.last
        #expect(last?.toggleUsed == true)
    }

    @available(iOS 16, *)
    @Test("backPressed sets backPressed=true", .timeLimit(.minutes(1)))
    func backPressedSetsFlag() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        sut.backPressed()
        let last = wideEvent.updates.compactMap { $0 as? PostIdleSessionWideEventData }.last
        #expect(last?.backPressed == true)
    }

    @available(iOS 16, *)
    @Test("First interaction is only set once across multiple updates", .timeLimit(.minutes(1)))
    func firstInteractionMarkedOnlyOnce() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(surface: .ntp)

        clock.advance(by: 0.5)
        let firstStamp = clock.now
        sut.pageEngaged()

        clock.advance(by: 1.0)
        sut.toggleUsed()

        let last = wideEvent.updates.compactMap { $0 as? PostIdleSessionWideEventData }.last
        #expect(last?.firstInteractionInterval.end == firstStamp)
    }

    // MARK: - Terminal events

    @available(iOS 16, *)
    @Test("sessionEnded completes flow as success with given reason", .timeLimit(.minutes(1)))
    func sessionEndedCompletesAsSuccess() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        clock.advance(by: 2)
        sut.sessionEnded(reason: .barUsed)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.statusReason == .barUsed)
        #expect(completion.0.sessionInterval.end == clock.now)
        if case .success(let reason) = completion.1 {
            #expect(reason == "bar_used")
        } else {
            Issue.record("Expected .success status, got \(completion.1)")
        }
    }

    @available(iOS 16, *)
    @Test("sessionEnded sets first interaction if not yet set", .timeLimit(.minutes(1)))
    func sessionEndedMarksFirstInteractionIfNotSet() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        clock.advance(by: 1.5)
        sut.sessionEnded(reason: .barUsed)
        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("sessionEnded preserves prior first-interaction timestamp", .timeLimit(.minutes(1)))
    func sessionEndedPreservesEarlierFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        clock.advance(by: 0.5)
        let firstStamp = clock.now
        sut.pageEngaged()
        clock.advance(by: 2)
        sut.sessionEnded(reason: .barUsed)
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
        sut.sessionStarted(surface: .ntp)
        sut.sessionEnded(reason: .barUsed)
        // Subsequent signals should be no-ops.
        sut.pageEngaged()
        sut.sessionEnded(reason: .returnToPageTapped)
        #expect(wideEvent.completions.count == 1)
    }

    // MARK: - Cancellation

    @available(iOS 16, *)
    @Test("sessionCancelledByBackground completes as cancelled with app_backgrounded", .timeLimit(.minutes(1)))
    func sessionCancelledCompletesAsCancelled() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.sessionStarted(surface: .ntp)
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
    }

    @available(iOS 16, *)
    @Test("sessionCancelledByBackground clears the active session", .timeLimit(.minutes(1)))
    func sessionCancelledClearsActiveSession() {
        let (sut, wideEvent, _) = makeSUT()
        sut.sessionStarted(surface: .ntp)
        sut.sessionCancelledByBackground()
        sut.sessionCancelledByBackground()
        #expect(wideEvent.completions.count == 1)
    }
}
