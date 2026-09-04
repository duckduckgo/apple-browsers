//
//  UpdateNotificationPromoBridgeTests.swift
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

import AppUpdaterShared
import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class UpdateNotificationPromoBridgeTests: XCTestCase {

    private var notificationCenter: NotificationCenter!
    private var sut: UpdateNotificationPromoBridge!

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        sut = UpdateNotificationPromoBridge(notificationCenter: notificationCenter)
    }

    override func tearDown() {
        sut = nil
        notificationCenter = nil
        super.tearDown()
    }

    func testWhenShowUpdateNotificationForUpdateTypeThenPostsUpdateAvailableTrigger() {
        var posted = false
        let cancellable = notificationCenter.publisher(for: .updateAvailable).sink { _ in posted = true }

        sut.showUpdateNotification(for: .regular, areAutomaticUpdatesEnabled: false)

        cancellable.cancel()
        XCTAssertTrue(posted)
    }

    func testWhenShowUpdateNotificationForNoChangeThenDoesNotPostOrStoreStatus() {
        var posted = false
        let cancellable = notificationCenter.publisher(for: .browserUpdated).sink { _ in posted = true }

        sut.showUpdateNotification(for: .noChange)

        cancellable.cancel()
        XCTAssertFalse(posted)
        XCTAssertEqual(sut.pendingApplicationUpdateStatus, .noChange)
    }

    func testWhenShowUpdateNotificationForUpdatedThenPostsBrowserUpdatedTriggerAndStoresStatus() {
        var posted = false
        let cancellable = notificationCenter.publisher(for: .browserUpdated).sink { _ in posted = true }

        sut.showUpdateNotification(for: .updated)

        cancellable.cancel()
        XCTAssertTrue(posted)
        XCTAssertEqual(sut.pendingApplicationUpdateStatus, .updated)
    }

    /// Once the browser-updated promo resolves, the status must not linger — `isEligible` should
    /// reflect current truth (nothing left pending to show), even though in practice nothing else
    /// will re-evaluate it this launch since `.browserUpdated` itself only posts once per launch.
    func testWhenAcknowledgedThenStatusResetsToNoChange() {
        sut.showUpdateNotification(for: .updated)

        sut.acknowledgeApplicationUpdateStatus()

        XCTAssertEqual(sut.pendingApplicationUpdateStatus, .noChange)
    }

    func testWhenSuggestionWindowDidShowThenDismissesBothDelegates() {
        let updateAvailable = DismissRecordingDelegate()
        let browserUpdated = DismissRecordingDelegate()
        sut.updateAvailableDelegate = updateAvailable
        sut.browserUpdatedDelegate = browserUpdated

        notificationCenter.post(name: .suggestionWindowDidShow, object: nil)

        // The `.suggestionWindowDidShow` observer is itself dispatched onto the main queue
        // (`queue: .main`), and its handler (`dismissIfPresented()`) hops to the main queue a
        // second time internally, so two turns of the main queue must elapse before the
        // delegates' `dismissIfPresented()` calls have actually happened.
        let expectation = expectation(description: "wait for dismissal to propagate")
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        XCTAssertTrue(updateAvailable.didDismiss)
        XCTAssertTrue(browserUpdated.didDismiss)
    }
}

private final class DismissRecordingDelegate: UpdateNotificationPromoDismissing {
    private(set) var didDismiss = false

    @MainActor
    func dismissIfPresented() {
        didDismiss = true
    }
}
