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

        sut.delaySend { spy.count += 1 }

        #expect(spy.count == 0)
        #expect(scheduler.interval == 12)
    }

    @Test("When the interval elapses then the send runs")
    func whenIntervalElapsesThenSendRuns() {
        let (sut, scheduler) = makeSUT()
        let spy = SendSpy()

        sut.delaySend { spy.count += 1 }
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

        sut.delaySend { spy.count += 1 }
        assertion.systemDidReleaseAssertion?()

        #expect(spy.count == 1)
    }

    @Test("When the interval elapses after the assertion expired then the send runs only once")
    func whenIntervalElapsesAfterExpiryThenSendRunsOnce() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(assertion: assertion)
        let spy = SendSpy()

        sut.delaySend { spy.count += 1 }
        assertion.systemDidReleaseAssertion?()
        scheduler.elapse()

        #expect(spy.count == 1)
    }

    @Test("When the send runs then the background assertion is released")
    func whenSendRunsThenAssertionIsReleased() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(assertion: assertion)

        sut.delaySend { }
        #expect(assertion.releaseCount == 0)

        scheduler.elapse()
        #expect(assertion.releaseCount == 1)
    }

    @Test("When the interval elapses twice then the assertion is released only once")
    func whenIntervalElapsesTwiceThenAssertionIsReleasedOnce() {
        let assertion = FakeBackgroundAssertion()
        let (sut, scheduler) = makeSUT(assertion: assertion)

        sut.delaySend { }
        scheduler.elapse()
        scheduler.elapse()

        #expect(assertion.releaseCount == 1)
    }
}

@Suite("Return Session Send Delaying Wide Event Sender")
struct ReturnSessionSendDelayingWideEventSenderTests {

    private final class SpyWideEventSender: WideEventSending {
        var sentPixelNames: [String] = []

        func send<T: WideEventData>(_ data: T,
                                    status: WideEventStatus,
                                    featureFlagProvider: WideEventFeatureFlagProviding,
                                    onComplete: @escaping PixelKit.CompletionBlock) {
            sentPixelNames.append(T.metadata.pixelName)
        }
    }

    private final class ImmediateDelay: PixelTransmissionDelaying {
        var delayedSends = 0

        func delaySend(_ send: @escaping () -> Void) {
            delayedSends += 1
            send()
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
}
