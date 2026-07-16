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

import Persistence
import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class QuickFeedbackTipControllerTests: XCTestCase {

    private var storage: (any KeyedStoring<QuickFeedbackTipSettings>)!

    override func setUp() {
        super.setUp()
        storage = InMemoryKeyValueStore().keyedStoring()
    }

    override func tearDown() {
        storage = nil
        super.tearDown()
    }

    // MARK: - First session

    func testWhenNeverShownBeforeThenTipIsScheduled() {
        XCTAssertNil(storage.lastShown, "Fresh storage should have no lastShown timestamp")

        let controller = QuickFeedbackTipController(storage: storage)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        XCTAssertNil(storage.lastShown,
                     "Timestamp should not change synchronously when scheduling is deferred")
    }

    // MARK: - Cooldown

    func testWhenShownRecentlyThenScheduleIfNeededWillNotSchedule() {
        storage.lastShown = Date().timeIntervalSince1970 - 1

        let controller = QuickFeedbackTipController(storage: storage)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let lastShown = storage.lastShown ?? 0
        XCTAssertGreaterThan(lastShown, 0, "lastShown should retain the prior value")
    }

    func testWhenCooldownExceededThenScheduleIfNeededDoesNotReturnEarly() {
        let oldTimestamp = Date().timeIntervalSince1970 - 60
        storage.lastShown = oldTimestamp

        let controller = QuickFeedbackTipController(storage: storage)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let currentTimestamp = storage.lastShown ?? 0
        XCTAssertEqual(currentTimestamp, oldTimestamp, accuracy: 0.001,
                       "Timestamp should not change synchronously when scheduling is deferred")
    }

    // MARK: - dismissTip

    func testWhenDismissTipCalledThenPopoverIsClosed() {
        let controller = QuickFeedbackTipController(storage: storage)

        controller.dismissTip()
    }

    func testWhenRecordButtonClickCalledThenTipIsDismissed() {
        let controller = QuickFeedbackTipController(storage: storage)

        controller.recordButtonClick()
    }

    func testWhenRecordButtonClickCalledThenButtonClickedIsPersistedInStorage() {
        let controller = QuickFeedbackTipController(storage: storage)
        XCTAssertNil(storage.buttonClicked)

        controller.recordButtonClick()

        XCTAssertEqual(storage.buttonClicked, true)
    }

    func testWhenButtonClickedAndPreClickIntervalExceededThenTipIsNotYetShown() {
        // 45s ago exceeds preClickInterval (30s DEBUG) but not postClickInterval (60s DEBUG)
        storage.lastShown = Date().timeIntervalSince1970 - 45
        storage.buttonClicked = true

        let controller = QuickFeedbackTipController(storage: storage)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let lastShown = storage.lastShown ?? 0
        XCTAssertLessThan(Date().timeIntervalSince1970 - lastShown, 50,
                          "lastShown should not have been updated — tip should not have been scheduled")
    }

    func testWhenButtonClickedAndPostClickIntervalExceededThenTipIsScheduled() {
        // 90s ago exceeds postClickInterval (60s DEBUG)
        let oldTimestamp = Date().timeIntervalSince1970 - 90
        storage.lastShown = oldTimestamp
        storage.buttonClicked = true

        let controller = QuickFeedbackTipController(storage: storage)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled],
                                  backing: .buffered,
                                  defer: true)
            window.contentView?.addSubview(anchor)

            controller.scheduleIfNeeded(anchoredTo: anchor)
        }

        let currentTimestamp = storage.lastShown ?? 0
        XCTAssertEqual(currentTimestamp, oldTimestamp, accuracy: 0.001,
                       "Timestamp should not change synchronously when scheduling is deferred")
    }
}
