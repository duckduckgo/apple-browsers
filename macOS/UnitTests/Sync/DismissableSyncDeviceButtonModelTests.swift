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
import DDGSync
import FeatureFlags_macOS
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DismissableSyncDeviceButtonModelTests: XCTestCase {

    private var mockKeyValueStore: MockKeyValueStore!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockSyncLauncher: MockSyncDeviceFlowLauncher!
    private var authStateSubject: PassthroughSubject<SyncAuthState, Never>!
    private var pixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()
        mockKeyValueStore = MockKeyValueStore()
        mockFeatureFlagger = MockFeatureFlagger()
        mockSyncLauncher = MockSyncDeviceFlowLauncher()
        authStateSubject = PassthroughSubject<SyncAuthState, Never>()
        pixelFiring = PixelKitMock()
    }

    override func tearDown() {
        mockKeyValueStore = nil
        mockFeatureFlagger = nil
        mockSyncLauncher = nil
        authStateSubject = nil
        pixelFiring = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_ProperInitialization() {
        let model = createModel(source: .bookmarkAdded)

        XCTAssertFalse(model.shouldShowSyncButton)
    }

    // MARK: - Auth State Change Tests

    func testAuthStateChange_InactiveWithAllConditionsMet_ShowsButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        let model = createModel(source: .bookmarkAdded)

        let expectation = expectation(description: "shouldShowSyncButton should be true")
        let cancellable = model.$shouldShowSyncButton
            .sink { value in
                if value {
                    expectation.fulfill()
                }
            }

        authStateSubject.send(.inactive)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testAuthStateChange_NotInactive_HidesButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        let model = createModel(source: .bookmarkAdded)

        let expectation = expectation(description: "shouldShowSyncButton should be false")
        let cancellable = model.$shouldShowSyncButton
            .sink { value in
                if !value {
                    expectation.fulfill()
                }
            }

        authStateSubject.send(.active)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testAuthStateChange_InactiveButDismissed_HidesButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        mockKeyValueStore.set(true, forKey: "com.duckduckgo.bookmarkAddedSyncPromoDismissed")
        let model = createModel(source: .bookmarkAdded)

        let expectation = expectation(description: "shouldShowSyncButton should remain false")
        let cancellable = model.$shouldShowSyncButton
            .dropFirst() // Skip initial value
            .sink { value in
                if !value {
                    expectation.fulfill()
                }
            }

        authStateSubject.send(.inactive)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testAuthStateChange_InactiveButCountLimitReached_HidesButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        mockKeyValueStore.set(5, forKey: "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount")
        let model = createModel(source: .bookmarkAdded)

        let expectation = expectation(description: "shouldShowSyncButton should remain false")
        let cancellable = model.$shouldShowSyncButton
            .dropFirst() // Skip initial value
            .sink { value in
                if !value {
                    expectation.fulfill()
                }
            }

        authStateSubject.send(.inactive)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testAuthStateChange_InactiveButFeatureFlagOff_HidesButton() {
        for enabledFeatureFlags in [[], [FeatureFlag.newSyncEntryPoints], [FeatureFlag.syncFeatureLevel3]] {
            mockFeatureFlagger.enableFeatures(enabledFeatureFlags)
            let model = createModel(source: .bookmarkAdded)

            let expectation = expectation(description: "shouldShowSyncButton should be true")
            let cancellable = model.$shouldShowSyncButton
                .dropFirst() // Skip initial value
                .sink { value in
                    expectation.fulfill()
                    if value {
                        XCTFail("Sync button should not be visible")
                    }
                }

            authStateSubject.send(.inactive)

            wait(for: [expectation], timeout: 1.0)
            cancellable.cancel()
            mockFeatureFlagger.enabledFeatureFlags = []
        }
    }

    // MARK: - viewDidLoad Tests

    func testViewDidLoad_FeatureFlagsDisabled_HidesButton() {
        // Feature flags disabled by default in mock
        let model = createModel(source: .bookmarkAdded)
        authStateSubject.send(.inactive)

        model.viewDidLoad()

        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testViewDidLoad_AuthStateNotInactive_HidesButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        let model = createModel(source: .bookmarkAdded)
        authStateSubject.send(.active)

        model.viewDidLoad()

        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testViewDidLoad_AlreadyDismissed_HidesButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        mockKeyValueStore.set(true, forKey: "com.duckduckgo.bookmarkAddedSyncPromoDismissed")
        let model = createModel(source: .bookmarkAdded)
        authStateSubject.send(.inactive)

        model.viewDidLoad()

        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testViewDidLoad_CountLimitReached_HidesButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        let model = createModel(source: .bookmarkAdded)
        waitForInitialInactiveStateToEnableSyncButton(on: model)
        mockKeyValueStore.set(5, forKey: "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount")
        XCTAssertTrue(model.shouldShowSyncButton)

        // First call should increment to 5 and reach limit
        model.viewDidLoad()

        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testViewDidLoad_AllConditionsMet_ShowsButton() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        let model = createModel(source: .bookmarkAdded)

        waitForInitialInactiveStateToEnableSyncButton(on: model)

        // Now test viewDidLoad - should remain true
        model.viewDidLoad()

        XCTAssertTrue(model.shouldShowSyncButton)
    }

    func testViewDidLoad_BookmarkAdded_IncrementsCount() {
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        let model = createModel(source: .bookmarkAdded)

        waitForInitialInactiveStateToEnableSyncButton(on: model)

        // Now test viewDidLoad - should remain true and increment count
        model.viewDidLoad()
        XCTAssertTrue(model.shouldShowSyncButton)
        XCTAssertEqual(mockKeyValueStore.object(forKey: "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount") as? Int, 1)
    }

    // MARK: - Action Tests

    func testSyncButtonAction_CallsSyncLauncher() {
        let model = createModel(source: .bookmarkAdded)

        model.syncButtonAction()

        XCTAssertTrue(mockSyncLauncher.startDeviceSyncFlowCalled)
    }

    func testDismissSyncButtonAction_HidesButtonAndStoresState() {
        let model = createModel(source: .bookmarkAdded)
        // First show the button
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])

        waitForInitialInactiveStateToEnableSyncButton(on: model)

        model.dismissSyncButtonAction()

        XCTAssertFalse(model.shouldShowSyncButton)
        XCTAssertEqual(mockKeyValueStore.object(forKey: "com.duckduckgo.bookmarkAddedSyncPromoDismissed") as? Bool, true)
    }

    // MARK: - State Management Tests

    func testResetAllState_ClearsAllKeys() {
        // Set up some state
        mockKeyValueStore.set(true, forKey: "com.duckduckgo.bookmarkAddedSyncPromoDismissed")
        mockKeyValueStore.set(3, forKey: "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount")

        DismissableSyncDeviceButtonModel.resetAllState(from: mockKeyValueStore)

        XCTAssertNil(mockKeyValueStore.object(forKey: "com.duckduckgo.bookmarkAddedSyncPromoDismissed"))
        XCTAssertNil(mockKeyValueStore.object(forKey: "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount"))
    }

    // MARK: - Promo-backed Tests

    func testWhenPromoIsActiveThenSyncButtonIsShown() {
        // Given
        let promo = MockBookmarksBarSyncPromo()
        let model = createModel(source: .bookmarksBar, promo: promo)

        // When
        promo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertTrue(model.shouldShowSyncButton)

        // When
        promo.isPromoActiveSubject.send(false)

        // Then
        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testWhenPromoBackedThenAuthStateChangesDoNotShowSyncButton() {
        // Given
        mockFeatureFlagger.enableFeatures([.newSyncEntryPoints, .syncFeatureLevel3])
        let model = createModel(source: .bookmarksBar, promo: MockBookmarksBarSyncPromo())

        // When
        authStateSubject.send(.inactive)
        model.viewDidLoad()

        // Then
        XCTAssertFalse(model.shouldShowSyncButton)
    }

    func testWhenPromoBecomesActiveThenDisplayedPixelWaitsForButtonToAppear() {
        // Given
        let promo = MockBookmarksBarSyncPromo()
        let model = createModel(source: .bookmarksBar, promo: promo)

        // When
        promo.isPromoActiveSubject.send(true)

        // Then
        XCTAssertTrue(model.shouldShowSyncButton)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenSyncButtonAppearsRepeatedlyThenDisplayedPixelFiresOnce() {
        // Given
        let model = createModel(source: .bookmarksBar, promo: MockBookmarksBarSyncPromo())

        // When
        model.syncButtonDidAppear()
        model.syncButtonDidAppear()

        // Then
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarksBar"])
    }

    func testWhenPromoBackedSyncButtonActionThenSetupStartsAndConfirmedPixelFires() {
        // Given
        let promo = MockBookmarksBarSyncPromo()
        let model = createModel(source: .bookmarksBar, promo: promo)

        // When
        model.syncButtonAction()

        // Then
        XCTAssertEqual(promo.syncSetupStartedCount, 1)
        XCTAssertEqual(mockSyncLauncher.startDeviceSyncFlowSources, [.bookmarksBar])
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoConfirmed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarksBar"])
    }

    func testResetAllState_ClearsBookmarksBarLegacyKeys() {
        // Given
        mockKeyValueStore.set(true, forKey: "com.duckduckgo.bookmarksBarSyncPromoDismissed")
        mockKeyValueStore.set(Date(), forKey: "com.duckduckgo.bookmarkFirstPresentedCount")

        // When
        DismissableSyncDeviceButtonModel.resetAllState(from: mockKeyValueStore)

        // Then
        XCTAssertNil(mockKeyValueStore.object(forKey: "com.duckduckgo.bookmarksBarSyncPromoDismissed"))
        XCTAssertNil(mockKeyValueStore.object(forKey: "com.duckduckgo.bookmarkFirstPresentedCount"))
    }

    // MARK: - Helper Methods

    private func createModel(source: DismissableSyncDeviceButtonModel.DismissableSyncDevicePromoSource,
                             promo: BookmarksBarSyncPromoPresenting? = nil) -> DismissableSyncDeviceButtonModel {
        return DismissableSyncDeviceButtonModel(
            source: source,
            keyValueStore: mockKeyValueStore,
            authStatePublisher: authStateSubject.eraseToAnyPublisher(),
            initialAuthState: .initializing,
            syncLauncher: mockSyncLauncher,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: pixelFiring,
            promo: promo
        )
    }

    func waitForInitialInactiveStateToEnableSyncButton(on model: DismissableSyncDeviceButtonModel) {
        let setupExpectation = expectation(description: "shouldShowSyncButton should be true after auth state change")
        let setupCancellable = model.$shouldShowSyncButton
            .sink { value in
                if value {
                    setupExpectation.fulfill()
                }
            }

        authStateSubject.send(.inactive)
        wait(for: [setupExpectation], timeout: 1.0)
        setupCancellable.cancel()
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

// MARK: - Date Extension for Testing

private extension Date {
    func isLessThan(daysAgo days: Int) -> Bool {
        let timeInterval = TimeInterval(days * 24 * 60 * 60)
        let daysAgoDate = Date().addingTimeInterval(-timeInterval)
        return self > daysAgoDate
    }
}
