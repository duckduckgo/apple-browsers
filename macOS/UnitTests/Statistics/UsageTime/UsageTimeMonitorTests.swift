//
//  UsageTimeMonitorTests.swift
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

import Combine
import XCTest
@_spi(Testing) import PixelKit
@testable import DuckDuckGo_Privacy_Browser

final class UsageTimeMonitorTests: XCTestCase {
    private var directory: URL!
    private let first = Date(timeIntervalSince1970: 1_795_600_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testEligibleDayWaitsForFiveMinuteCheckOrNextLaunch() throws {
        var reading = UsageTimeReading(date: first, uptime: 0)
        let clock = { reading }
        do {
            let monitor = UsageTimeMonitor(directory: directory, now: clock, pixelFiring: nil)
            monitor.handle(.start)
            monitor.handle(.input)
            reading = UsageTimeReading(date: first.addingTimeInterval(600), uptime: 600)
            monitor.handle(.stop)
            reading = UsageTimeReading(date: first.addingTimeInterval(86_399), uptime: 600)
            monitor.handle(.start)
            reading = UsageTimeReading(date: first.addingTimeInterval(86_459), uptime: 660)
            monitor.handle(.checkpoint)
            monitor.preview()
            monitor.stopForQuit()
        }
        let key = UsageTimeTracker.calendar.startOfDay(for: first)
        do {
            let store = UsageDayStore(directory: directory) { XCTFail("Unexpected discard") }
            try store.restore()
            XCTAssertEqual(store.days[key]?.open, 600)
            XCTAssertEqual(store.days[key]?.active, 300)
            XCTAssertNil(store.days[key]?.delivery)
        }
        do {
            let monitor = UsageTimeMonitor(directory: directory, now: clock, pixelFiring: nil)
            monitor.handle(.start)
            monitor.stopForQuit()
        }
        let persisted = UsageDayStore(directory: directory) { XCTFail("Unexpected discard") }
        try persisted.restore()
        XCTAssertEqual(persisted.days[key]?.delivery?.finalizedAt, reading.date)
        XCTAssertEqual(persisted.days[key]?.delivery?.payload.daysAgo, 1)
    }

#if DEBUG
    @MainActor
    func testPeriodicPreviewCanBeDisabledAndStopsOnQuit() throws {
        do {
            let reading = UsageTimeReading(date: first, uptime: 0)
            var readings = 0
            let monitor = UsageTimeMonitor(directory: directory, now: {
                readings += 1
                return reading
            }, pixelFiring: nil)
            let ticks = PassthroughSubject<Date, Never>()
            monitor.handle(.start)
            XCTAssertFalse(monitor.isPreviewingEvery30Seconds)
            monitor.togglePreviewEvery30Seconds(ticks: ticks.eraseToAnyPublisher())
            XCTAssertTrue(monitor.isPreviewingEvery30Seconds)
            let initialReadings = readings
            ticks.send(first)
            ticks.send(first.addingTimeInterval(30))
            XCTAssertEqual(readings, initialReadings + 2)
            monitor.togglePreviewEvery30Seconds()
            XCTAssertFalse(monitor.isPreviewingEvery30Seconds)
            ticks.send(first.addingTimeInterval(60))
            XCTAssertEqual(readings, initialReadings + 2)
            monitor.togglePreviewEvery30Seconds(ticks: ticks.eraseToAnyPublisher())
            monitor.stopForQuit()
            XCTAssertFalse(monitor.isPreviewingEvery30Seconds)
            let readingsAtQuit = readings
            ticks.send(first.addingTimeInterval(90))
            XCTAssertEqual(readings, readingsAtQuit)
        }

        let store = UsageDayStore(directory: directory) { XCTFail("Unexpected discard") }
        try store.restore()
        let record = try XCTUnwrap(store.days[UsageTimeTracker.calendar.startOfDay(for: first)])
        XCTAssertNil(record.delivery)
    }
#endif

    @MainActor
    func testFifthCheckpointAfterWakeFinalizesEligibleDay() throws {
        var reading = UsageTimeReading(date: first, uptime: 0)
        do {
            let monitor = UsageTimeMonitor(directory: directory, now: { reading }, pixelFiring: nil)
            monitor.handle(.start)
            monitor.handle(.stop)
            let wake = first.addingTimeInterval(86_399)
            reading = UsageTimeReading(date: wake, uptime: 1)
            monitor.handle(.start)
            for minute in 1...5 {
                let elapsed = Double(minute * 60)
                // The fifth scheduled callback can sample uptime just shy of 300 elapsed seconds.
                reading = UsageTimeReading(date: wake.addingTimeInterval(elapsed), uptime: elapsed + 0.99)
                monitor.handle(.checkpoint)
            }
            monitor.stopForQuit()
        }
        let store = UsageDayStore(directory: directory) { XCTFail("Unexpected discard") }
        try store.restore()
        XCTAssertEqual(store.days[UsageTimeTracker.calendar.startOfDay(for: first)]?.delivery?.finalizedAt, reading.date)
    }

    @MainActor
    func testDiscardRequestsOneStandardPixelAndQuitDoesNotFire() throws {
        do {
            let store = UsageDayStore(directory: directory) { XCTFail("Unexpected discard") }
            try store.restore()
            try store.checkpoint(at: first)
        }
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data([0xff]).write(to: file)
        let pixels = PixelKitMock()
        let reading = UsageTimeReading(date: first, uptime: 0)
        let monitor = UsageTimeMonitor(directory: directory, now: { reading }, pixelFiring: pixels)
        monitor.handle(.start)
        monitor.handle(.checkpoint)
        monitor.stopForQuit()
        XCTAssertEqual(pixels.actualFireCalls.count, 1)
        XCTAssertEqual(pixels.actualFireCalls.first?.pixel.name, "usage-time_store-discarded_macos")
        XCTAssertEqual(pixels.actualFireCalls.first?.frequency, .standard)
    }
}
