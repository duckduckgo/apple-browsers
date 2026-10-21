//
//  SpyConversionReporting.swift
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
@testable import EventHub

/// Test double for `EventHubConversionReporting`: records every conversion request the hub hands to the
/// Native Apps experiment framework. `EventHubFixture` exposes the recording as `.requested`.
///
/// It replicates exactly one line of the real framework — the enrollment gate that opens
/// `PixelKit.fireExperimentPixelIfThresholdReached`:
///
///     guard let experimentData = featureFlagger.allActiveExperiments[subfeatureID] else { return }
///
/// That gate belongs to the framework, not the hub: per the Tech Design the metrics handler is
/// stateless, with no enrollment check of its own. Observing requests just *after* it is what makes
/// M-SEL-6 and M-SEL-7 ("an unenrolled experiment requests nothing") assertable without dragging
/// PixelKit's window arithmetic, enrollment dates and event store into a specification test.
///
/// `allActiveExperiments` already excludes an experiment whose config `state` is `disabled`, keeping
/// only `.enabled` and `.disabled(.targetDoesNotMatch)`, so removing an ID from `enrolled` models both
/// un-enrolling and disabling in config (M-LIF-5).
final class SpyConversionReporting: EventHubConversionReporting {
    /// The experiments the user is currently enrolled in and which are currently enabled. Settable
    /// mid-test, so a case can enroll between phases (M-LIF-1, M-LIF-3).
    var enrolled: Set<String> = []

    /// One recorded request. A local type rather than `MetricRequest`, whose `event` field the
    /// reporting seam deliberately does not carry: by the time a request is made the event has already
    /// done its job of selecting it.
    struct Recorded: Equatable {
        let experiment: String
        let metric: String
        let windowDays: ClosedRange<Int>
        let threshold: Int
    }

    private(set) var requests: [Recorded] = []

    func reportConversion(experiment: String, metric: String, windowDays: ClosedRange<Int>, threshold: Int) {
        guard enrolled.contains(experiment) else { return }
        requests.append(Recorded(experiment: experiment, metric: metric,
                                 windowDays: windowDays, threshold: threshold))
    }

    /// Every request accepted, written as `experiment/metric/window/threshold` and sorted, so a case can
    /// state its complete expected set and an over-request fails as loudly as a missing one.
    ///
    /// The window is rendered the way the specification's derived-request table writes it — and the way
    /// PixelKit's own `conversionWindowDays` pixel parameter does — `"N"` for a single-day window and
    /// `"low-high"` otherwise.
    var requested: [String] {
        requests
            .map { request in
                let window = request.windowDays.lowerBound == request.windowDays.upperBound
                    ? "\(request.windowDays.lowerBound)"
                    : "\(request.windowDays.lowerBound)-\(request.windowDays.upperBound)"
                return "\(request.experiment)/\(request.metric)/\(window)/\(request.threshold)"
            }
            .sorted()
    }
}
