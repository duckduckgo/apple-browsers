//
//  BookmarkPanelShownTriggerTests.swift
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
import ConcurrencyExtensions
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarkPanelShownTriggerTests: XCTestCase {

    private var notificationCenter: NotificationCenter!
    private var observer: NSObjectProtocol?
    private var postCount = 0

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        postCount = 0
        observer = notificationCenter.addObserver(forName: .bookmarkPanelShown, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeMainThread {
                self?.postCount += 1
            }
        }
    }

    override func tearDown() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        notificationCenter = nil
        super.tearDown()
    }

    func testWhenBookmarkPanelShownNotificationPostedThenPromoTriggerFires() {
        let triggerExpectation = expectation(description: "trigger fired")
        let cancellable = PromoTrigger.triggerPublisher
            .filter { $0 == .bookmarkPanelShown }
            .sink { _ in triggerExpectation.fulfill() }

        NotificationCenter.default.post(name: .bookmarkPanelShown, object: nil)

        wait(for: [triggerExpectation], timeout: 1)
        cancellable.cancel()
    }

    func testWhenPanelAppearsThenTriggerIsPosted() {
        // Given
        let model = makeModel()

        // When
        model.bookmarkPanelDidAppear()

        // Then
        XCTAssertEqual(postCount, 1)
    }

    func testWhenPanelAppearsWhilePromoIsAlreadyActiveThenTriggerIsStillPosted() {
        // Given
        let promo = MockSyncDeviceButtonPromo()
        promo.isPromoActiveSubject.send(true)
        let model = makeModel(promo: promo)

        // When
        model.bookmarkPanelDidAppear()

        // Then
        XCTAssertEqual(postCount, 1)
    }

    func testWhenModelIsCreatedThenTriggerIsNotPosted() {
        // When
        _ = makeModel()

        // Then
        XCTAssertEqual(postCount, 0)
    }

    private func makeModel(promo: MockSyncDeviceButtonPromo = MockSyncDeviceButtonPromo()) -> DismissableSyncDeviceButtonModel {
        DismissableSyncDeviceButtonModel(
            source: .bookmarkAdded,
            syncLauncher: MockSyncDeviceFlowLauncher(),
            pixelFiring: PixelKitMock(),
            notificationCenter: notificationCenter,
            promo: promo
        )
    }
}
