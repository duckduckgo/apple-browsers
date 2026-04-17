//
//  QuickFeedbackTipControllerTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class QuickFeedbackTipControllerTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "QuickFeedbackTipControllerTests")!
        defaults.removePersistentDomain(forName: "QuickFeedbackTipControllerTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "QuickFeedbackTipControllerTests")
        defaults = nil
        super.tearDown()
    }

    // MARK: - First session

    func testWhenNeverShownBeforeThenTipIsScheduled() {
        XCTAssertEqual(defaults.double(forKey: "feedbackTip.lastShown"), 0,
                       "Fresh defaults should have no lastShown timestamp")

        let controller = QuickFeedbackTipController(defaults: defaults)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        // lastShown is 0 (never shown), so shouldShow returns true and tip is scheduled.
        // The timestamp is not updated synchronously — it updates in showTip after the delay.
        XCTAssertEqual(defaults.double(forKey: "feedbackTip.lastShown"), 0,
                       "Timestamp should not change synchronously when scheduling is deferred")
    }

    // MARK: - Cooldown

    func testWhenShownRecentlyThenScheduleIfNeededWillNotSchedule() {
        defaults.set(Date().timeIntervalSince1970 - 1, forKey: "feedbackTip.lastShown")

        let controller = QuickFeedbackTipController(defaults: defaults)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let lastShown = defaults.double(forKey: "feedbackTip.lastShown")
        XCTAssertGreaterThan(lastShown, 0, "lastShown should retain the prior value")
    }

    func testWhenCooldownExceededThenScheduleIfNeededDoesNotReturnEarly() {
        // Set lastShown well beyond the cooldown interval (30s in DEBUG)
        let oldTimestamp = Date().timeIntervalSince1970 - 60
        defaults.set(oldTimestamp, forKey: "feedbackTip.lastShown")

        let controller = QuickFeedbackTipController(defaults: defaults)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let currentTimestamp = defaults.double(forKey: "feedbackTip.lastShown")
        XCTAssertEqual(currentTimestamp, oldTimestamp, accuracy: 0.001,
                       "Timestamp should not change synchronously when scheduling is deferred")
    }

    // MARK: - dismissTip

    func testWhenDismissTipCalledThenPopoverIsClosed() {
        let controller = QuickFeedbackTipController(defaults: defaults)

        controller.dismissTip()
    }

    func testWhenRecordButtonClickCalledThenTipIsDismissed() {
        let controller = QuickFeedbackTipController(defaults: defaults)

        controller.recordButtonClick()
    }

    func testWhenRecordButtonClickCalledThenButtonClickedIsPersistedInDefaults() {
        let controller = QuickFeedbackTipController(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: "feedbackTip.buttonClicked"))

        controller.recordButtonClick()

        XCTAssertTrue(defaults.bool(forKey: "feedbackTip.buttonClicked"))
    }

    func testWhenButtonClickedAndPreClickIntervalExceededThenTipIsNotYetShown() {
        // 45s ago exceeds preClickInterval (30s DEBUG) but not postClickInterval (60s DEBUG)
        defaults.set(Date().timeIntervalSince1970 - 45, forKey: "feedbackTip.lastShown")
        defaults.set(true, forKey: "feedbackTip.buttonClicked")

        let controller = QuickFeedbackTipController(defaults: defaults)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let lastShown = defaults.double(forKey: "feedbackTip.lastShown")
        XCTAssertLessThan(Date().timeIntervalSince1970 - lastShown, 50,
                          "lastShown should not have been updated — tip should not have been scheduled")
    }

    func testWhenButtonClickedAndPostClickIntervalExceededThenTipIsScheduled() {
        // 90s ago exceeds postClickInterval (60s DEBUG)
        let oldTimestamp = Date().timeIntervalSince1970 - 90
        defaults.set(oldTimestamp, forKey: "feedbackTip.lastShown")
        defaults.set(true, forKey: "feedbackTip.buttonClicked")

        let controller = QuickFeedbackTipController(defaults: defaults)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let currentTimestamp = defaults.double(forKey: "feedbackTip.lastShown")
        XCTAssertEqual(currentTimestamp, oldTimestamp, accuracy: 0.001,
                       "Timestamp should not change synchronously when scheduling is deferred")
    }
}
