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

/// Holds a send back so it does not land in the burst of pixels the app sends when it foregrounds.
protocol PixelTransmissionDelaying {
    /// Safe to call from any thread; the send itself runs on the main thread. The send must call the
    /// closure it is handed once its request finished, so the assertion covers the request too.
    func delaySend(_ send: @escaping (_ requestDidFinish: @escaping () -> Void) -> Void)
}

final class PixelTransmissionDelay: PixelTransmissionDelaying {

    /// Agreed with Privacy Triage; the upper bound also matches the background window iOS grants.
    static let range: ClosedRange<TimeInterval> = 1...30

    static func randomInterval() -> TimeInterval {
        .random(in: range)
    }

    private static let assertionName = "Delayed pixel transmission"

    private let interval: () -> TimeInterval
    private let makeAssertion: () -> BackgroundAssertion?
    private let runOnMain: (@escaping () -> Void) -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(interval: @escaping () -> TimeInterval = PixelTransmissionDelay.randomInterval,
         makeAssertion: @escaping () -> BackgroundAssertion? = {
             QRunInBackgroundAssertion(name: PixelTransmissionDelay.assertionName, application: .shared)
         },
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
        self.runOnMain = runOnMain
        self.schedule = schedule
    }

    func delaySend(_ send: @escaping (@escaping () -> Void) -> Void) {
        let interval = self.interval()
        let makeAssertion = self.makeAssertion
        let runOnMain = self.runOnMain
        let schedule = self.schedule

        // The assertion must be taken now, not when the delay elapses, and is main-thread only.
        runOnMain {
            let pending = PendingSend(send: send, assertion: makeAssertion(), runOnMain: runOnMain)
            schedule(interval) { pending.run() }
        }
    }
}

/// Sends once, on whichever comes first: the delay elapsing or the assertion being reclaimed.
/// Both arrive on the main thread, so the one-shot guard needs no locking.
private final class PendingSend {

    private var send: ((@escaping () -> Void) -> Void)?
    private let assertion: BackgroundAssertion?
    private let runOnMain: (@escaping () -> Void) -> Void

    init(send: @escaping (@escaping () -> Void) -> Void,
         assertion: BackgroundAssertion?,
         runOnMain: @escaping (@escaping () -> Void) -> Void) {
        self.send = send
        self.assertion = assertion
        self.runOnMain = runOnMain
        assertion?.systemDidReleaseAssertion = { [weak self] in self?.run() }
    }

    func run() {
        guard let send else { return }
        self.send = nil

        // Handing the assertion to the completion keeps it alive for the request, not just for the
        // call that starts it. Hop to main because PixelKit calls back off it and releasing cannot.
        let assertion = self.assertion
        let runOnMain = self.runOnMain
        send { runOnMain { assertion?.release() } }
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

        delay.delaySend { requestDidFinish in
            wrapped.send(data, status: status, featureFlagProvider: featureFlagProvider) { success, error in
                onComplete(success, error)
                requestDidFinish()
            }
        }
    }
}
