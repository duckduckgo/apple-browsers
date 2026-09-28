//
//  BrowserUpdatedPromoDelegateTests.swift
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
import FeatureFlags_macOS
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrowserUpdatedPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var bridge: UpdateNotificationPromoBridge!
    private var windowControllersManager: WindowControllersManagerMock!
    private var sut: BrowserUpdatedPromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.promoQueueBrowserUpdatedPromo.rawValue: true])
        bridge = UpdateNotificationPromoBridge(notificationCenter: NotificationCenter())
        windowControllersManager = WindowControllersManagerMock()
        sut = BrowserUpdatedPromoDelegate(bridge: bridge,
                                          windowControllersManager: windowControllersManager,
                                          featureFlagger: featureFlagger)
    }

    override func tearDown() {
        sut = nil
        windowControllersManager = nil
        bridge = nil
        featureFlagger = nil
        super.tearDown()
    }

    func testWhenNoStatusPendingThenNotEligible() {
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenUpdatedStatusPendingThenEligible() {
        bridge.showUpdateNotification(for: .updated)

        XCTAssertTrue(sut.isEligible)
    }

    func testWhenFeatureFlagOffThenNotEligibleEvenWithPendingStatus() {
        bridge.showUpdateNotification(for: .updated)
        featureFlagger.featuresStub = [FeatureFlag.promoQueueBrowserUpdatedPromo.rawValue: false]

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenThereIsNoKeyWindowThenShowReturnsNoChange() async {
        bridge.showUpdateNotification(for: .updated)

        let result = await sut.show(history: PromoHistoryRecord(id: "browser-updated"), force: false)

        XCTAssertEqual(result, .noChange)
    }

    func testWhenHiddenWithoutShowingThenAcknowledgesStatus() {
        bridge.showUpdateNotification(for: .updated)

        sut.hide()

        XCTAssertEqual(bridge.pendingApplicationUpdateStatus, .noChange)
    }
}
