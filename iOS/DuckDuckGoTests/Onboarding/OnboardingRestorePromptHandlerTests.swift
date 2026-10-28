//
//  OnboardingRestorePromptHandlerTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo

final class OnboardingRestorePromptHandlerTests: XCTestCase {

    func testWhenConfigurationIsDisabledThenRestorePromptEligibilityIsFalse() {
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        syncAutoRestoreHandler.isEligibleForAutoRestoreValue = true
        let authenticator = MockAuthenticator()
        authenticator.isAuthenticationAvailable = true

        let sut = OnboardingRestorePromptHandler(
            configuration: .disabled,
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            authenticator: authenticator
        )

        XCTAssertFalse(sut.isEligibleForRestorePrompt())
    }

    func testWhenConfigurationIsEnabledAndDependenciesAreEligibleThenRestorePromptEligibilityIsTrue() {
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        syncAutoRestoreHandler.isEligibleForAutoRestoreValue = true
        let authenticator = MockAuthenticator()
        authenticator.isAuthenticationAvailable = true

        let sut = OnboardingRestorePromptHandler(
            configuration: .enabled,
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            authenticator: authenticator
        )

        XCTAssertTrue(sut.isEligibleForRestorePrompt())
    }

    func testWhenConfigurationIsEnabledAndAutoRestoreIsNotEligibleThenRestorePromptEligibilityIsFalse() {
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        syncAutoRestoreHandler.isEligibleForAutoRestoreValue = false
        let authenticator = MockAuthenticator()
        authenticator.isAuthenticationAvailable = true

        let sut = OnboardingRestorePromptHandler(
            configuration: .enabled,
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            authenticator: authenticator
        )

        XCTAssertFalse(sut.isEligibleForRestorePrompt())
    }

    func testWhenConfigurationIsEnabledAndDeviceCannotAuthenticateThenRestorePromptEligibilityIsFalse() {
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        syncAutoRestoreHandler.isEligibleForAutoRestoreValue = true
        let authenticator = MockAuthenticator()
        authenticator.isAuthenticationAvailable = false

        let sut = OnboardingRestorePromptHandler(
            configuration: .enabled,
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            authenticator: authenticator
        )

        XCTAssertFalse(sut.isEligibleForRestorePrompt())
    }

    func testWhenConfigurationIsEnabledThenRestoreSyncAccountInvokesSyncAutoRestoreHandler() {
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        let restoreCalledExpectation = expectation(description: "Restore from preserved account is invoked")
        syncAutoRestoreHandler.onRestoreFromPreservedAccount = {
            restoreCalledExpectation.fulfill()
        }
        let authenticator = MockAuthenticator()

        let sut = OnboardingRestorePromptHandler(
            configuration: .enabled,
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            authenticator: authenticator
        )

        sut.restoreSyncAccount()

        wait(for: [restoreCalledExpectation], timeout: 1.0)
        XCTAssertEqual(syncAutoRestoreHandler.restoreFromPreservedAccountCallCount, 1)
    }

    func testWhenConfigurationIsDisabledThenRestoreSyncAccountDoesNotInvokeSyncAutoRestoreHandler() {
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        let authenticator = MockAuthenticator()

        let sut = OnboardingRestorePromptHandler(
            configuration: .disabled,
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            authenticator: authenticator
        )

        sut.restoreSyncAccount()

        XCTAssertEqual(syncAutoRestoreHandler.restoreFromPreservedAccountCallCount, 0)
    }
}
