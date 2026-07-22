//
//  LaunchTimeMetricsSubscriber.swift
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
import MetricKit
import Core
import Common
import Persistence
import PixelKit

@available(iOSApplicationExtension, unavailable)
final class LaunchTimeMetricsSubscriber: NSObject, MXMetricManagerSubscriber {

    private let processor: LaunchTimeMetricsProcessor
    private let store: KeyValueStoring
    private let currentAppVersion: String
    private let dateProvider: () -> Date
    private let fire: (LaunchTimeMetricsPixel) -> Void

    /// Serialises all report processing. Both entry points — MetricKit's system-delivered
    /// payloads (`didReceive`) and our own drain of retained payloads (`processPastPayloads`) —
    /// run here, off the main thread and never concurrently, so the `lastProcessedEnd`
    /// read-modify-write can't race.
    private let processingQueue = DispatchQueue(label: "com.duckduckgo.ios.launchTimeMetrics")

    init(processor: LaunchTimeMetricsProcessor = LaunchTimeMetricsProcessor(),
         store: KeyValueStoring,
         currentAppVersion: String = AppVersion.shared.versionNumber,
         dateProvider: @escaping () -> Date = Date.init,
         fire: ((LaunchTimeMetricsPixel) -> Void)? = nil) {
        self.processor = processor
        self.store = store
        self.currentAppVersion = currentAppVersion
        self.dateProvider = dateProvider
        self.fire = fire ?? { PixelKit.fire($0) }
        super.init()
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.process(reports: payloads.compactMap(Self.report(from:)))
        }
    }

    /// Drains MetricKit's retained past payloads. Called on launch and on every foreground.
    /// Reads `pastPayloads` and processes it on the serial queue, so nothing runs on the main
    /// thread; the dedup marker makes repeated calls safe.
    func processPastPayloads() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.process(reports: MXMetricManager.shared.pastPayloads.compactMap(Self.report(from:)))
        }
    }

    // MARK: - Report handling

    func process(reports: [LaunchMetricsReport]) {
        let dataPoints = processor.dataPointsToSendPixelsFor(from: reports,
                                                             currentAppVersion: currentAppVersion,
                                                             now: dateProvider(),
                                                             lastProcessedEnd: lastProcessedEnd)
        for point in dataPoints {
            fire(point.pixelKitEvent)
        }
        if let newest = processor.newestTimestamp(in: reports) {
            lastProcessedEnd = max(newest, lastProcessedEnd ?? .distantPast)
        }
    }

    // MARK: - Persistence

    private var lastProcessedEnd: Date? {
        get { (store.object(forKey: Const.lastProcessedKey) as? Double).map(Date.init(timeIntervalSince1970:)) }
        set { store.set(newValue?.timeIntervalSince1970, forKey: Const.lastProcessedKey) }
    }

    private enum Const {
        static let lastProcessedKey = "LaunchTimeMetrics.lastProcessedEnd"
    }

    // MARK: - MetricKit adapter

    static func report(from payload: MXMetricPayload) -> LaunchMetricsReport? {
        guard let launch = payload.applicationLaunchMetrics else { return nil }
        var histograms: [LaunchType: [LaunchHistogramBucket]] = [
            .coldStart: buckets(from: launch.histogrammedTimeToFirstDraw),
            .resume: buckets(from: launch.histogrammedApplicationResumeTime)
        ]
        if #available(iOS 15.2, *) {
            histograms[.optimizedFirstDraw] = buckets(from: launch.histogrammedOptimizedTimeToFirstDraw)
        }
        return LaunchMetricsReport(appVersion: payload.latestApplicationVersion,
                                   includesMultipleAppVersions: payload.includesMultipleApplicationVersions,
                                   timeStampEnd: payload.timeStampEnd,
                                   histograms: histograms)
    }

    static func buckets(from histogram: MXHistogram<UnitDuration>) -> [LaunchHistogramBucket] {
        var result: [LaunchHistogramBucket] = []
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitDuration> {
            result.append(LaunchHistogramBucket(startMs: bucket.bucketStart.converted(to: .milliseconds).value,
                                                endMs: bucket.bucketEnd.converted(to: .milliseconds).value,
                                                count: bucket.bucketCount))
        }
        return result
    }
}

enum LaunchTimeMetricsPixel: PixelKitEvent, PixelKitEventWithCustomPrefix {
    case firstDraw(minMs: Int, maxMs: Int)
    case resume(minMs: Int, maxMs: Int)
    case optimizedFirstDraw(minMs: Int, maxMs: Int)

    var name: String {
        switch self {
        case .firstDraw: return "app-launch_metrickit_first-draw"
        case .resume: return "app-launch_metrickit_resume"
        case .optimizedFirstDraw: return "app-launch_metrickit_optimized-first-draw"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case let .firstDraw(minMs, maxMs),
             let .resume(minMs, maxMs),
             let .optimizedFirstDraw(minMs, maxMs):
            return [
                PixelParameters.launchTimeMinMs: String(minMs),
                PixelParameters.launchTimeMaxMs: String(maxMs)
            ]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: String { "" }
}

private extension LaunchTimeDataPoint {
    var pixelKitEvent: LaunchTimeMetricsPixel {
        let lowerMs = Int(minMs.rounded())
        let upperMs = Int(maxMs.rounded())
        switch launchType {
        case .coldStart: return .firstDraw(minMs: lowerMs, maxMs: upperMs)
        case .resume: return .resume(minMs: lowerMs, maxMs: upperMs)
        case .optimizedFirstDraw: return .optimizedFirstDraw(minMs: lowerMs, maxMs: upperMs)
        }
    }
}
