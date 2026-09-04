//
//  UpdateAvailablePromoDelegateTests.swift
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
final class UpdateAvailablePromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var updateController: MockUpdateAvailabilityController!
    private var windowControllersManager: WindowControllersManagerMock!
    private var sut: UpdateAvailablePromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.promoQueueUpdateAvailablePromo.rawValue: true])
        updateController = MockUpdateAvailabilityController()
        windowControllersManager = WindowControllersManagerMock()
        sut = UpdateAvailablePromoDelegate(updateController: updateController,
                                           windowControllersManager: windowControllersManager,
                                           featureFlagger: featureFlagger)
    }

    override func tearDown() {
        sut = nil
        windowControllersManager = nil
        updateController = nil
        featureFlagger = nil
        super.tearDown()
    }

    func testWhenFeatureFlagOffThenNotEligible() {
        featureFlagger.featuresStub = [FeatureFlag.promoQueueUpdateAvailablePromo.rawValue: false]
        updateController.hasPendingUpdate = true

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenNoPendingUpdateThenNotEligible() {
        updateController.hasPendingUpdate = false

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFeatureFlagOnAndPendingUpdateThenEligible() {
        updateController.hasPendingUpdate = true

        XCTAssertTrue(sut.isEligible)
    }

    /// No key window to anchor to: the promo must end its session rather than leave the queue
    /// waiting on an unresolved continuation.
    func testWhenThereIsNoKeyWindowThenShowReturnsNoChange() async {
        updateController.hasPendingUpdate = true
        updateController.latestUpdate = Update(isInstalled: false,
                                               type: .regular,
                                               version: "1.0.0",
                                               build: "100",
                                               date: Date(),
                                               releaseNotes: [],
                                               releaseNotesSubscription: [])

        let result = await sut.show(history: PromoHistoryRecord(id: "update-available"), force: false)

        XCTAssertEqual(result, .noChange)
    }
}

/// Minimal stand-in for `any UpdateController` — add to this if a shared mock doesn't already
/// exist elsewhere in the test target by the time this is implemented.
private final class MockUpdateAvailabilityController: UpdateController {
    @Published var latestUpdate: Update?
    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }
    @Published var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }
    var mustShowUpdateIndicators: Bool { hasPendingUpdate }
    var needsNotificationDot = false
    var notificationDotPublisher: AnyPublisher<Bool, Never> { Just(needsNotificationDot).eraseToAnyPublisher() }
    var clearsNotificationDotOnMenuOpen = false
    var lastUpdateCheckDate: Date?
    @Published var updateProgress: UpdateCycleProgress = .default
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }
    var areAutomaticUpdatesEnabled = false
    var notificationPresenter: UpdateNotificationPresenting = MockUpdateNotificationPresenting()
    func runUpdate() { }
    func checkForUpdateSkippingRollout() { }
    func openUpdatesPage() { }
    func handleAppTermination() { }
}

private final class MockUpdateNotificationPresenting: UpdateNotificationPresenting {
    func showUpdateNotification(for status: AppUpdateStatus) { }
    func showUpdateNotification(for status: Update.UpdateType, areAutomaticUpdatesEnabled: Bool) { }
    func dismissIfPresented() { }
    func openUpdatesPage() { }
}
