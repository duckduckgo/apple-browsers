//
//  BookmarksBarSyncButtonTests.swift
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

import AppKit
import Combine
import DDGSync
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarksBarSyncButtonTests: XCTestCase {

    private var syncPromo: MockBookmarksBarSyncPromo!
    private var pixelFiring: PixelKitMock!
    private var syncLauncher: MockSyncDeviceFlowLauncher!
    private var viewController: BookmarksBarViewController!

    override func setUp() {
        super.setUp()
        syncPromo = MockBookmarksBarSyncPromo()
        pixelFiring = PixelKitMock()
        syncLauncher = MockSyncDeviceFlowLauncher()
        let bookmarkManager = MockBookmarkManager()
        viewController = BookmarksBarViewController(
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
            bookmarkManager: bookmarkManager,
            dragDropManager: BookmarkDragDropManager(bookmarkManager: bookmarkManager),
            pinningManager: MockPinningManager(),
            featureFlagger: MockFeatureFlagger(),
            appereancePreferences: AppearancePreferencesPersistorMock(),
            syncButtonModel: DismissableSyncDeviceButtonModel(
                source: .bookmarksBar,
                keyValueStore: MockKeyValueStore(),
                authStatePublisher: Empty().eraseToAnyPublisher(),
                initialAuthState: .inactive,
                syncLauncher: syncLauncher,
                featureFlagger: MockFeatureFlagger(),
                pixelFiring: pixelFiring,
                promo: syncPromo
            )
        )
        _ = viewController.view
        viewController.viewWillAppear()
    }

    override func tearDown() {
        viewController = nil
        syncLauncher = nil
        pixelFiring = nil
        syncPromo = nil
        super.tearDown()
    }

    func testWhenPromoIsInactiveThenSyncButtonIsHiddenAndNoPixelFires() {
        XCTAssertTrue(viewController.syncButton.isHidden)
        XCTAssertEqual(viewController.syncButtonZeroWidthConstraint.priority, .required)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenPromoBecomesActiveThenSyncButtonIsShownAndDisplayedPixelFires() {
        // When
        syncPromo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertFalse(viewController.syncButton.isHidden)
        XCTAssertEqual(viewController.syncButtonZeroWidthConstraint.priority, .defaultLow)
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarksBar"])
    }

    func testWhenPromoBecomesInactiveThenSyncButtonIsHidden() {
        // Given
        syncPromo.isPromoActiveSubject.send(true)

        // When
        syncPromo.isPromoActiveSubject.send(false)

        // Then
        XCTAssertTrue(viewController.syncButton.isHidden)
        XCTAssertEqual(viewController.syncButtonZeroWidthConstraint.priority, .required)
    }

    func testWhenBarIsReattachedWhilePromoIsActiveThenDisplayedPixelDoesNotFireAgain() {
        // Given
        syncPromo.isPromoActiveSubject.send(true)

        // When: the bar is removed and shown again, as when a new-tab-only bar comes back
        viewController.removeFromParent()
        viewController.viewWillAppear()

        // Then
        XCTAssertFalse(viewController.syncButton.isHidden)
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
    }

    func testWhenPromoBecomesActiveWhileBarIsDetachedThenDisplayedPixelWaitsUntilBarIsShown() {
        // Given
        viewController.removeFromParent()

        // When
        syncPromo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)

        // When
        viewController.viewWillAppear()

        // Then
        XCTAssertFalse(viewController.syncButton.isHidden)
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
    }

    func testWhenSyncButtonClickedThenSyncSetupStarts() {
        // Given
        syncPromo.isPromoActiveSubject.send(true)

        // When
        viewController.syncClicked(self)

        // Then
        XCTAssertEqual(syncPromo.syncSetupStartedCount, 1)
        XCTAssertEqual(syncLauncher.startDeviceSyncFlowSources, [.bookmarksBar])
    }
}

final class MockBookmarksBarSyncPromo: BookmarksBarSyncPromoPresenting {
    let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private(set) var syncSetupStartedCount = 0

    var isPromoActivePublisher: AnyPublisher<Bool, Never> {
        isPromoActiveSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func syncSetupStarted() {
        syncSetupStartedCount += 1
    }
}
