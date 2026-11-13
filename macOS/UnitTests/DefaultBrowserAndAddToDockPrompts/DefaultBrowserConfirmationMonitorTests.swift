//
//  DefaultBrowserConfirmationMonitorTests.swift
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

import AppKit
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserConfirmationMonitorTests: XCTestCase {

    private let clickDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let afterClickDelay: TimeInterval = 5
    private let deadlineInterval: TimeInterval = 24 * 60 * 60

    private var store: InMemoryConfirmationStore!
    private var provider: MockDefaultBrowserProvider!
    private var center: NotificationCenter!
    private var timerFactory: MockTimerFactory!
    private var now: Date!
    private var pixelFiring: PixelKitMock!
    private var monitors: [DefaultBrowserConfirmationMonitor] = []

    override func setUp() {
        super.setUp()
        store = InMemoryConfirmationStore()
        provider = MockDefaultBrowserProvider()
        center = NotificationCenter()
        timerFactory = MockTimerFactory()
        now = clickDate
        pixelFiring = PixelKitMock()
        monitors = []
    }

    override func tearDown() {
        monitors = []
        pixelFiring = nil
        now = nil
        timerFactory = nil
        center = nil
        provider = nil
        store = nil
        super.tearDown()
    }

    func testWhenNotDefaultAfterClickThenNextActivationRuns() {
        let sut = makeMonitor()
        sut.start(clickDate: clickDate)

        fireTimer(interval: afterClickDelay)

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        XCTAssertEqual(store.pendingConfirmation?.nextCheck, .nextActivation)

        provider.isDefault = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(firedPixels, [.confirmed(source: .winBack, check: .nextActivation)])
        let call = pixelFiring.actualFireCalls.first
        XCTAssertEqual(call?.pixel.name, "default-browser-win-back_default-confirmed_macos")
        XCTAssertEqual(call?.pixel.namePrefix, PixelKitNamePrefix.none)
        XCTAssertEqual(call?.pixel.parameters, ["check": "next-activation"])
        XCTAssertEqual(call?.frequency, .standard)
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenNotDefaultAtFirstTwoChecksThenDeadlineTimerNotConfirmed() {
        let sut = makeMonitor()
        sut.start(clickDate: clickDate)
        fireTimer(interval: afterClickDelay)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(store.pendingConfirmation?.nextCheck, .deadline)

        fireTimer(interval: deadlineInterval)

        XCTAssertEqual(firedPixels, [.notConfirmed(source: .winBack)])
        let call = pixelFiring.actualFireCalls.first
        XCTAssertEqual(call?.pixel.name, "default-browser-win-back_default-not-confirmed_macos")
        XCTAssertEqual(call?.pixel.namePrefix, PixelKitNamePrefix.none)
        XCTAssertNil(call?.pixel.parameters)
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenResumedPastDeadlineThenOnlyDeadlineCheckRuns() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .afterClick)
        provider.isDefault = true
        now = clickDate.addingTimeInterval(25 * 60 * 60)
        let sut = makeMonitor()

        sut.resume()

        XCTAssertEqual(firedPixels, [.confirmed(source: .winBack, check: .deadline)])
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenActivationPastDeadlineThenOnlyDeadlineCheckRuns() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .nextActivation)
        let sut = makeMonitor()
        sut.resume()
        provider.isDefault = true
        now = clickDate.addingTimeInterval(deadlineInterval)

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(firedPixels, [.confirmed(source: .winBack, check: .deadline)])
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenRelaunchedAfterAfterClickDelayThenAfterClickRunsRightAway() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .afterClick)
        provider.isDefault = true
        now = clickDate.addingTimeInterval(60)
        let sut = makeMonitor()
        sut.resume()
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)

        fireTimer(interval: 0)

        XCTAssertEqual(firedPixels, [.confirmed(source: .winBack, check: .afterClick)])
    }

    func testWhenResumedBeforeDeadlineThenDeadlineTimerScheduledForRemainingTime() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .nextActivation)
        now = clickDate.addingTimeInterval(3 * 60 * 60)
        let sut = makeMonitor()

        sut.resume()

        XCTAssertEqual(timerFactory.createdTimers.count, 1)
        XCTAssertEqual(timerFactory.createdTimers.first?.timeInterval, deadlineInterval - 3 * 60 * 60)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testExactlyOneResultPerClick() {
        let sut = makeMonitor()
        sut.start(clickDate: clickDate)
        provider.isDefault = true
        fireTimer(interval: afterClickDelay)
        XCTAssertEqual(firedPixels, [.confirmed(source: .winBack, check: .afterClick)])

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        timerFactory.createdTimers.forEach { $0.fire() }
        sut.resume()

        XCTAssertEqual(firedPixels, [.confirmed(source: .winBack, check: .afterClick)])
    }

    // MARK: - Helpers

    private var firedPixels: [DefaultBrowserConfirmationPixel] {
        pixelFiring.actualFireCalls.compactMap { $0.pixel as? DefaultBrowserConfirmationPixel }
    }

    private func makeMonitor() -> DefaultBrowserConfirmationMonitor {
        let monitor = DefaultBrowserConfirmationMonitor(source: .winBack,
                                                        store: store,
                                                        defaultBrowserProvider: provider,
                                                        notificationCenter: center,
                                                        timerFactory: timerFactory,
                                                        dateProvider: { [unowned self] in now },
                                                        afterClickDelay: afterClickDelay,
                                                        deadlineInterval: deadlineInterval,
                                                        pixelFiring: pixelFiring)
        monitors.append(monitor)
        return monitor
    }

    private func fireTimer(interval: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        guard let timer = timerFactory.createdTimers.last(where: { $0.timeInterval == interval && !$0.didCallInvalidate }) else {
            return XCTFail("No valid timer with interval \(interval)", file: file, line: line)
        }
        timer.fire()
    }
}

private final class InMemoryConfirmationStore: DefaultBrowserConfirmationStoring {
    var pendingConfirmation: DefaultBrowserPendingConfirmation?
}
