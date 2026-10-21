//
//  DismissableSyncDeviceButtonModelTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DismissableSyncDeviceButtonModelTests: XCTestCase {

    private var promo: MockSyncDeviceButtonPromo!
    private var syncLauncher: MockSyncDeviceFlowLauncher!
    private var pixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()
        promo = MockSyncDeviceButtonPromo()
        syncLauncher = MockSyncDeviceFlowLauncher()
        pixelFiring = PixelKitMock()
    }

    override func tearDown() {
        pixelFiring = nil
        syncLauncher = nil
        promo = nil
        super.tearDown()
    }

    // MARK: - Visibility

    func testWhenCreatedWithInactivePromoThenSyncButtonIsHidden() {
        let model = makeModel()

        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testWhenPromoActiveChangesThenSyncButtonFollowsIt() {
        // Given
        let model = makeModel()

        // When
        promo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertTrue(model.shouldShowSyncButton)

        // When
        promo.isPromoActiveSubject.send(false)

        // Then
        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testWhenPromoIsAlreadyActiveThenSyncButtonIsShownOnCreation() {
        // Given
        promo.isPromoActiveSubject.send(true)

        // When
        let model = makeModel()

        // Then
        XCTAssertTrue(model.shouldShowSyncButton)
    }

    // MARK: - Displayed pixel

    func testWhenPromoBecomesActiveWithoutPanelThenDisplayedPixelWaitsForButtonToAppear() {
        // Given
        let model = makeModel(source: .bookmarksBar)

        // When
        promo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertTrue(model.shouldShowSyncButton)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenSyncButtonAppearsRepeatedlyThenDisplayedPixelFiresOnce() {
        // Given
        let model = makeModel(source: .bookmarksBar)

        // When
        model.syncButtonDidAppear()
        model.syncButtonDidAppear()

        // Then
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarksBar"])
    }

    func testWhenPanelAppearsWhilePromoIsActiveThenDisplayedPixelFires() {
        // Given
        promo.isPromoActiveSubject.send(true)
        let model = makeModel()

        // When
        model.bookmarkPanelDidAppear()

        // Then
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarkAdded"])
    }

    func testWhenPanelAppearsWhilePromoIsInactiveThenDisplayedPixelWaitsUntilPromoBecomesActive() {
        // Given
        let model = makeModel()

        // When
        model.bookmarkPanelDidAppear()

        // Then
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)

        // When
        promo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarkAdded"])
    }

    func testWhenButtonIsShownAgainInTheSamePanelThenDisplayedPixelFiresOnce() {
        // Given
        let model = makeModel()
        model.bookmarkPanelDidAppear()

        // When
        promo.isPromoActiveSubject.send(true)
        promo.isPromoActiveSubject.send(false)
        promo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
    }

    func testWhenPanelDidAppearIsReportedTwiceThenDisplayedPixelFiresOnce() {
        // Given
        promo.isPromoActiveSubject.send(true)
        let model = makeModel()

        // When
        model.bookmarkPanelDidAppear()
        model.bookmarkPanelDidAppear()

        // Then
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
    }

    // MARK: - Forwarding to the promo

    func testWhenViewDisappearsThenPromoIsTold() {
        // Given
        let model = makeModel()

        // When
        model.viewDidDisappear()

        // Then
        XCTAssertEqual(promo.syncButtonSurfaceClosedCount, 1)
        XCTAssertEqual(promo.syncButtonDismissedCount, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenSyncButtonIsDismissedThenButtonHidesAndPromoIsToldAndDismissedPixelFires() {
        // Given
        promo.isPromoActiveSubject.send(true)
        let model = makeModel()

        // When
        model.dismissSyncButtonAction()

        // Then
        XCTAssertFalse(model.shouldShowSyncButton)
        XCTAssertEqual(promo.syncButtonDismissedCount, 1)
        XCTAssertEqual(promo.syncButtonSurfaceClosedCount, 0)
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDismissed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarkAdded"])
    }

    func testWhenSyncButtonIsTappedThenSetupStartsAndConfirmedPixelFires() {
        // Given
        let model = makeModel()

        // When
        model.syncButtonAction()

        // Then
        XCTAssertEqual(promo.syncSetupStartedCount, 1)
        XCTAssertEqual(syncLauncher.startDeviceSyncFlowSources, [.bookmarkAdded])
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoConfirmed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarkAdded"])
    }

    func testWhenBookmarksBarSyncButtonIsTappedThenSetupStartsFromBookmarksBar() {
        // Given
        let model = makeModel(source: .bookmarksBar)

        // When
        model.syncButtonAction()

        // Then
        XCTAssertEqual(promo.syncSetupStartedCount, 1)
        XCTAssertEqual(syncLauncher.startDeviceSyncFlowSources, [.bookmarksBar])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarksBar"])
    }

    // MARK: - Debug reset

    func testWhenStateIsResetThenAllLegacyKeysAreCleared() {
        // Given
        let keyValueStore = InMemoryKeyValueStore()
        keyValueStore.set(true, forKey: UserDefaultsKeys.bookmarksBarSyncPromoDismissed.rawValue)
        keyValueStore.set(Date(), forKey: UserDefaultsKeys.bookmarksBarSyncPromoFirstPresentedDate.rawValue)
        keyValueStore.set(true, forKey: UserDefaultsKeys.bookmarkAddedSyncPromoDismissed.rawValue)
        keyValueStore.set(3, forKey: UserDefaultsKeys.bookmarkAddedSyncPromoPresentedCount.rawValue)

        // When
        DismissableSyncDeviceButtonModel.resetAllState(from: keyValueStore)

        // Then
        XCTAssertNil(keyValueStore.object(forKey: "com.duckduckgo.bookmarksBarSyncPromoDismissed"))
        XCTAssertNil(keyValueStore.object(forKey: "com.duckduckgo.bookmarkFirstPresentedCount"))
        XCTAssertNil(keyValueStore.object(forKey: "com.duckduckgo.bookmarkAddedSyncPromoDismissed"))
        XCTAssertNil(keyValueStore.object(forKey: "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount"))
    }

    // MARK: - Helpers

    private func makeModel(source: DismissableSyncDeviceButtonModel.DismissableSyncDevicePromoSource = .bookmarkAdded) -> DismissableSyncDeviceButtonModel {
        DismissableSyncDeviceButtonModel(
            source: source,
            syncLauncher: syncLauncher,
            pixelFiring: pixelFiring,
            notificationCenter: NotificationCenter(),
            promo: promo
        )
    }
}

// MARK: - Mock Classes

final class MockSyncDeviceFlowLauncher: SyncDeviceFlowLaunching {
    var startDeviceSyncFlowCalled = false
    private(set) var startDeviceSyncFlowSources: [SyncDeviceButtonTouchpoint] = []

    func startDeviceSyncFlow(source: SyncDeviceButtonTouchpoint, completion: (() -> Void)?) {
        startDeviceSyncFlowCalled = true
        startDeviceSyncFlowSources.append(source)
        completion?()
    }
}
