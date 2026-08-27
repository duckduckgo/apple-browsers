//
//  BookmarkToolbarPromoDelegateTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarkToolbarPromoDelegateTests: XCTestCase {

    private var windowControllersManager: WindowControllersManagerMock!
    private var sut: BookmarkToolbarPromoDelegate!

    override func setUp() {
        super.setUp()
        windowControllersManager = WindowControllersManagerMock()
        sut = makeSUT()
    }

    override func tearDown() {
        sut = nil
        windowControllersManager = nil
        UserDefaultsWrapper<Bool?>(key: .bookmarksBarPromptShown).clear()
        super.tearDown()
    }

    private func makeSUT() -> BookmarkToolbarPromoDelegate {
        BookmarkToolbarPromoDelegate(windowControllersManager: windowControllersManager)
    }

    // MARK: - Eligibility

    /// There's no externally-owned condition to reflect here (unlike e.g. Sync Favicons); every
    /// gate that determines whether anything is actually shown lives inside `show()` instead, so
    /// history/eligibility permanence isn't duplicated outside PromoService's own record.
    func testIsEligibleIsAlwaysTrue() {
        XCTAssertTrue(sut.isEligible)
    }

    func testIsEligiblePublisherReplaysCurrentValue() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        cancellable.cancel()
        XCTAssertEqual(received, [true])
    }

    // MARK: - show()

    /// No window to anchor the popover to: the promo must end its session rather than leave the
    /// queue waiting on an unresolved continuation.
    func testWhenThereIsNoKeyWindowThenShowReturnsNoChange() async {
        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkToolbarPromoID), force: false)

        XCTAssertEqual(result, .noChange)
    }

    /// Migration: a user who already saw (and dismissed, either way) the pre-Promo-Queue popover
    /// must not see it again. `.retired` permanently disables the promo without consuming the
    /// global cooldown, since nothing is actually shown.
    func testWhenLegacyPopoverWasAlreadyShownThenShowRetiresThePromo() async {
        UserDefaultsWrapper(key: .bookmarksBarPromptShown, defaultValue: false).wrappedValue = true

        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkToolbarPromoID), force: false)

        XCTAssertEqual(result, .retired)
    }

    /// Force Show (debug menu) must still let engineers preview the migrated promo even for a
    /// user who already saw the legacy popover. With no window present here, bypassing the
    /// retirement check falls through to the ordinary no-window path rather than `.retired`.
    func testWhenLegacyPopoverWasAlreadyShownThenForceShowBypassesRetirement() async {
        UserDefaultsWrapper(key: .bookmarksBarPromptShown, defaultValue: false).wrappedValue = true

        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkToolbarPromoID), force: true)

        XCTAssertEqual(result, .noChange)
    }

    // MARK: - hide()

    /// `PromoService` calls `hide()` unconditionally after recording any result, including for
    /// sessions that never showed; it must be a no-op rather than crash.
    func testHideBeforeShowingDoesNothing() {
        sut.hide()
        sut.hide()
    }

    // MARK: - Resolution paths (the one-shot/permanent-history semantics)

    /// Matches the legacy popover: it is shown at most once ever, so *both* outcomes retire it
    /// permanently -- unlike a typical recurring promo, dismissing must not use a cooldown here.
    func testResolutionResult_whenAccepted_returnsActioned() {
        XCTAssertEqual(BookmarkToolbarPromoDelegate.resolutionResult(accepted: true), .actioned)
    }

    func testResolutionResult_whenDismissed_returnsBareIgnored() {
        XCTAssertEqual(BookmarkToolbarPromoDelegate.resolutionResult(accepted: false), .ignored())
    }

    // MARK: - Trigger wiring

    func testWhenBookmarkPromptShouldShowNotificationPosted_thenPromoTriggerFires() {
        let expectation = expectation(description: "trigger fired")
        let cancellable = PromoTrigger.triggerPublisher
            .filter { $0 == .bookmarkPromptShouldShow }
            .sink { _ in expectation.fulfill() }

        NotificationCenter.default.post(name: .bookmarkPromptShouldShow, object: nil)

        waitForExpectations(timeout: 1)
        cancellable.cancel()
    }
}
