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
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarkToolbarPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var windowControllersManager: WindowControllersManagerMock!
    private var storage: KeyedStorage<BookmarkToolbarPromoSettings>!
    private var sut: BookmarkToolbarPromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueBookmarkToolbarPromo]
        windowControllersManager = WindowControllersManagerMock()
        storage = KeyedStorage(storage: InMemoryKeyValueStore())
        sut = makeSUT()
    }

    override func tearDown() {
        sut = nil
        windowControllersManager = nil
        storage = nil
        featureFlagger = nil
        super.tearDown()
    }

    private func makeSUT() -> BookmarkToolbarPromoDelegate {
        BookmarkToolbarPromoDelegate(featureFlagger: featureFlagger, windowControllersManager: windowControllersManager, storage: storage)
    }

    // MARK: - Eligibility

    func testIsEligibleWhenFeatureFlagIsOn() {
        XCTAssertTrue(sut.isEligible)
    }

    func testIsEligibleWhenFeatureFlagIsOff() {
        featureFlagger.enabledFeatureFlags = []

        XCTAssertFalse(sut.isEligible)
    }

    func testIsEligiblePublisherReplaysCurrentValue() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        cancellable.cancel()
        XCTAssertEqual(received, [true])
    }

    // MARK: - show()

    func testWhenThereIsNoKeyWindowThenShowReturnsNoChange() async {
        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkToolbarPromoID), force: false)

        XCTAssertEqual(result, .noChange)
    }

    func testWhenLegacyPopoverWasAlreadyShownThenShowRetiresThePromo() async {
        storage.didShowLegacyPopover = true

        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkToolbarPromoID), force: false)

        XCTAssertEqual(result, .retired)
    }

    func testWhenLegacyPopoverWasAlreadyShownThenForceShowBypassesRetirement() async {
        storage.didShowLegacyPopover = true

        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkToolbarPromoID), force: true)

        XCTAssertEqual(result, .noChange)
    }

    // MARK: - hide()

    func testHideBeforeShowingDoesNothing() {
        sut.hide()
        sut.hide()
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
