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

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper)

        await viewModel.updateExtensionStatus()
        XCTAssertFalse(viewModel.isExtensionEnabled)

        store.isEnabled = true
        await viewModel.enableExtension()

        XCTAssertEqual(settingsHelper.requestCallCount, 1)
        XCTAssertTrue(viewModel.isShowingActivationView)
        XCTAssertTrue(viewModel.isExtensionEnabled)
    }

    func testEnableExtensionDoesNotShowActivationWhenRequestReturnsFalse() async {
        let store = MockASCredentialIdentityStore()
        store.isEnabled = false
        let settingsHelper = MockAutofillExtensionSettingsHelper(requestResult: false)

        let viewModel = AutofillExtensionSettingsViewModel(credentialStore: store,
                                                           settingsHelper: settingsHelper)

        await viewModel.updateExtensionStatus()
        XCTAssertFalse(viewModel.isExtensionEnabled)

        await viewModel.enableExtension()

        XCTAssertEqual(settingsHelper.requestCallCount, 1)
        XCTAssertFalse(viewModel.isShowingActivationView)
        XCTAssertFalse(viewModel.isExtensionEnabled)
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

    init(requestResult: Bool = false) {
        self.requestResult = requestResult
    }

    func requestToTurnOnCredentialProviderExtension() async -> Bool {
        requestCallCount += 1
        return requestResult
    }

    func openCredentialProviderAppSettings() async throws {
        openCallCount += 1

        if let openError {
            throw openError
        }
    }
}
