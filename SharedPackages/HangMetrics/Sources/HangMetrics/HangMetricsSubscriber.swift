//
//  HangMetricsSubscriber.swift
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
import Common
import Persistence
import PixelKit

/// Subscribes to MetricKit metric payloads and turns `MXAppResponsivenessMetric`
/// hang-time histograms into pixels. Shared by iOS and macOS; each platform owns only
/// the service that registers it with `MXMetricManager` and drives `processPastPayloads`.
public final class HangMetricsSubscriber: NSObject, MXMetricManagerSubscriber {

    private let processor: HangMetricsProcessor
    private let store: KeyValueStoring
    private let currentAppVersion: String
    private let dateProvider: () -> Date
    private let fire: (HangMetricsPixel) -> Void

    /// Serialises all report processing. Both entry points — MetricKit's system-delivered
    /// payloads (`didReceive`) and our own drain of retained payloads (`processPastPayloads`) —
    /// run here, off the main thread and never concurrently, so the `lastProcessedEnd`
    /// read-modify-write can't race.
    private let processingQueue = DispatchQueue(label: "com.duckduckgo.hangMetrics")

    public convenience init(store: KeyValueStoring) {
        self.init(processor: HangMetricsProcessor(), store: store)
    }

    init(processor: HangMetricsProcessor = HangMetricsProcessor(),
         store: KeyValueStoring,
         currentAppVersion: String = AppVersion.shared.versionNumber,
         dateProvider: @escaping () -> Date = Date.init,
         fire: ((HangMetricsPixel) -> Void)? = nil) {
        self.processor = processor
        self.store = store
        self.currentAppVersion = currentAppVersion
        self.dateProvider = dateProvider
        self.fire = fire ?? { PixelKit.fire($0) }
        super.init()
    }

    // MARK: - MXMetricManagerSubscriber

    public func didReceive(_ payloads: [MXMetricPayload]) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.process(reports: payloads.compactMap(Self.report(from:)))
        }
    }

    /// Drains MetricKit's retained past payloads. Called on launch and on every foreground.
    /// Reads `pastPayloads` and processes it on the serial queue, so nothing runs on the main
    /// thread; the dedup marker makes repeated calls safe.
    public func processPastPayloads() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.process(reports: MXMetricManager.shared.pastPayloads.compactMap(Self.report(from:)))
        }
    }

    // MARK: - Report handling

    func process(reports: [HangMetricsReport]) {
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
        static let lastProcessedKey = "HangMetrics.lastProcessedEnd"
    }

    // MARK: - MetricKit adapter

    static func report(from payload: MXMetricPayload) -> HangMetricsReport? {
        guard let responsiveness = payload.applicationResponsivenessMetrics else { return nil }
        return HangMetricsReport(appVersion: payload.latestApplicationVersion,
                                 includesMultipleAppVersions: payload.includesMultipleApplicationVersions,
                                 timeStampEnd: payload.timeStampEnd,
                                 buckets: buckets(from: responsiveness.histogrammedApplicationHangTime))
    }

    static func buckets(from histogram: MXHistogram<UnitDuration>) -> [HangHistogramBucket] {
        var result: [HangHistogramBucket] = []
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitDuration> {
            result.append(HangHistogramBucket(startMs: bucket.bucketStart.converted(to: .milliseconds).value,
                                              endMs: bucket.bucketEnd.converted(to: .milliseconds).value,
                                              count: bucket.bucketCount))
        }
        return result
    }
}

/// Parameter keys for the hang pixels. Declared here rather than in each app's parameter
/// catalogue so the two platforms cannot drift apart on the wire.
public enum HangMetricsPixelParameters {
    public static let minMs = "min_hang_duration_ms"
    public static let maxMs = "max_hang_duration_ms"
    public static let count = "hang_count"
}

public enum HangMetricsPixel: PixelKit.Event {

    case hangBucket(minMs: Int, maxMs: Int, count: Int)

    public var name: String {
        switch self {
        case .hangBucket: return "app-hangs_metrickit_hang-bucket"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case let .hangBucket(minMs, maxMs, count):
            return [
                HangMetricsPixelParameters.minMs: String(minMs),
                HangMetricsPixelParameters.maxMs: String(maxMs),
                HangMetricsPixelParameters.count: String(count)
            ]
        }
    }

    public var standardParameters: [PixelKitStandardParameter]? { nil }
}

private extension HangDataPoint {
    var pixelKitEvent: HangMetricsPixel {
        .hangBucket(minMs: minMs, maxMs: maxMs, count: count)
    }
}
