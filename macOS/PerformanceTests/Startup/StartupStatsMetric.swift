//
//  StartupStatsMetric.swift
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
import XCTest

/// Allows us to provide the `startupStatsURL` at a `deferred` time.
///
/// - Important:
///     This is required as `XCTestCase.measure` will create a copy of the `XCTMetric`, and the "root / parent" object cannot be accessed directly.
///
final class StartupMetricsURLProvider {
    var statsURL: URL?

    init(statsURL: URL? = nil) {
        self.statsURL = statsURL
    }
}

/// `XCMetric` that processes the `StartupMetrics` JSON file, as exported by `StartupMetricsExporter`.
///
final class StartupStatsMetric: NSObject, XCTMetric {

    private let metricsURLProvider: StartupMetricsURLProvider
    private var stats: StartupStats?
    private var attachment: XCTAttachment?

    private var statsURL: URL {
        metricsURLProvider.statsURL!
    }

    init(metricsURLProvider: StartupMetricsURLProvider) {
        self.metricsURLProvider = metricsURLProvider
        super.init()
    }

    // MARK: - NSCopying

    func copy(with zone: NSZone? = nil) -> Any {
        StartupStatsMetric(metricsURLProvider: metricsURLProvider)
    }

    // MARK: - XCTMetric

    func willBeginMeasuring() {

    }

    func didStopMeasuring() {
        guard let (stats, attachment) = try? loadAndDecodeStats(sourceURL: statsURL, description: "Startup Stats") else {
            return
        }

        self.stats = stats
        self.attachment = attachment
    }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp, to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        guard let stats, let attachment else {
            XCTFail()
            return []
        }

        // Add attachments to test results
        runAllocationAttachmentsActivity(attachment: attachment)

        // Map Measurements into XCTPerformanceMeasurement
        let measurements: [XCTPerformanceMeasurement] = StartupStats.Step.allCases.compactMap { step in
            guard let duration = stats.duration(step: step) else {
                return nil
            }

            return XCTPerformanceMeasurement(
                identifier: "com.duckduckgo.startup.metrics." + step.rawValue,
                displayName: step.rawValue,
                doubleValue: Double(duration),
                unitSymbol: "Milliseconds"
            )
        }

        return measurements
    }
}

private extension StartupStatsMetric {

    func loadAndDecodeStats(sourceURL: URL, description: String) throws -> (StartupStats, XCTAttachment) {
        let statsAsData = try Data(contentsOf: sourceURL)
        let snapshot = try decodeStats(statsAsData: statsAsData)
        let attachment = buildAttachment(statsAsData: statsAsData, description: description)

        return (snapshot, attachment)
    }

    func decodeStats(statsAsData: Data) throws -> StartupStats {
        try JSONDecoder().decode(StartupStats.self, from: statsAsData)
    }

    func buildAttachment(statsAsData: Data, description: String) -> XCTAttachment {
        let attachment = XCTAttachment(data: statsAsData, uniformTypeIdentifier: "public.json")
        attachment.name = description
        attachment.lifetime = .keepAlways
        return attachment
    }

    func runAllocationAttachmentsActivity(attachment: XCTAttachment) {
        XCTContext.runActivity(named: "Attaching Startup Metrics") { activity in
            activity.add(attachment)
        }
    }
}
