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

/// Aggregation period. Authored as seconds (config-generation collapses any authored unit to seconds
/// before it reaches the client — see the ported README).
public struct TelemetryPeriodConfig: Equatable, Sendable {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    public var periodSeconds: Int64 { Int64(seconds) }
}

/// Describes when a pixel fires. `type` is `"period"` (aggregated, the default) or `"immediate"` (one
/// pixel per event). Period triggers carry a `period`; immediate triggers carry a `source` event name.
public struct TelemetryTriggerConfig: Equatable, Sendable {
    public let type: String
    public let period: TelemetryPeriodConfig?
    public let source: String?

    public init(type: String, period: TelemetryPeriodConfig? = nil, source: String? = nil) {
        self.type = type
        self.period = period
        self.source = source
    }

    public var isImmediate: Bool { type == "immediate" }
    public var isPeriod: Bool { type == "period" }
}

/// A single pixel parameter. `template` is `"counter"` (bucketed event count, using `buckets` and
/// `source`) or `"data"` (a value forwarded from `webEvent.data` under `dataKey`).
public struct TelemetryParameterConfig: Equatable, Sendable {
    public let template: String
    public let source: String?
    public let dataKey: String?
    public let buckets: BucketList?

    public init(template: String, source: String? = nil, dataKey: String? = nil, buckets: BucketList? = nil) {
        self.template = template
        self.source = source
        self.dataKey = dataKey
        self.buckets = buckets
    }

    public var isCounter: Bool { template == "counter" }
    public var isData: Bool { template == "data" }
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
