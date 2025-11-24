//
//  AutofillExtensionEnableCoordinatorTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo
@testable import BrowserServicesKitTestsUtils

@available(iOS 18.0, *)
@MainActor
final class AutofillExtensionEnableCoordinatorTests: XCTestCase {

    private var mockStore: MockASCredentialIdentityStore!
    private var mockSettingsHelper: MockAutofillExtensionSettingsHelper!
    private var coordinator: AutofillExtensionEnableCoordinator!
    private var mockDelegate: MockAutofillExtensionEnableCoordinatorDelegate!

    override func setUpWithError() throws {
        super.setUp()
        mockStore = MockASCredentialIdentityStore()
        mockSettingsHelper = MockAutofillExtensionSettingsHelper()
        mockDelegate = MockAutofillExtensionEnableCoordinatorDelegate()

        coordinator = AutofillExtensionEnableCoordinator(
            source: "test",
            credentialStore: mockStore,
            settingsHelper: mockSettingsHelper
        )
        coordinator.delegate = mockDelegate
    }

    override func tearDownWithError() throws {
        coordinator = nil
        mockDelegate = nil
        mockSettingsHelper = nil
        mockStore = nil

        try super.tearDownWithError()
    }

    // MARK: - updateExtensionStatus Tests

    func testWhenExtensionIsEnabledThenUpdateExtensionStatusReturnsTrue() async {
        // Given
        mockStore.isEnabled = true

        // When
        let result = await coordinator.updateExtensionStatus()

        // Then
        XCTAssertTrue(result)
    }

    func testWhenExtensionIsDisabledThenUpdateExtensionStatusReturnsFalse() async {
        // Given
        mockStore.isEnabled = false

        // When
        let result = await coordinator.updateExtensionStatus()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - enableExtension Success Tests

    func testWhenUserEnablesExtensionThenReturnsSuccess() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = true
        mockSettingsHelper.onRequest = { [weak mockStore] in
            mockStore?.isEnabled = true
        }

        // When
        let result = await coordinator.enableExtension()

        // Then
        XCTAssertEqual(result, .success)
        XCTAssertEqual(mockSettingsHelper.requestCallCount, 1)
        XCTAssertEqual(mockSettingsHelper.openCallCount, 0)
        XCTAssertFalse(coordinator.isEnableRequestThrottled)
    }

    func testWhenEnableSucceedsThenNotifiesDelegate() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = true
        mockSettingsHelper.onRequest = { [weak mockStore] in
            mockStore?.isEnabled = true
        }

        // When
        let result = await coordinator.enableExtension()

        // Then
        XCTAssertEqual(result, .success)
        XCTAssertEqual(mockDelegate.shouldDisableAuthCalls, [true, false])
    }

    // MARK: - enableExtension Cancelled Tests

    func testWhenUserChoosesNotNowThenReturnsCancelled() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        // When
        let result = await coordinator.enableExtension()

        // Then
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(mockSettingsHelper.requestCallCount, 1)
        XCTAssertEqual(mockSettingsHelper.openCallCount, 0)
        XCTAssertTrue(coordinator.isEnableRequestThrottled)
    }

    func testWhenUserCancelsThenNotifiesDelegate() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        // When
        let result = await coordinator.enableExtension()

        // Then
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(mockDelegate.shouldDisableAuthCalls, [true, false])
    }

    // MARK: - enableExtension Failed Tests

    func testWhenUserChoosesEnableButExtensionNotEnabledThenReturnsFailed() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = true
        // Extension remains disabled after request

        // When
        let result = await coordinator.enableExtension()

        // Then
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(mockSettingsHelper.requestCallCount, 1)
        XCTAssertEqual(mockSettingsHelper.openCallCount, 1)
        XCTAssertTrue(coordinator.isEnableRequestThrottled)
    }

    // MARK: - Throttle Tests

    func testWhenThrottledThenEnableExtensionOpensSettings() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        // First request to trigger throttle
        let firstResult = await coordinator.enableExtension()
        XCTAssertEqual(firstResult, .cancelled)
        XCTAssertTrue(coordinator.isEnableRequestThrottled)

        // When - second request while throttled
        let secondResult = await coordinator.enableExtension()

        // Then
        XCTAssertEqual(secondResult, .throttled)
        XCTAssertEqual(mockSettingsHelper.requestCallCount, 1) // Only called once
        XCTAssertEqual(mockSettingsHelper.openCallCount, 1) // Opens settings instead
    }

    func testWhenThrottledThenRemainingIntervalIsPositive() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        // When
        await coordinator.enableExtension()

        // Then
        XCTAssertTrue(coordinator.isEnableRequestThrottled)
        XCTAssertNotNil(coordinator.remainingEnableRequestThrottleInterval)
        if let remaining = coordinator.remainingEnableRequestThrottleInterval {
            XCTAssertGreaterThan(remaining, 0)
        }
    }

    func testWhenThrottleExpiresThenRemainingIntervalIsNil() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        let shortThrottleCoordinator = AutofillExtensionEnableCoordinator(
            source: "test",
            credentialStore: mockStore,
            settingsHelper: mockSettingsHelper,
            enableRetryThrottleDuration: 0.1
        )

        // When
        await shortThrottleCoordinator.enableExtension()
        XCTAssertTrue(shortThrottleCoordinator.isEnableRequestThrottled)

        // Wait for throttle to expire
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        // Then
        XCTAssertFalse(shortThrottleCoordinator.isEnableRequestThrottled)
        XCTAssertNil(shortThrottleCoordinator.remainingEnableRequestThrottleInterval)
    }

    func testClearEnableRequestThrottleResetsState() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        await coordinator.enableExtension()
        XCTAssertTrue(coordinator.isEnableRequestThrottled)

        // When
        coordinator.clearEnableRequestThrottle()

        // Then
        XCTAssertFalse(coordinator.isEnableRequestThrottled)
        XCTAssertNil(coordinator.remainingEnableRequestThrottleInterval)
    }

    func testWhenThrottleClearedThenNextEnableRequestProceeds() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        await coordinator.enableExtension()
        XCTAssertEqual(mockSettingsHelper.requestCallCount, 1)

        coordinator.clearEnableRequestThrottle()

        // When
        await coordinator.enableExtension()

        // Then
        XCTAssertEqual(mockSettingsHelper.requestCallCount, 2) // Called again
    }

    // MARK: - Edge Case Tests

    func testWhenSettingsHelperThrowsErrorThenHandlesGracefully() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = true
        mockSettingsHelper.openError = TestError.settingsUnavailable

        // When
        let result = await coordinator.enableExtension()

        // Then - Should still return failed even if opening settings throws
        XCTAssertEqual(result, .failed)
    }

    func testMultipleSequentialEnableAttemptsWithDifferentOutcomes() async {
        // Given
        mockStore.isEnabled = false
        mockSettingsHelper.requestResult = false

        // First attempt - user cancels
        let result1 = await coordinator.enableExtension()
        XCTAssertEqual(result1, .cancelled)
        XCTAssertTrue(coordinator.isEnableRequestThrottled)

        // Second attempt - throttled
        let result2 = await coordinator.enableExtension()
        XCTAssertEqual(result2, .throttled)

        // Clear throttle and change user behavior
        coordinator.clearEnableRequestThrottle()
        mockSettingsHelper.requestResult = true
        mockSettingsHelper.onRequest = { [weak mockStore] in
            mockStore?.isEnabled = true
        }

        // Third attempt - succeeds
        let result3 = await coordinator.enableExtension()
        XCTAssertEqual(result3, .success)
        XCTAssertFalse(coordinator.isEnableRequestThrottled)
    }

    private enum TestError: Error {
        case settingsUnavailable
    }
}

// MARK: - Mock Objects

@available(iOS 18.0, *)
@MainActor
private final class MockAutofillExtensionSettingsHelper: AutofillExtensionSettingsHelping {

    var requestResult: Bool = false
    var requestCallCount = 0
    var openCallCount = 0
    var openError: Error?
    var onRequest: (() -> Void)?

    func requestToTurnOnCredentialProviderExtension() async -> Bool {
        requestCallCount += 1
        onRequest?()
        return requestResult
    }

    func openCredentialProviderAppSettings() async throws {
        openCallCount += 1
        if let openError {
            throw openError
        }
    }
}

@available(iOS 18.0, *)
private final class MockAutofillExtensionEnableCoordinatorDelegate: AutofillExtensionEnableCoordinatorDelegate {

    var shouldDisableAuthCalls: [Bool] = []

    @MainActor
    func autofillExtensionEnableCoordinator(_ coordinator: AutofillExtensionEnableCoordinator, shouldDisableAuth: Bool) {
        shouldDisableAuthCalls.append(shouldDisableAuth)
    }
}
