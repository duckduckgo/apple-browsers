//
//  EventHubConfigParser.swift
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
import os.log

/// Parses the remote `eventHub` feature settings JSON into validated telemetry pixel configs, and
/// serialises a single config back to JSON for persistence as a period's config snapshot.
public protocol EventHubConfigParsing {
    /// Parses the `telemetry` map from the feature settings, returning only valid, fully-formed pixel
    /// configs. Malformed or invalid input yields an empty list (never throws). Takes the settings in the
    /// `[String: Any]` shape remote config already holds them in (BSK's `settings(for:)`), so no JSON
    /// round trip is needed to reach the parser.
    func parseTelemetry(_ settings: [String: Any]) -> [TelemetryPixelConfig]

    /// Parses a single serialised pixel config (as produced by `serializePixelConfig`), returning `nil`
    /// if it is malformed or invalid.
    func parseSinglePixelConfig(name: String, json: String) -> TelemetryPixelConfig?

    /// Serialises a pixel config to JSON for persistence, or `nil` if serialisation fails.
    func serializePixelConfig(_ config: TelemetryPixelConfig) -> String?
}

public final class EventHubConfigParser: EventHubConfigParsing {
    /// The feature-settings key holding the per-pixel telemetry map. Also read by `EventHubSettings`,
    /// which strips consent-gated entries out of it.
    static let telemetryKey = "telemetry"

    private static let periodType = "period"
    private static let immediateType = "immediate"
    private static let counterTemplate = "counter"
    private static let dataTemplate = "data"

    public init() {}

    public func parseTelemetry(_ settings: [String: Any]) -> [TelemetryPixelConfig] {
        // An absent `telemetry` key is the normal pre-rollout state ("eventHub enabled, nothing configured
        // yet"), not malformed settings, so it must stay distinguishable from the failures below.
        guard let telemetry = settings[Self.telemetryKey] else { return [] }
        // `isValidJSONObject` first: `data(withJSONObject:)` raises an ObjC exception Swift cannot catch
        // for values JSON can't represent, and this is a public entry point taking untyped input.
        guard JSONSerialization.isValidJSONObject(telemetry) else {
            Logger.eventHub.error("config: `\(Self.telemetryKey, privacy: .public)` is not a valid JSON object, no telemetry configured")
            return []
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: telemetry)
            return try JSONDecoder().decode([String: PixelDTO].self, from: data)
                .compactMap { name, pixel in Self.toPixelConfig(name: name, pixel: pixel) }
        } catch {
            Logger.eventHub.error("config: `\(Self.telemetryKey, privacy: .public)` could not be decoded, no telemetry configured: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func parseSinglePixelConfig(name: String, json: String) -> TelemetryPixelConfig? {
        guard let data = json.data(using: .utf8),
              let pixel = try? JSONDecoder().decode(PixelDTO.self, from: data) else {
            return nil
        }
        return Self.toPixelConfig(name: name, pixel: pixel)
    }

    public func serializePixelConfig(_ config: TelemetryPixelConfig) -> String? {
        guard let data = try? JSONEncoder().encode(Self.toDTO(config)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func toPixelConfig(name: String, pixel: PixelDTO) -> TelemetryPixelConfig? {
        guard let state = pixel.state, let triggerDTO = pixel.trigger else {
            Logger.eventHub.error("config: pixel \(name, privacy: .public) skipped, missing state and/or trigger")
            return nil
        }
        guard let trigger = toTrigger(triggerDTO, pixelName: name) else { return nil }
        let parameters = toParameters(pixel.parameters ?? [:], pixelName: name)
        // A period pixel with no parameters has nothing to report; immediate pixels may legitimately
        // carry none (they fire on the event alone).
        if trigger.isPeriod && parameters.isEmpty {
            Logger.eventHub.error("config: period pixel \(name, privacy: .public) skipped, no valid parameters")
            return nil
        }
        return TelemetryPixelConfig(name: name, state: state, trigger: trigger, parameters: parameters)
    }

    private static func toTrigger(_ dto: TriggerDTO, pixelName: String) -> TelemetryTriggerConfig? {
        let type = dto.type ?? periodType
        if type == immediateType {
            guard let source = dto.source, !source.isEmpty else {
                Logger.eventHub.error("config: pixel \(pixelName, privacy: .public) skipped, immediate trigger with no source")
                return nil
            }
            return TelemetryTriggerConfig(type: immediateType, source: source)
        }
        if type == periodType {
            guard let period = dto.period, period.seconds > 0 else {
                Logger.eventHub.error("config: pixel \(pixelName, privacy: .public) skipped, period seconds missing or not positive")
                return nil
            }
            return TelemetryTriggerConfig(type: periodType, period: TelemetryPeriodConfig(seconds: period.seconds))
        }
        Logger.eventHub.error("config: pixel \(pixelName, privacy: .public) skipped, unknown trigger type \(type, privacy: .public)")
        return nil
    }

    private static func toParameters(_ parameters: [String: ParameterDTO], pixelName: String) -> [String: TelemetryParameterConfig] {
        var result: [String: TelemetryParameterConfig] = [:]
        for (name, parameter) in parameters {
            if let mapped = toParameter(parameter, pixelName: pixelName, parameterName: name) {
                result[name] = mapped
            }
        }
        return result
    }

    private static func toParameter(_ parameter: ParameterDTO, pixelName: String, parameterName: String) -> TelemetryParameterConfig? {
        if parameter.template == counterTemplate {
            guard let source = parameter.source, !source.isEmpty,
                  let buckets = parameter.buckets, !buckets.ordered.isEmpty else {
                Logger.eventHub.error("config: counter parameter \(pixelName, privacy: .public)/\(parameterName, privacy: .public) dropped, missing source and/or usable buckets")
                return nil
            }
            return TelemetryParameterConfig(template: counterTemplate, source: source, buckets: buckets.ordered)
        }
        if parameter.template == dataTemplate {
            guard let dataKey = parameter.dataKey, !dataKey.isEmpty else {
                Logger.eventHub.error("config: data parameter \(pixelName, privacy: .public)/\(parameterName, privacy: .public) dropped, missing dataKey")
                return nil
            }
            return TelemetryParameterConfig(template: dataTemplate, source: parameter.source, dataKey: dataKey)
        }
        Logger.eventHub.error("config: parameter \(pixelName, privacy: .public)/\(parameterName, privacy: .public) dropped, unknown template \(parameter.template ?? "<none>", privacy: .public)")
        return nil
    }

    private static func toDTO(_ config: TelemetryPixelConfig) -> PixelDTO {
        PixelDTO(
            state: config.state,
            trigger: TriggerDTO(
                type: config.trigger.type,
                period: config.trigger.period.map { PeriodDTO(seconds: $0.seconds) },
                source: config.trigger.source),
            parameters: config.parameters.mapValues { parameter in
                ParameterDTO(
                    template: parameter.template,
                    source: parameter.source,
                    dataKey: parameter.dataKey,
                    buckets: parameter.buckets.map { BucketsDTO(ordered: $0) })
            })
    }

    // MARK: DTOs

    private struct PixelDTO: Codable {
        let state: String?
        let trigger: TriggerDTO?
        let parameters: [String: ParameterDTO]?
    }

    private struct TriggerDTO: Codable {
        let type: String?
        let period: PeriodDTO?
        let source: String?
    }

    private struct PeriodDTO: Codable {
        let seconds: Int
    }

    private struct ParameterDTO: Codable {
        let template: String?
        let source: String?
        let dataKey: String?
        let buckets: BucketsDTO?
    }

    private struct BucketDTO: Codable {
        let gte: Int?
        let lt: Int?
    }

    /// Decodes/encodes the `buckets` JSON object as an ordered list, because `BucketCounter` is
    /// first-match-wins and Swift's `Dictionary` would not preserve order. Decoding relies on
    /// `KeyedDecodingContainer.allKeys` returning keys in document order, which holds for the persisted
    /// snapshot but NOT for live remote config: that arrives as an unordered `[String: Any]`, so the
    /// initial order is arbitrary. Harmless while bucket ranges are disjoint (exactly one match, and
    /// `shouldStopCounting` scans all of them); overlapping ranges would resolve unpredictably.
    /// A bucket without a lower bound (`gte`) is invalid and disqualifies the whole counter.
    private struct BucketsDTO: Codable {
        let ordered: BucketList

        init(ordered: BucketList) {
            self.ordered = ordered
        }

        private struct DynamicKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            var result: BucketList = []
            for key in container.allKeys {
                let dto = try container.decode(BucketDTO.self, forKey: key)
                guard let gte = dto.gte else {
                    Logger.eventHub.error("config: bucket \(key.stringValue, privacy: .public) has no `gte` lower bound, counter discarded")
                    ordered = []
                    return
                }
                result.append(OrderedBucket(name: key.stringValue, config: BucketConfig(gte: gte, lt: dto.lt)))
            }
            ordered = result
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicKey.self)
            for bucket in ordered {
                let key = DynamicKey(stringValue: bucket.name)!
                try container.encode(BucketDTO(gte: bucket.config.gte, lt: bucket.config.lt), forKey: key)
            }
        }
    }
}
