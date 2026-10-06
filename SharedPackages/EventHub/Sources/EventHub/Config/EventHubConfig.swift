//
//  EventHubConfig.swift
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

/// When a pixel fires. Raw values are the strings remote config authors and the persisted config
/// snapshot carries, so they must not change.
///
/// The one exception, deliberate: the immediate trigger was renamed from `immediate` to
/// `immediate_v2` when web events began de-duplicating at the hub. Clients already in the wild parse
/// `immediate` and would fire on every occurrence, so config carrying the new semantics needs a name
/// they ignore. Safe for the persisted snapshot too: only `period` pixels ever have state to persist.
public enum TelemetryTriggerType: String, Equatable, Sendable {
    /// Aggregated over a period, and the default when config omits the type.
    case period
    /// One pixel per delivered event.
    case immediateV2 = "immediate_v2"
}

/// What a parameter measures. Raw values are the strings remote config authors and the persisted config
/// snapshot carries, so they must not change.
public enum TelemetryParameterTemplate: String, Equatable, Sendable {
    /// Bucketed event count, using `buckets` and `source`.
    case counter
    /// A value forwarded from `webEvent.data` under `dataKey`.
    case data
}

/// Describes when a pixel fires. Period triggers carry a `periodSeconds`; immediate triggers carry a
/// `source` event name.
public struct TelemetryTriggerConfig: Equatable, Sendable {
    public let type: TelemetryTriggerType
    /// Length of the aggregation period. Always seconds — config generation collapses any authored unit
    /// to seconds before it reaches the client (see the ported README).
    public let periodSeconds: Int64?
    public let source: String?

    public init(type: TelemetryTriggerType, periodSeconds: Int64? = nil, source: String? = nil) {
        self.type = type
        self.periodSeconds = periodSeconds
        self.source = source
    }
}

/// A single pixel parameter.
public struct TelemetryParameterConfig: Equatable, Sendable {
    public let template: TelemetryParameterTemplate
    public let source: String?
    public let dataKey: String?
    public let buckets: BucketList?

    public init(template: TelemetryParameterTemplate, source: String? = nil, dataKey: String? = nil, buckets: BucketList? = nil) {
        self.template = template
        self.source = source
        self.dataKey = dataKey
        self.buckets = buckets
    }
}

/// Parsed configuration for a single EventHub telemetry pixel, as supplied by the remote `eventHub`
/// feature settings.
public struct TelemetryPixelConfig: Equatable, Sendable {
    public let name: String
    public let state: String
    public let trigger: TelemetryTriggerConfig
    public let parameters: [String: TelemetryParameterConfig]

    public init(name: String, state: String, trigger: TelemetryTriggerConfig, parameters: [String: TelemetryParameterConfig]) {
        self.name = name
        self.state = state
        self.trigger = trigger
        self.parameters = parameters
    }

    public var isEnabled: Bool { state == "enabled" }
}

/// One experiment-metric conversion request — the whole of what the metrics handler hands to the
/// Native Apps experiment framework, and the unit the cross-platform specification asserts against.
///
/// Flattened at parse time. Config groups a metric's conversions as `windows × thresholds`, but that
/// product is an authoring convenience with no meaning once an event arrives (M-FAN-P1), so the parser
/// multiplies it out once and the event-time job is left as a filter over a flat list.
public struct MetricRequest: Equatable, Sendable {
    /// The experiment (subfeature) ID whose `settings.metrics` declared this metric. Declaration is
    /// attachment: a request always belongs to the declaring experiment and is never fanned out by
    /// metric name alone, so two experiments declaring the same name stay independent (M-SEL-P1/P2).
    public let experiment: String
    /// The event type that triggers this metric.
    public let event: String
    public let metric: String
    /// Inclusive day bounds after enrollment. Whether the user is inside the window is the experiment
    /// framework's decision, not the hub's — the hub only reports.
    public let windowDays: ClosedRange<Int>
    /// Occurrence count at which the framework converts.
    public let threshold: Int

    public init(experiment: String, event: String, metric: String, windowDays: ClosedRange<Int>, threshold: Int) {
        self.experiment = experiment
        self.event = event
        self.metric = metric
        self.windowDays = windowDays
        self.threshold = threshold
    }
}

/// Runtime state for a single parameter within a pixel's active period.
public struct ParamState: Codable, Equatable, Sendable {
    public var value: Int
    public var stopCounting: Bool
    public var lastDataValue: String?

    public init(value: Int, stopCounting: Bool = false, lastDataValue: String? = nil) {
        self.value = value
        self.stopCounting = stopCounting
        self.lastDataValue = lastDataValue
    }
}

/// Persisted runtime state for a pixel's current period: the period window, the per-parameter values,
/// and a snapshot of the config taken at period start (so mid-period config changes do not affect a
/// running period).
public struct PixelState: Equatable, Sendable {
    public let pixelName: String
    public let periodStartMillis: Int64
    public let periodEndMillis: Int64
    public let config: TelemetryPixelConfig
    public var params: [String: ParamState]

    public init(pixelName: String, periodStartMillis: Int64, periodEndMillis: Int64, config: TelemetryPixelConfig, params: [String: ParamState]) {
        self.pixelName = pixelName
        self.periodStartMillis = periodStartMillis
        self.periodEndMillis = periodEndMillis
        self.config = config
        self.params = params
    }
}
