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

@Suite("Pixel Transmission Delay")
struct PixelTransmissionDelayTests {

    private final class FakeBackgroundAssertion: BackgroundAssertion {
        var systemDidReleaseAssertion: (() -> Void)?
        var releaseCount = 0

        func release() {
            releaseCount += 1
        }
    }

    private final class Scheduler {
        var interval: TimeInterval?
        var work: (() -> Void)?

        func elapse() {
            work?()
        }
    }

    private final class SendSpy {
        var count = 0
        private var requestDidFinish: (() -> Void)?

        /// Stands in for a send: records the call and holds its completion until the test finishes it.
        func send(_ requestDidFinish: @escaping () -> Void) {
            count += 1
            self.requestDidFinish = requestDidFinish
        }

        func finishRequest() {
            requestDidFinish?()
        }
    }

    private func makeSUT(interval: TimeInterval = 5,
                         assertion: BackgroundAssertion? = nil) -> (PixelTransmissionDelay, Scheduler) {
        let scheduler = Scheduler()
        let sut = PixelTransmissionDelay(
            interval: { interval },
            makeAssertion: { assertion },
            runOnMain: { $0() },
            schedule: { interval, work in
                scheduler.interval = interval
                scheduler.work = work
            })
        return (sut, scheduler)
    }

    // MARK: - Deferral

    @Test("When a send is delayed then it does not run before the interval elapses")
    func whenSendIsDelayedThenItDoesNotRunImmediately() {
        let (sut, scheduler) = makeSUT(interval: 12)
        let spy = SendSpy()

        sut.delaySend(spy.send)

        #expect(spy.count == 0)
        #expect(scheduler.interval == 12)
    }

    @Test("When the interval elapses then the send runs")
    func whenIntervalElapsesThenSendRuns() {
        let (sut, scheduler) = makeSUT()
        let spy = SendSpy()

        sut.delaySend(spy.send)
        scheduler.elapse()

        #expect(spy.count == 1)
    }

    // MARK: - Randomised interval

    @Test("When the interval is randomised then it stays within the range agreed with Privacy Triage")
    func whenIntervalIsRandomisedThenItStaysWithinRange() {
        for _ in 0..<500 {
            #expect(PixelTransmissionDelay.range.contains(PixelTransmissionDelay.randomInterval()))
        }
    }

    @Test("When the range is read then it matches the 1-30s mitigation")
    func whenRangeIsReadThenItMatchesTheMitigation() {
        #expect(PixelTransmissionDelay.range == 1...30)
    }

    // MARK: - Background assertion

    @Test("When the system reclaims the background assertion then the send runs without waiting")
    func whenAssertionExpiresThenSendRunsWithoutWaiting() {
        let assertion = FakeBackgroundAssertion()
        let (sut, _) = makeSUT(assertion: assertion)
        let spy = SendSpy()

        sut.delaySend(spy.send)
        assertion.systemDidReleaseAssertion?()

        #expect(spy.count == 1)
    }

    @Test("When the interval elapses after the assertion expired then the send runs only once")
    func whenIntervalElapsesAfterExpiryThenSendRunsOnce() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(assertion: assertion)
        let spy = SendSpy()

        sut.delaySend(spy.send)
        assertion.systemDidReleaseAssertion?()
        scheduler.elapse()

        #expect(spy.count == 1)
    }

    @Test("When the request is still in flight then the background assertion is still held")
    func whenRequestIsInFlightThenAssertionIsStillHeld() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(assertion: assertion)
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
        let (sut, scheduler) = makeSUT(assertion: assertion)
        let spy = SendSpy()

        sut.delaySend(spy.send)
        scheduler.elapse()
        spy.finishRequest()

        #expect(assertion.releaseCount == 1)
    }

    @Test("When the request reports completion twice then the assertion is released twice, harmlessly")
    func whenRequestReportsCompletionTwiceThenReleaseIsIdempotent() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(assertion: assertion)
        let spy = SendSpy()

        // `.dailyAndCount` calls back once per fired variant, and `release()` is documented safe to
        // call redundantly, so the delay does not need to count completions itself.
        sut.delaySend(spy.send)
        scheduler.elapse()
        spy.finishRequest()
        spy.finishRequest()

        #expect(assertion.releaseCount == 2)
    }

    @Test("When the interval elapses twice then the send runs only once")
    func whenIntervalElapsesTwiceThenSendRunsOnce() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(assertion: assertion)
        let spy = SendSpy()

        sut.delaySend(spy.send)
        scheduler.elapse()
        scheduler.elapse()

        #expect(spy.count == 1)
    }

    @Test("When the release lands off the main thread then it is hopped back onto it")
    func whenReleaseLandsOffMainThenItIsHoppedOntoMain() {
        let assertion = FakeBackgroundAssertion()
        let scheduler = Scheduler()
        var hops = 0
        let sut = PixelTransmissionDelay(
            interval: { 5 },
            makeAssertion: { assertion },
            runOnMain: { work in
                hops += 1
                work()
            },
            schedule: { interval, work in
                scheduler.interval = interval
                scheduler.work = work
            })
        let spy = SendSpy()

        sut.delaySend(spy.send)
        scheduler.elapse()
        #expect(hops == 1)

        // PixelKit's iOS fire request calls back off the main thread, and releasing asserts on it.
        spy.finishRequest()

        #expect(hops == 2)
        #expect(assertion.releaseCount == 1)
    }
}

@Suite("Return Session Send Delaying Wide Event Sender")
struct ReturnSessionSendDelayingWideEventSenderTests {

    private final class SpyWideEventSender: WideEventSending {
        var sentPixelNames: [String] = []
        var sentStatuses: [WideEventStatus] = []
        private var onComplete: PixelKit.CompletionBlock?

        func send<T: WideEventData>(_ data: T,
                                    status: WideEventStatus,
                                    featureFlagProvider: WideEventFeatureFlagProviding,
                                    onComplete: @escaping PixelKit.CompletionBlock) {
            sentPixelNames.append(T.metadata.pixelName)
            sentStatuses.append(status)
            self.onComplete = onComplete
        }

        func finishRequest(success: Bool) {
            onComplete?(success, nil)
        }
    }

    private final class ImmediateDelay: PixelTransmissionDelaying {
        var delayedSends = 0
        private(set) var requestDidFinish = false

        func delaySend(_ send: @escaping (@escaping () -> Void) -> Void) {
            delayedSends += 1
            send { self.requestDidFinish = true }
        }
    }

    private struct StubFeatureFlagProvider: WideEventFeatureFlagProviding {
        func isEnabled(_ flag: WideEventFeatureFlag) -> Bool { true }
    }

    @Test("When the return session event is sent then it goes through the delay")
    func whenReturnSessionEventIsSentThenItIsDelayed() {
        let wrapped = SpyWideEventSender()
        let delay = ImmediateDelay()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: delay)

        sut.send(ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true),
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

    @Test("When the delayed send completes then the caller and the delay are both told")
    func whenDelayedSendCompletesThenCallerAndDelayAreBothTold() {
        let wrapped = SpyWideEventSender()
        let delay = ImmediateDelay()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: delay)
        var reportedSuccess: Bool?

        sut.send(ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true),
                 status: .cancelled,
                 featureFlagProvider: StubFeatureFlagProvider(),
                 onComplete: { success, _ in reportedSuccess = success })

        #expect(reportedSuccess == nil)
        #expect(delay.requestDidFinish == false)

        wrapped.finishRequest(success: true)

        #expect(reportedSuccess == true)
        #expect(delay.requestDidFinish)
    }

    @Test("When an event is wrapped then the status reaches the wrapped sender unchanged")
    func whenEventIsWrappedThenStatusReachesWrappedSenderUnchanged() {
        let wrapped = SpyWideEventSender()
        let sut = ReturnSessionSendDelayingWideEventSender(wrapping: wrapped, delay: ImmediateDelay())

        sut.send(ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true),
                 status: .success(reason: "search_submitted"),
                 featureFlagProvider: StubFeatureFlagProvider(),
                 onComplete: { _, _ in })

        #expect(wrapped.sentStatuses == [.success(reason: "search_submitted")])
    }
}
