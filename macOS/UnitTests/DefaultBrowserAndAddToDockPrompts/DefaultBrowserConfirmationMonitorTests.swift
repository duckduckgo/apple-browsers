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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserConfirmationMonitorTests: XCTestCase {

    private let clickDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let returnDelay: TimeInterval = 5
    private let deadlineInterval: TimeInterval = 24 * 60 * 60

    private var store: InMemoryConfirmationStore!
    private var provider: MockDefaultBrowserProvider!
    private var center: NotificationCenter!
    private var timerFactory: MockTimerFactory!
    private var now: Date!
    private var results: [DefaultBrowserConfirmationResult]!
    private var monitors: [DefaultBrowserConfirmationMonitor] = []

    override func setUp() {
        super.setUp()
        store = InMemoryConfirmationStore()
        provider = MockDefaultBrowserProvider()
        center = NotificationCenter()
        timerFactory = MockTimerFactory()
        now = clickDate
        results = []
        monitors = []
    }

    override func tearDown() {
        monitors = []
        results = nil
        now = nil
        timerFactory = nil
        center = nil
        provider = nil
        store = nil
        super.tearDown()
    }

    func testWhenNotDefaultAtReturnedThenNextActivationRuns() {
        let sut = makeMonitor()
        sut.start(clickDate: clickDate)

        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        fireTimer(interval: returnDelay)

        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(store.pendingConfirmation?.nextCheck, .nextActivation)

        provider.isDefault = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(results, [.confirmed(.nextActivation)])
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenNotDefaultAtFirstTwoChecksThenDeadlineTimerNotConfirmed() {
        let sut = makeMonitor()
        sut.start(clickDate: clickDate)
        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        fireTimer(interval: returnDelay)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(store.pendingConfirmation?.nextCheck, .deadline)

        fireTimer(interval: deadlineInterval)

        XCTAssertEqual(results, [.notConfirmed])
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenResumedPastDeadlineThenOnlyDeadlineCheckRuns() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .returned)
        provider.isDefault = true
        now = clickDate.addingTimeInterval(25 * 60 * 60)
        let sut = makeMonitor()

        sut.resume()

        XCTAssertEqual(results, [.confirmed(.deadline)])
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenActivationPastDeadlineThenOnlyDeadlineCheckRuns() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .nextActivation)
        let sut = makeMonitor()
        sut.resume()
        provider.isDefault = true
        now = clickDate.addingTimeInterval(deadlineInterval)

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(results, [.confirmed(.deadline)])
        XCTAssertNil(store.pendingConfirmation)
    }

    func testWhenQuitDuringReturnDelayThenNextKeyWindowRerunsReturned() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .returned)
        provider.isDefault = true
        let sut = makeMonitor()
        sut.resume()
        XCTAssertTrue(results.isEmpty)

        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        fireTimer(interval: returnDelay)

        XCTAssertEqual(results, [.confirmed(.returned)])
    }

    func testWhenResumedBeforeDeadlineThenDeadlineTimerScheduledForRemainingTime() {
        store.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: clickDate, nextCheck: .nextActivation)
        now = clickDate.addingTimeInterval(3 * 60 * 60)
        let sut = makeMonitor()

        sut.resume()

        XCTAssertEqual(timerFactory.createdTimers.count, 1)
        XCTAssertEqual(timerFactory.createdTimers.first?.timeInterval, deadlineInterval - 3 * 60 * 60)
        XCTAssertTrue(results.isEmpty)
    }

    func testExactlyOneResultPerClick() {
        let sut = makeMonitor()
        sut.start(clickDate: clickDate)
        provider.isDefault = true
        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        fireTimer(interval: returnDelay)
        XCTAssertEqual(results, [.confirmed(.returned)])

        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        timerFactory.createdTimers.forEach { $0.fire() }
        sut.resume()

        XCTAssertEqual(results, [.confirmed(.returned)])
    }

    // MARK: - Helpers

    private func makeMonitor() -> DefaultBrowserConfirmationMonitor {
        let monitor = DefaultBrowserConfirmationMonitor(source: .winBack,
                                                        store: store,
                                                        defaultBrowserProvider: provider,
                                                        notificationCenter: center,
                                                        timerFactory: timerFactory,
                                                        dateProvider: { [unowned self] in now },
                                                        returnDelay: returnDelay,
                                                        deadlineInterval: deadlineInterval,
                                                        report: { [unowned self] in results.append($0) })
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
