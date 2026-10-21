//
//  CPMInterruptionObserverTests.swift
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
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMInterruptionObserverTests: XCTestCase {

    func testNotificationsBecomeInterruptionEventsBeforePostReturns() {
        let center = NotificationCenter()
        let began = Notification.Name("test.interruption.began")
        let ended = Notification.Name("test.interruption.ended")
        let monitor = RecordingHealthMonitor()
        let observer = CPMInterruptionObserver(monitor: monitor, center: center, began: began, ended: ended)

        center.post(name: began, object: nil)
        XCTAssertEqual(monitor.events, ["began"], "The handler must finish inside the post, before the system sleeps")
        center.post(name: ended, object: nil)
        XCTAssertEqual(monitor.events, ["began", "ended"])

        withExtendedLifetime(observer) {}
    }

    func testNotificationPostedOffMainThreadIsHandledOnMain() {
        let center = NotificationCenter()
        let began = Notification.Name("test.interruption.began.background")
        let monitor = RecordingHealthMonitor()
        let delivered = expectation(description: "Event reaches the monitor on the main thread")
        monitor.onEvent = {
            XCTAssertTrue(Thread.isMainThread)
            delivered.fulfill()
        }
        let observer = CPMInterruptionObserver(monitor: monitor, center: center, began: began, ended: Notification.Name("unused"))

        DispatchQueue.global().async { center.post(name: began, object: nil) }
        wait(for: [delivered], timeout: 1)

        XCTAssertEqual(monitor.events, ["began"])
        withExtendedLifetime(observer) {}
    }

    func testProductionNotificationsAreInterruptions() {
        let monitor = RecordingHealthMonitor()
        let observer = CPMInterruptionObserver(monitor: monitor)

        #if os(iOS)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #else
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #endif

        XCTAssertEqual(monitor.events, ["began", "ended"])
        withExtendedLifetime(observer) {}
    }

    func testBecomingInactiveIsNotAnInterruption() {
        let monitor = RecordingHealthMonitor()
        let observer = CPMInterruptionObserver(monitor: monitor)

        #if os(iOS)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #else
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        // The display going to sleep does not stop the process; only the system sleeping does.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #endif
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(monitor.events.isEmpty)
        withExtendedLifetime(observer) {}
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class RecordingHealthMonitor: CPMMessagingHealthMonitoring, @unchecked Sendable {
    var events: [String] = []
    var onEvent: (() -> Void)?

    @MainActor
    func handle(_ event: CPMMessagingHealthEvent) {
        switch event {
        case .interruptionBegan: events.append("began")
        case .interruptionEnded: events.append("ended")
        default: events.append("other")
        }
        onEvent?()
    }
}
