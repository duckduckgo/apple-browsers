//
//  AutofillExtensionSettingsViewModelTests.swift
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
final class AutofillExtensionSettingsViewModelTests: XCTestCase {

    func testUpdateExtensionStatusReflectsCredentialStoreState() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = false
        let settingsHelper = MockAutofillExtensionSettingsHelper()

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper)

        await viewModel.updateExtensionStatus()
        XCTAssertFalse(viewModel.isExtensionEnabled)

        store.isEnabled = true
        await viewModel.updateExtensionStatus()
        XCTAssertTrue(viewModel.isExtensionEnabled)
    }

    func testEnableExtensionShowsActivationWhenRequestSucceeds() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = false
        let settingsHelper = MockAutofillExtensionSettingsHelper(requestResult: true)
        settingsHelper.onRequest = { store.isEnabled = true }

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper,
                                                           enableRetryThrottleDuration: 0.1)

        await viewModel.updateExtensionStatus()
        XCTAssertFalse(viewModel.isExtensionEnabled)

        await viewModel.enableExtension()

        XCTAssertEqual(settingsHelper.requestCallCount, 1)
        XCTAssertTrue(viewModel.isShowingActivationView)
        XCTAssertTrue(viewModel.isExtensionEnabled)
    }

    func testEnableExtensionThrottlesWhenUserChoosesNotNow() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = false
        let settingsHelper = MockAutofillExtensionSettingsHelper(requestResult: false)

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper,
                                                           enableRetryThrottleDuration: 0.1)

        await viewModel.updateExtensionStatus()
        XCTAssertFalse(viewModel.isExtensionEnabled)

        await viewModel.enableExtension()

        XCTAssertEqual(settingsHelper.requestCallCount, 1)
        XCTAssertFalse(viewModel.isShowingActivationView)
        XCTAssertFalse(viewModel.isExtensionEnabled)
        XCTAssertTrue(viewModel.isEnableRequestThrottled)
        XCTAssertEqual(settingsHelper.openCallCount, 0) // Should NOT open settings when user chooses "Not Now"
        XCTAssertNotNil(viewModel.remainingEnableRequestThrottleInterval)
    }

    func testEnableExtensionNotifiesDelegateOnSuccess() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = true
        let settingsHelper = MockAutofillExtensionSettingsHelper(requestResult: true)
        let delegate = MockAutofillExtensionSettingsViewModelDelegate()

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper,
                                                           enableRetryThrottleDuration: 0.1)
        viewModel.delegate = delegate

        await viewModel.enableExtension()

        XCTAssertEqual(delegate.authDisabledStates, [true, false])
    }

    func testEnableExtensionNotifiesDelegateOnFailure() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = false
        let settingsHelper = MockAutofillExtensionSettingsHelper(requestResult: false)
        let delegate = MockAutofillExtensionSettingsViewModelDelegate()

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper,
                                                           enableRetryThrottleDuration: 0.1)
        viewModel.delegate = delegate

        await viewModel.enableExtension()

        XCTAssertEqual(delegate.authDisabledStates, [true, false])
    }

    func testEnableExtensionSkipsRequestWhenThrottleActive() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = false
        let settingsHelper = MockAutofillExtensionSettingsHelper(requestResult: false)

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper,
                                                           enableRetryThrottleDuration: 0.5)

        await viewModel.enableExtension()
        XCTAssertTrue(viewModel.isEnableRequestThrottled)
        XCTAssertEqual(settingsHelper.requestCallCount, 1)

        await viewModel.enableExtension()

        XCTAssertEqual(settingsHelper.requestCallCount, 1)
        XCTAssertNotNil(viewModel.remainingEnableRequestThrottleInterval)
        XCTAssertEqual(settingsHelper.openCallCount, 1)
    }

    func testEnableExtensionThrottleExpiresAfterDuration() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = false
        let settingsHelper = MockAutofillExtensionSettingsHelper(requestResult: false)

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper,
                                                           enableRetryThrottleDuration: 0.05)

        await viewModel.enableExtension()
        XCTAssertTrue(viewModel.isEnableRequestThrottled)

        // Poll until throttle expires or timeout
        let expectation = expectation(description: "Throttle expires")
        Task {
            while viewModel.isEnableRequestThrottled {
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertFalse(viewModel.isEnableRequestThrottled)
        XCTAssertNil(viewModel.remainingEnableRequestThrottleInterval)
    }

    func testDisableExtensionRequestsOpeningSettings() async {
        let store = MockASCredentialIdentityStore()
        let settingsHelper = MockAutofillExtensionSettingsHelper()

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper)

        await viewModel.disableExtension()

        XCTAssertEqual(settingsHelper.openCallCount, 1)
    }

    func testDisableExtensionSwallowsErrors() async {
        let store = MockASCredentialIdentityStore()
        let settingsHelper = MockAutofillExtensionSettingsHelper()
        settingsHelper.openError = TestError.example

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper)

        await viewModel.disableExtension()

        XCTAssertEqual(settingsHelper.openCallCount, 1)
    }

    private enum TestError: Error {
        case example
    }
}

@available(iOS 18.0, *)
@MainActor
private final class MockAutofillExtensionSettingsHelper: AutofillExtensionSettingsHelping {

    var requestResult: Bool
    var requestCallCount = 0
    var openCallCount = 0
    var openError: Error?
    var onRequest: (() -> Void)?

    init(requestResult: Bool = false) {
        self.requestResult = requestResult
    }

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
private final class MockAutofillExtensionSettingsViewModelDelegate: AutofillExtensionSettingsViewModelDelegate {

    var authDisabledStates: [Bool] = []

    func autofillExtensionSettingsViewModel(_ viewModel: AutofillExtensionSettingsViewModel, shouldDisableAuth: Bool) {
        authDisabledStates.append(shouldDisableAuth)
    }
}
