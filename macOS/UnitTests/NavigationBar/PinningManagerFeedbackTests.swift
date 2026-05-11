//
//  PinningManagerFeedbackTests.swift
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

final class PinningManagerFeedbackTests: XCTestCase {

    private var pinningManager: LocalPinningManager!

    override func setUp() {
        super.setUp()
        UserDefaultsWrapper<Any>.clearAll()
        pinningManager = LocalPinningManager()
    }

    override func tearDown() {
        UserDefaultsWrapper<Any>.clearAll()
        pinningManager = nil
        super.tearDown()
    }

    // MARK: - Pin/Unpin

    func testWhenFeedbackIsPinnedThenIsPinnedReturnsTrue() {
        pinningManager.pin(.feedback)

        XCTAssertTrue(pinningManager.isPinned(.feedback))
    }

    func testWhenFeedbackIsNotPinnedThenIsPinnedReturnsFalse() {
        XCTAssertFalse(pinningManager.isPinned(.feedback))
    }

    func testWhenFeedbackIsToggledThenPinStateFlips() {
        XCTAssertFalse(pinningManager.isPinned(.feedback))

        pinningManager.togglePinning(for: .feedback)
        XCTAssertTrue(pinningManager.isPinned(.feedback))

        pinningManager.togglePinning(for: .feedback)
        XCTAssertFalse(pinningManager.isPinned(.feedback))
    }

    // MARK: - Manual Toggle Tracking

    func testWhenFeedbackIsToggledThenWasManuallyToggledReturnsTrue() {
        pinningManager.togglePinning(for: .feedback)

        XCTAssertTrue(pinningManager.wasManuallyToggled(.feedback))
    }

    func testWhenFeedbackIsOnlyPinnedViaPinThenWasManuallyToggledReturnsFalse() {
        pinningManager.pin(.feedback)

        XCTAssertFalse(pinningManager.wasManuallyToggled(.feedback))
    }

    // MARK: - Shortcut Title

    func testWhenFeedbackIsPinnedThenShortcutTitleIsHide() {
        pinningManager.pin(.feedback)

        XCTAssertEqual(pinningManager.shortcutTitle(for: .feedback), UserText.hideFeedbackShortcut)
    }

    func testWhenFeedbackIsNotPinnedThenShortcutTitleIsShow() {
        XCTAssertEqual(pinningManager.shortcutTitle(for: .feedback), UserText.showFeedbackShortcut)
    }

    // MARK: - Notification

    func testWhenFeedbackIsPinnedThenPinnedViewsChangedNotificationIsFired() {
        let expectation = expectation(forNotification: .PinnedViewsChanged, object: nil) { notification in
            let viewType = notification.userInfo?[LocalPinningManager.pinnedViewChangedNotificationViewTypeKey] as? String
            return viewType == PinnableView.feedback.rawValue
        }

        pinningManager.pin(.feedback)

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenFeedbackIsAlreadyPinnedThenPinDoesNotFireNotification() {
        pinningManager.pin(.feedback)

        let expectation = expectation(forNotification: .PinnedViewsChanged, object: nil)
        expectation.isInverted = true

        pinningManager.pin(.feedback)

        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Auto-Pin Pattern (mirrors VPN behavior)

    func testWhenFeedbackNotPinnedAndNotManuallyToggledThenAutoShouldPin() {
        let shouldAutoPin = !pinningManager.isPinned(.feedback) && !pinningManager.wasManuallyToggled(.feedback)

        XCTAssertTrue(shouldAutoPin)
    }

    func testWhenFeedbackManuallyToggledThenAutoShouldNotPin() {
        pinningManager.togglePinning(for: .feedback)
        pinningManager.togglePinning(for: .feedback)

        let shouldAutoPin = !pinningManager.isPinned(.feedback) && !pinningManager.wasManuallyToggled(.feedback)

        XCTAssertFalse(shouldAutoPin, "Auto-pin should be skipped when user has manually toggled")
    }
}
