//
//  EventHubConversionReporting.swift
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

/// The seam through which EventHub hands experiment-metric conversion requests to the Native Apps
/// experiment framework, mirroring `EventHubPixelFiring` for telemetry.
///
/// Everything past this call belongs to the framework: it resolves enrollment and cohort, decides
/// window containment, accumulates occurrences against the threshold, suppresses repeats and fires the
/// pixel. The hub's metrics handler is deliberately stateless — no counting, no window arithmetic, no
/// enrollment check, nothing persisted — so a request for an experiment the user is not enrolled in is
/// a no-op rather than something the hub has to filter.
public protocol EventHubConversionReporting {
    func reportConversion(experiment: String, metric: String, windowDays: ClosedRange<Int>, threshold: Int)
}
