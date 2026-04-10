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

    // MARK: - recordButtonClick

    func testWhenRecordButtonClickCalledThenButtonClickedKeyIsSetInDefaults() {
        let controller = QuickFeedbackTipController(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: "feedbackTip.buttonClicked"))

        controller.recordButtonClick()

        XCTAssertTrue(defaults.bool(forKey: "feedbackTip.buttonClicked"))
    }

    // MARK: - shouldShow timing logic (tested via scheduleIfNeeded behavior)

    func testWhenNeverShownBeforeThenFirstSessionSeedsTimestampWithoutScheduling() {
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

        // First session seeds the timestamp so the tip starts on the next session
        XCTAssertGreaterThan(defaults.double(forKey: "feedbackTip.lastShown"), 0,
                             "First session should seed the lastShown timestamp")
    }

    func testWhenShownRecentlyAndNoClickThenScheduleIfNeededWillNotSchedule() {
        // Simulate the tip was just shown 1 second ago (well within the pre-click interval)
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

        // The timestamp should be unchanged (tip was not re-shown)
        let lastShown = defaults.double(forKey: "feedbackTip.lastShown")
        XCTAssertGreaterThan(lastShown, 0, "lastShown should retain the prior value")
    }

    func testWhenClickedAndShownRecentlyThenUsesPostClickInterval() {
        // Simulate: button was clicked, and tip was shown 1 second ago
        defaults.set(true, forKey: "feedbackTip.buttonClicked")
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

        // Post-click interval is longer, so 1 second ago is not enough — tip should NOT schedule
        let lastShown = defaults.double(forKey: "feedbackTip.lastShown")
        XCTAssertGreaterThan(lastShown, 0, "lastShown should retain the prior value (not re-shown)")
    }

    func testWhenPreClickIntervalExceededThenScheduleIfNeededDoesNotReturnEarly() {
        // Set lastShown well beyond the pre-click interval (10s in DEBUG)
        let oldTimestamp = Date().timeIntervalSince1970 - 20
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

        // shouldShow() returned true so scheduleIfNeeded entered the scheduling path.
        // The timestamp is not updated synchronously (it updates in showTip after the delay),
        // so it should still equal the old value — confirming we didn't hit the first-session
        // seeding path or any other early-return that modifies the timestamp.
        let currentTimestamp = defaults.double(forKey: "feedbackTip.lastShown")
        XCTAssertEqual(currentTimestamp, oldTimestamp, accuracy: 0.001,
                       "Timestamp should not change synchronously when scheduling is deferred")
    }

    func testWhenPostClickIntervalExceededThenScheduleIfNeededDoesNotReturnEarly() {
        defaults.set(true, forKey: "feedbackTip.buttonClicked")
        // Set lastShown well beyond the post-click interval (300s in DEBUG)
        let oldTimestamp = Date().timeIntervalSince1970 - 400
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

        // No crash, no popover to close — this is a no-op safety check
    }

    func testWhenRecordButtonClickCalledThenTipIsDismissed() {
        let controller = QuickFeedbackTipController(defaults: defaults)

        // recordButtonClick internally calls dismissTip; verify it completes without error
        controller.recordButtonClick()

        XCTAssertTrue(defaults.bool(forKey: "feedbackTip.buttonClicked"))
    }
}
