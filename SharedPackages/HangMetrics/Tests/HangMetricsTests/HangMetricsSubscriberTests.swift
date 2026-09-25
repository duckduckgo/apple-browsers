//
//  HangMetricsSubscriberTests.swift
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

import XCTest
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
@testable import HangMetrics

final class HangMetricsSubscriberTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let version = "7.100.0"

    private var expectedName: String {
#if os(macOS)
        "app-hangs_metrickit_hang-bucket_macos"
#else
        "app-hangs_metrickit_hang-bucket"
#endif
    }

    private func makeSubscriber(store: KeyValueStoring,
                                pixelFiring: PixelKitMock) -> HangMetricsSubscriber {
        HangMetricsSubscriber(store: store,
                              currentAppVersion: version,
                              dateProvider: { self.now },
                              pixelFiring: pixelFiring)
    }

    private func report(buckets: [HangHistogramBucket], endOffset: TimeInterval = -60) -> HangMetricsReport {
        HangMetricsReport(appVersion: version,
                          includesMultipleAppVersions: false,
                          timeStampEnd: now.addingTimeInterval(endOffset),
                          buckets: buckets)
    }

    func testFiresOnePixelPerBucketWithRoundedParamsAndExactCount() {
        let pixelKit = PixelKitMock()
        let subscriber = makeSubscriber(store: MockKeyValueStore(), pixelFiring: pixelKit)

        subscriber.process(reports: [report(buckets: [HangHistogramBucket(startMs: 123.4, endMs: 456.6, count: 17)])])

        XCTAssertEqual(pixelKit.actualFireCalls.count, 1)
        let call = pixelKit.actualFireCalls.first
        XCTAssertEqual(call?.pixel.name, expectedName)
        XCTAssertEqual(call?.frequency, .standard)
        XCTAssertEqual(call?.pixel.parameters?[HangMetricsPixelParameters.minMs], "123")
        XCTAssertEqual(call?.pixel.parameters?[HangMetricsPixelParameters.maxMs], "457")
        XCTAssertEqual(call?.pixel.parameters?[HangMetricsPixelParameters.count], "17")
    }

    func testPixelNameNeverCarriesTheLegacyMacPrefix() {
        let pixel = HangMetricsPixel.hangBucket(minMs: 0, maxMs: 1, count: 1)
        XCTAssertFalse(pixel.name.hasPrefix("m_mac_"))
        XCTAssertEqual(pixel.name, expectedName)
        XCTAssertEqual(pixel.namePrefix, .none)
    }

    func testFiresOncePerBucketRatherThanOncePerHang() {
        let pixelKit = PixelKitMock()
        let subscriber = makeSubscriber(store: MockKeyValueStore(), pixelFiring: pixelKit)

        subscriber.process(reports: [report(buckets: [
            HangHistogramBucket(startMs: 0, endMs: 100, count: 40),
            HangHistogramBucket(startMs: 100, endMs: 500, count: 9)
        ])])

        XCTAssertEqual(pixelKit.actualFireCalls.count, 2)
        XCTAssertEqual(pixelKit.actualFireCalls.compactMap { $0.pixel.parameters?[HangMetricsPixelParameters.count] },
                       ["40", "9"])
    }

    func testPersistsMarkerAndSuppressesDuplicateDelivery() {
        let store = MockKeyValueStore()
        let pixelKit = PixelKitMock()
        let subscriber = makeSubscriber(store: store, pixelFiring: pixelKit)

        let r = report(buckets: [HangHistogramBucket(startMs: 1, endMs: 2, count: 3)])
        subscriber.process(reports: [r])
        XCTAssertEqual(pixelKit.actualFireCalls.count, 1)

        // A fresh subscriber sharing the same store must not re-fire the same report.
        let pixelKit2 = PixelKitMock()
        let subscriber2 = makeSubscriber(store: store, pixelFiring: pixelKit2)
        subscriber2.process(reports: [r])
        XCTAssertTrue(pixelKit2.actualFireCalls.isEmpty)
    }
}
