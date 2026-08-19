//
//  PixelTransmissionDelayTests.swift
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
@testable import DuckDuckGo

/// Shared with `AppReturnInstrumentationTests`, which needs to observe the same release.
final class FakeBackgroundAssertion: BackgroundAssertion {
    var systemDidReleaseAssertion: (() -> Void)?
    var releaseCount = 0

    func release() {
        releaseCount += 1
    }
}

@Suite("Pixel Transmission Delay")
struct PixelTransmissionDelayTests {

    private final class Scheduler {
        private(set) var intervals: [TimeInterval] = []
        private var work: [() -> Void] = []

        var interval: TimeInterval? { intervals.first }

        func schedule(_ interval: TimeInterval, _ work: @escaping () -> Void) {
            intervals.append(interval)
            self.work.append(work)
        }

        /// Deliberately keeps the work, so re-firing a scheduled send is possible.
        func elapse(_ index: Int = 0) {
            work[index]()
        }
    }

    private final class SendSpy {
        var count = 0
        var requestsPerSend = 1
        private var tokens: [PixelSendToken] = []

        /// Stands in for a send: records the call and holds the token once per request it starts,
        /// the way `.dailyAndCount` hands the same completion to both of its requests.
        func send(_ keepAppAwake: PixelSendToken) {
            count += 1
            tokens.append(contentsOf: Array(repeating: keepAppAwake, count: requestsPerSend))
        }

        /// One of the requests came back.
        func finishRequest() {
            if !tokens.isEmpty {
                tokens.removeLast()
            }
        }
    }

    private func makeSUT(interval: TimeInterval = 5,
                         budget: TimeInterval = .greatestFiniteMagnitude,
                         makeAssertion: @escaping () -> BackgroundAssertion? = { nil }) -> (PixelTransmissionDelay, Scheduler) {
        let scheduler = Scheduler()
        let sut = PixelTransmissionDelay(
            interval: { interval },
            makeAssertion: makeAssertion,
            backgroundTimeRemaining: { budget },
            runOnMain: { $0() },
            schedule: scheduler.schedule)
        return (sut, scheduler)
    }

    // MARK: - Deferral

    @Test("When a send is delayed then it does not run before the wait elapses")
    func whenSendIsDelayedThenItDoesNotRunImmediately() {
        let (sut, scheduler) = makeSUT(interval: 12)
        let spy = SendSpy()

        sut.delaySend(spy.send)

        #expect(spy.count == 0)
        #expect(scheduler.interval == 12)
    }

    @Test("When the wait elapses then the send runs")
    func whenWaitElapsesThenSendRuns() {
        let (sut, scheduler) = makeSUT()
        let spy = SendSpy()

        sut.delaySend(spy.send)
        scheduler.elapse()

        #expect(spy.count == 1)
    }

    @Test("When the wait elapses twice then the send runs only once")
    func whenWaitElapsesTwiceThenSendRunsOnce() {
        let (sut, scheduler) = makeSUT(makeAssertion: { FakeBackgroundAssertion() })
        let spy = SendSpy()

        sut.delaySend(spy.send)
        scheduler.elapse()
        scheduler.elapse()

        #expect(spy.count == 1)
    }

    @Test("When two sends are delayed then each gets its own assertion and wait")
    func whenTwoSendsAreDelayedThenEachGetsItsOwnAssertion() {
        var assertions: [FakeBackgroundAssertion] = []
        var intervals: [TimeInterval] = [4, 9]
        let scheduler = Scheduler()
        let sut = PixelTransmissionDelay(
            interval: { intervals.removeFirst() },
            makeAssertion: {
                let assertion = FakeBackgroundAssertion()
                assertions.append(assertion)
                return assertion
            },
            backgroundTimeRemaining: { .greatestFiniteMagnitude },
            runOnMain: { $0() },
            schedule: scheduler.schedule)
        let first = SendSpy()
        let second = SendSpy()

        sut.delaySend(first.send)
        sut.delaySend(second.send)
        scheduler.elapse(1)

        #expect(scheduler.intervals == [4, 9])
        #expect(assertions.count == 2)
        #expect(first.count == 0)
        #expect(second.count == 1)
        // Finishing the second send leaves the first one's assertion untouched.
        second.finishRequest()
        #expect(assertions[0].releaseCount == 0)
        #expect(assertions[1].releaseCount == 1)
    }

    // MARK: - Background budget

    @Test("When the app is foregrounded then the full agreed wait is used")
    func whenAppIsForegroundedThenFullAgreedWaitIsUsed() {
        // `backgroundTimeRemaining` reports `.greatestFiniteMagnitude` while foregrounded.
        let (sut, scheduler) = makeSUT(interval: 30, budget: .greatestFiniteMagnitude)

        sut.delaySend(SendSpy().send)

        #expect(scheduler.interval == 30)
    }

    @Test("When the background budget is shorter than the wait then the wait is trimmed to fit")
    func whenBudgetIsShorterThanWaitThenWaitIsTrimmed() {
        // 10s of the budget is kept back for the request itself.
        let (sut, scheduler) = makeSUT(interval: 30, budget: 25)

        sut.delaySend(SendSpy().send)

        #expect(scheduler.interval == 15)
    }

    @Test("When the background budget is nearly gone then the shortest agreed wait is used")
    func whenBudgetIsNearlyGoneThenShortestAgreedWaitIsUsed() {
        let (sut, scheduler) = makeSUT(interval: 30, budget: 2)

        sut.delaySend(SendSpy().send)

        #expect(scheduler.interval == PixelTransmissionDelay.range.lowerBound)
    }

    @Test("When the budget is ample then a short wait is left alone")
    func whenBudgetIsAmpleThenShortWaitIsLeftAlone() {
        let (sut, scheduler) = makeSUT(interval: 3, budget: 25)

        sut.delaySend(SendSpy().send)

        #expect(scheduler.interval == 3)
    }

    // MARK: - Background assertion

    @Test("When a send is delayed then the assertion is taken once, up front")
    func whenSendIsDelayedThenAssertionIsTakenOnceUpFront() {
        var made = 0
        let scheduler = Scheduler()
        let sut = PixelTransmissionDelay(
            interval: { 5 },
            makeAssertion: {
                made += 1
                return FakeBackgroundAssertion()
            },
            backgroundTimeRemaining: { .greatestFiniteMagnitude },
            runOnMain: { $0() },
            schedule: scheduler.schedule)

        sut.delaySend(SendSpy().send)

        // Taken when the send is handed over, not when the wait elapses.
        #expect(made == 1)

        scheduler.elapse()

        #expect(made == 1)
    }

    @Test("When the system reclaims the background assertion then the send runs without waiting")
    func whenAssertionExpiresThenSendRunsWithoutWaiting() {
        let assertion = FakeBackgroundAssertion()
        let (sut, _) = makeSUT(makeAssertion: { assertion })
        let spy = SendSpy()

        sut.delaySend(spy.send)
        assertion.systemDidReleaseAssertion?()

        #expect(spy.count == 1)
    }

    @Test("When the wait elapses after the assertion expired then the send runs only once")
    func whenWaitElapsesAfterExpiryThenSendRunsOnce() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(makeAssertion: { assertion })
        let spy = SendSpy()

        sut.delaySend(spy.send)
        assertion.systemDidReleaseAssertion?()
        scheduler.elapse()

        #expect(spy.count == 1)
    }

    @Test("When the request is still in flight then the background assertion is still held")
    func whenRequestIsInFlightThenAssertionIsStillHeld() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(makeAssertion: { assertion })
        let spy = SendSpy()

        sut.delaySend(spy.send)
        #expect(assertion.releaseCount == 0)

        scheduler.elapse()

        // The send has been kicked off but its request has not come back yet.
        #expect(spy.count == 1)
        #expect(assertion.releaseCount == 0)
    }

    @Test("When the request finishes then the background assertion is released")
    func whenRequestFinishesThenAssertionIsReleased() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(makeAssertion: { assertion })
        let spy = SendSpy()

        sut.delaySend(spy.send)
        scheduler.elapse()
        spy.finishRequest()

        #expect(assertion.releaseCount == 1)
    }

    @Test("When a send starts two requests then the assertion is held until the last one finishes")
    func whenSendStartsTwoRequestsThenAssertionHeldUntilLastFinishes() {
        // `.dailyAndCount` fires the daily and the count request off the same completion, so the
        // first request to come back must not end the assertion.
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(makeAssertion: { assertion })
        let spy = SendSpy()
        spy.requestsPerSend = 2

        sut.delaySend(spy.send)
        scheduler.elapse()
        spy.finishRequest()

        #expect(assertion.releaseCount == 0)

        spy.finishRequest()

        #expect(assertion.releaseCount == 1)
    }

    @Test("When a send never reports back then the assertion is released as it is let go")
    func whenSendNeverReportsBackThenAssertionIsReleasedWhenLetGo() {
        // Nothing holds the token, e.g. `PixelKit.shared` was nil and the fire never happened.
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(makeAssertion: { assertion })

        sut.delaySend { _ in }
        scheduler.elapse()

        #expect(assertion.releaseCount == 1)
    }

    @Test("When the release is triggered then it goes through the main-queue hop")
    func whenReleaseIsTriggeredThenItGoesThroughTheMainQueueHop() {
        let assertion = FakeBackgroundAssertion()
        let scheduler = Scheduler()
        var hops = 0
        let sut = PixelTransmissionDelay(
            interval: { 5 },
            makeAssertion: { assertion },
            backgroundTimeRemaining: { .greatestFiniteMagnitude },
            runOnMain: { work in
                hops += 1
                work()
            },
            schedule: scheduler.schedule)
        let spy = SendSpy()

        sut.delaySend(spy.send)
        // Taking the assertion is the first hop.
        #expect(hops == 1)

        scheduler.elapse()
        #expect(hops == 1)

        // PixelKit's iOS fire request calls back off the main thread, and releasing asserts on it.
        spy.finishRequest()

        #expect(hops == 2)
        #expect(assertion.releaseCount == 1)
    }

    @available(iOS 16, *)
    @Test("When the delay runs against the real assertion then no main-queue precondition trips", .timeLimit(.minutes(1)))
    func whenDelayRunsAgainstRealAssertionThenNoMainQueuePreconditionTrips() async {
        // The assertion, the hop and the scheduler are the production ones here, so a hop the code
        // forgets to make trips `QRunInBackgroundAssertion`'s preconditions in this test rather
        // than in the field. Only the wait is shortened.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var hops = 0
            let sut = PixelTransmissionDelay(
                interval: { 0.01 },
                runOnMain: { work in
                    DispatchQueue.main.async {
                        work()
                        hops += 1
                        // The second hop is the release, queued by the token as the send let it go.
                        if hops == 2 {
                            continuation.resume()
                        }
                    }
                })

            sut.delaySend { keepAppAwake in
                DispatchQueue.global().async {
                    withExtendedLifetime(keepAppAwake) { }
                }
            }
        }
    }
}

@Suite("Return Session Send Delaying Wide Event Sender")
struct ReturnSessionSendDelayingWideEventSenderTests {

    private final class SpyWideEventSender: WideEventSending {
        var sentPixelNames: [String] = []
        var sentStatuses: [WideEventStatus] = []
        var sentFeatureFlagProviders: [WideEventFeatureFlagProviding] = []
        private var onComplete: PixelKit.CompletionBlock?

        func send<T: WideEventData>(_ data: T,
                                    status: WideEventStatus,
                                    featureFlagProvider: WideEventFeatureFlagProviding,
                                    onComplete: @escaping PixelKit.CompletionBlock) {
            sentPixelNames.append(T.metadata.pixelName)
            sentStatuses.append(status)
            sentFeatureFlagProviders.append(featureFlagProvider)
            self.onComplete = onComplete
        }

        func finishRequest(success: Bool, error: Error? = nil) {
            onComplete?(success, error)
        }

        /// Drops the completion, the way the transport would once it is done with it.
        func letGoOfCompletion() {
            onComplete = nil
        }
    }

    private final class ImmediateDelay: PixelTransmissionDelaying {
        var delayedSends = 0
        let assertion = FakeBackgroundAssertion()

        func delaySend(_ send: @escaping (PixelSendToken) -> Void) {
            delayedSends += 1
            send(PixelSendToken(assertion: assertion, runOnMain: { $0() }))
        }
    }

    private struct StubFeatureFlagProvider: WideEventFeatureFlagProviding {
        func isEnabled(_ flag: WideEventFeatureFlag) -> Bool { true }
    }

    private func returnSessionData() -> ReturnSessionWideEventData {
        ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true)
    }

    @Test("When the return session event is sent then it goes through the delay")
    func whenReturnSessionEventIsSentThenItIsDelayed() {
        let wrapped = SpyWideEventSender()
        let delay = ImmediateDelay()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: delay)

        sut.send(returnSessionData(),
                 status: .cancelled,
                 featureFlagProvider: StubFeatureFlagProvider(),
                 onComplete: { _, _ in })

        #expect(delay.delayedSends == 1)
        #expect(wrapped.sentPixelNames == ["return_session"])
    }

    @Test("When any other wide event is sent then it is not delayed")
    func whenOtherWideEventIsSentThenItIsNotDelayed() {
        let wrapped = SpyWideEventSender()
        let delay = ImmediateDelay()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: delay)

        sut.send(PostIdleSessionWideEventData(surface: .ntp),
                 status: .cancelled,
                 featureFlagProvider: StubFeatureFlagProvider(),
                 onComplete: { _, _ in })

        #expect(delay.delayedSends == 0)
        #expect(wrapped.sentPixelNames == ["post_idle_session"])
    }

    @Test("When the delayed send completes then the caller is told")
    func whenDelayedSendCompletesThenCallerIsTold() {
        let wrapped = SpyWideEventSender()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: ImmediateDelay())
        var reportedSuccess: Bool?

        sut.send(returnSessionData(),
                 status: .cancelled,
                 featureFlagProvider: StubFeatureFlagProvider(),
                 onComplete: { success, _ in reportedSuccess = success })

        #expect(reportedSuccess == nil)

        wrapped.finishRequest(success: true)

        #expect(reportedSuccess == true)
    }

    @Test("When the delayed send fails then the failure reaches the caller")
    func whenDelayedSendFailsThenFailureReachesCaller() {
        let wrapped = SpyWideEventSender()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: ImmediateDelay())
        var reportedSuccess: Bool?
        var reportedError: Error?

        sut.send(returnSessionData(),
                 status: .cancelled,
                 featureFlagProvider: StubFeatureFlagProvider(),
                 onComplete: { success, error in
                     reportedSuccess = success
                     reportedError = error
                 })
        wrapped.finishRequest(success: false, error: WideEventError.invalidFlowState)

        #expect(reportedSuccess == false)
        #expect(reportedError is WideEventError)
    }

    @Test("When the transport still holds the completion then the app is kept awake")
    func whenTransportStillHoldsCompletionThenAppIsKeptAwake() {
        let wrapped = SpyWideEventSender()
        let delay = ImmediateDelay()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: delay)

        sut.send(returnSessionData(),
                 status: .cancelled,
                 featureFlagProvider: StubFeatureFlagProvider(),
                 onComplete: { _, _ in })
        wrapped.finishRequest(success: true)

        // Reporting back is not letting go: the app stays awake until the transport drops it.
        #expect(delay.assertion.releaseCount == 0)

        wrapped.letGoOfCompletion()

        #expect(delay.assertion.releaseCount == 1)
    }

    @Test("When an event is wrapped then the status and flag provider reach the wrapped sender")
    func whenEventIsWrappedThenStatusAndFlagProviderReachWrappedSender() {
        let wrapped = SpyWideEventSender()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: ImmediateDelay())
        let featureFlagProvider = StubFeatureFlagProvider()

        sut.send(returnSessionData(),
                 status: .success(reason: "search_submitted"),
                 featureFlagProvider: featureFlagProvider,
                 onComplete: { _, _ in })

        #expect(wrapped.sentStatuses == [.success(reason: "search_submitted")])
        #expect(wrapped.sentFeatureFlagProviders.count == 1)
        #expect(wrapped.sentFeatureFlagProviders.first is StubFeatureFlagProvider)
    }
}
