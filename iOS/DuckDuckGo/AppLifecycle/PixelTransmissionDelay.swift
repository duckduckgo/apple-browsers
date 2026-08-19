//
//  PixelTransmissionDelay.swift
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
import UIKit
import PixelKit

/// The part of `QRunInBackgroundAssertion` needed here, so tests can run without `UIApplication`.
protocol BackgroundAssertion: AnyObject {
    var systemDidReleaseAssertion: (() -> Void)? { get set }
    func release()
}

extension QRunInBackgroundAssertion: BackgroundAssertion {}

/// Keeps the app awake while a delayed send is in flight. The guarantee lasts exactly as long as
/// the last reference to it, so hold one from every completion the send hands out.
final class PixelSendToken {

    private let assertion: BackgroundAssertion?
    private let runOnMain: (@escaping () -> Void) -> Void

    init(assertion: BackgroundAssertion?, runOnMain: @escaping (@escaping () -> Void) -> Void) {
        self.assertion = assertion
        self.runOnMain = runOnMain
    }

    /// Called on the main thread when the system reclaims the assertion before we are done with it.
    func onSystemRelease(_ handler: @escaping () -> Void) {
        assertion?.systemDidReleaseAssertion = handler
    }

    deinit {
        // Hop because the last reference is usually dropped by a URL session callback, and both
        // releasing and clearing `systemDidReleaseAssertion` assert they are on the main queue.
        let assertion = self.assertion
        runOnMain { assertion?.release() }
    }
}

/// Holds a send back so it does not land in the burst of pixels the app sends when it foregrounds.
protocol PixelTransmissionDelaying {
    /// Safe to call from any thread. The send runs on the main thread and must keep the token it is
    /// handed alive until every request it started has finished.
    func delaySend(_ send: @escaping (_ keepAppAwake: PixelSendToken) -> Void)
}

final class PixelTransmissionDelay: PixelTransmissionDelaying {

    /// Agreed with Privacy Triage. The wait is trimmed when the remaining background budget is
    /// smaller, so the upper bound does not have to fit inside the window iOS grants.
    static let range: ClosedRange<TimeInterval> = 1...30

    static func randomInterval() -> TimeInterval {
        .random(in: range)
    }

    /// Kept back from the background budget for the request itself, since the assertion starts
    /// running down the moment it is taken rather than when the wait is over.
    private static let requestHeadroom: TimeInterval = 10

    private static let assertionName = "Delayed pixel transmission"

    private let interval: () -> TimeInterval
    private let makeAssertion: () -> BackgroundAssertion?
    private let backgroundTimeRemaining: () -> TimeInterval
    private let runOnMain: (@escaping () -> Void) -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(interval: @escaping () -> TimeInterval = PixelTransmissionDelay.randomInterval,
         makeAssertion: @escaping () -> BackgroundAssertion? = {
             QRunInBackgroundAssertion(name: PixelTransmissionDelay.assertionName, application: .shared)
         },
         // `.greatestFiniteMagnitude` while foregrounded, so the wait is only ever trimmed when the
         // app is on its way out.
         backgroundTimeRemaining: @escaping () -> TimeInterval = { UIApplication.shared.backgroundTimeRemaining },
         // Always hops, because being on the main thread does not mean being on the main queue and
         // `QRunInBackgroundAssertion` asserts the latter.
         runOnMain: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.main.async(execute: work)
         },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { interval, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
         }) {
        self.interval = interval
        self.makeAssertion = makeAssertion
        self.backgroundTimeRemaining = backgroundTimeRemaining
        self.runOnMain = runOnMain
        self.schedule = schedule
    }

    func delaySend(_ send: @escaping (PixelSendToken) -> Void) {
        let interval = self.interval()
        let makeAssertion = self.makeAssertion
        let backgroundTimeRemaining = self.backgroundTimeRemaining
        let runOnMain = self.runOnMain
        let schedule = self.schedule

        // The assertion must be taken now, not when the wait elapses, and is main-thread only.
        runOnMain {
            let token = PixelSendToken(assertion: makeAssertion(), runOnMain: runOnMain)
            let wait = Self.wait(for: interval, budget: backgroundTimeRemaining())
            let pending = PendingSend(send: send, token: token)
            schedule(wait) { pending.run() }
        }
    }

    /// Read after the assertion is taken, so the budget is the one the system actually granted.
    private static func wait(for interval: TimeInterval, budget: TimeInterval) -> TimeInterval {
        min(interval, max(range.lowerBound, budget - requestHeadroom))
    }
}

/// Sends once, on whichever comes first: the wait elapsing or the assertion being reclaimed.
/// Both arrive on the main thread, so the one-shot guard needs no locking.
private final class PendingSend {

    private var send: ((PixelSendToken) -> Void)?
    private var token: PixelSendToken?

    init(send: @escaping (PixelSendToken) -> Void, token: PixelSendToken) {
        self.send = send
        self.token = token
        token.onSystemRelease { [weak self] in self?.run() }
    }

    func run() {
        guard let send, let token else { return }
        self.send = nil

        // Hand the token over rather than releasing when the send reports back: `.dailyAndCount`
        // completes once per fired variant, so the first report is not the last request.
        self.token = nil
        send(token)
    }
}

/// Delays the return-session event only. Sits at the send seam, which `completeFlow` reaches
/// after removing the flow from storage, so a delayed send is out of reach of the orphan sweep.
final class ReturnSessionSendDelayingWideEventSender: WideEventSending {

    private let wrapped: WideEventSending
    private let delay: PixelTransmissionDelaying

    init(wrapping wrapped: WideEventSending, delay: PixelTransmissionDelaying = PixelTransmissionDelay()) {
        self.wrapped = wrapped
        self.delay = delay
    }

    func send<T: WideEventData>(_ data: T,
                                status: WideEventStatus,
                                featureFlagProvider: WideEventFeatureFlagProviding,
                                onComplete: @escaping PixelKit.CompletionBlock) {
        let wrapped = self.wrapped

        guard data is ReturnSessionWideEventData else {
            wrapped.send(data, status: status, featureFlagProvider: featureFlagProvider, onComplete: onComplete)
            return
        }

        delay.delaySend { keepAppAwake in
            wrapped.send(data, status: status, featureFlagProvider: featureFlagProvider) { success, error in
                onComplete(success, error)
                withExtendedLifetime(keepAppAwake) { }
            }
        }
    }
}
