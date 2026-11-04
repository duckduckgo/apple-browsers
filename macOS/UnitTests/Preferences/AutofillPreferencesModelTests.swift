//
//  AutofillPreferencesModelTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import PrivacyConfig
@testable import DuckDuckGo_Privacy_Browser

final class AutofillPreferencesPersistorMock: AutofillPreferencesPersistor {
    var isAutoLockEnabled: Bool = true
    var autoLockThreshold: AutofillAutoLockThreshold = .fifteenMinutes
    var askToSaveUsernamesAndPasswords: Bool = true
    var askToSaveAddresses: Bool = true
    var askToSavePaymentMethods: Bool = true
    var passwordManager: PasswordManager = .duckduckgo
    var autolockLocksFormFilling: Bool = false
    var debugScriptEnabled: Bool = false
    var showInMenuBar: Bool = false
    var isManagedByExtension: Bool = false
}

final class UserAuthenticatorMock: UserAuthenticating {
    var didCallAuthenticate = false
    var _authenticateUser: (DeviceAuthenticator.AuthenticationReason) -> DeviceAuthenticationResult = { _ in return .success }

    func authenticateUser(reason: DeviceAuthenticator.AuthenticationReason, result: @escaping (DeviceAuthenticationResult) -> Void) {
        didCallAuthenticate = true
        let authenticationResult = _authenticateUser(reason)
        result(authenticationResult)
    }
    func authenticateUser(reason: DeviceAuthenticator.AuthenticationReason) async -> DeviceAuthenticationResult {
        didCallAuthenticate = true
        return _authenticateUser(reason)
    }
    func isAuthenticationPromptNeeded(reason: DeviceAuthenticator.AuthenticationReason) -> Bool {
        true
    }
}

final class AutofillPreferencesModelTests: XCTestCase {

    func neverPromptWebsitesManager() throws -> AutofillNeverPromptWebsitesManager {
        try AutofillNeverPromptWebsitesManager(secureVault: MockSecureVaultFactory.makeVault(reporter: nil))
    }

    @MainActor
    func testThatPreferencesArePersisted() throws {
        let persistor = AutofillPreferencesPersistorMock()
        let userAuthenticator = UserAuthenticatorMock()
        let model = try AutofillPreferencesModel(persistor: persistor, userAuthenticator: userAuthenticator, neverPromptWebsitesManager: neverPromptWebsitesManager())

        model.askToSaveUsernamesAndPasswords.toggle()
        XCTAssertEqual(persistor.askToSaveUsernamesAndPasswords, model.askToSaveUsernamesAndPasswords)

        model.askToSaveAddresses.toggle()
        XCTAssertEqual(persistor.askToSaveAddresses, model.askToSaveAddresses)

        model.askToSavePaymentMethods.toggle()
        XCTAssertEqual(persistor.askToSavePaymentMethods, model.askToSavePaymentMethods)
    }

    @MainActor
    func testWhenUserIsAuthenticatedThenAutoLockCanBeDisabled() throws {
        let persistor = AutofillPreferencesPersistorMock()
        let userAuthenticator = UserAuthenticatorMock()
        let model = try AutofillPreferencesModel(persistor: persistor, userAuthenticator: userAuthenticator, neverPromptWebsitesManager: neverPromptWebsitesManager())

        userAuthenticator._authenticateUser = { _ in return .success }

        model.authorizeAutoLockSettingsChange(isEnabled: false)
        XCTAssertEqual(model.isAutoLockEnabled, false)
        XCTAssertEqual(persistor.isAutoLockEnabled, model.isAutoLockEnabled)
    }

    @MainActor
    func testWhenUserIsNotAuthenticatedThenAutoLockCannotBeDisabled() throws {
        let persistor = AutofillPreferencesPersistorMock()
        let userAuthenticator = UserAuthenticatorMock()
        let model = try AutofillPreferencesModel(persistor: persistor, userAuthenticator: userAuthenticator, neverPromptWebsitesManager: neverPromptWebsitesManager())

        userAuthenticator._authenticateUser = { _ in return .failure }

        model.authorizeAutoLockSettingsChange(isEnabled: false)
        XCTAssertEqual(model.isAutoLockEnabled, true)
        XCTAssertEqual(persistor.isAutoLockEnabled, model.isAutoLockEnabled)
    }

    @MainActor
    func testWhenUserIsAuthenticatedThenAutoLockThresholdCanBeChanged() throws {
        let persistor = AutofillPreferencesPersistorMock()
        let userAuthenticator = UserAuthenticatorMock()
        let model = try AutofillPreferencesModel(persistor: persistor, userAuthenticator: userAuthenticator, neverPromptWebsitesManager: neverPromptWebsitesManager())

        userAuthenticator._authenticateUser = { _ in return .success }

        model.authorizeAutoLockSettingsChange(threshold: .oneHour)
        XCTAssertEqual(model.isAutoLockEnabled, true)
        XCTAssertEqual(model.autoLockThreshold, .oneHour)
        XCTAssertEqual(persistor.autoLockThreshold, model.autoLockThreshold)
    }

    @MainActor
    func testWhenUserIsNotAuthenticatedThenAutoLockThresholdCannotBeChanged() throws {
        let persistor = AutofillPreferencesPersistorMock()
        let userAuthenticator = UserAuthenticatorMock()
        let model = try AutofillPreferencesModel(persistor: persistor, userAuthenticator: userAuthenticator, neverPromptWebsitesManager: neverPromptWebsitesManager())

        userAuthenticator._authenticateUser = { _ in return .failure }

        model.authorizeAutoLockSettingsChange(threshold: .oneHour)
        XCTAssertNotEqual(model.autoLockThreshold, .oneHour)
        XCTAssertEqual(persistor.autoLockThreshold, model.autoLockThreshold)
    }

    @MainActor
    func testWhenDuckDuckGoIsThePasswordManagerThenActivePromoIsShown() throws {
        let syncPromoManager = MockSyncPromoManager()
        let model = try AutofillPreferencesModel(persistor: AutofillPreferencesPersistorMock(), userAuthenticator: UserAuthenticatorMock(),
                                                 neverPromptWebsitesManager: neverPromptWebsitesManager(), syncPromoManager: syncPromoManager)
        XCTAssertFalse(model.showSyncPromo)

        syncPromoManager.isPromoActiveSubject.send(true)

        XCTAssertTrue(model.showSyncPromo)
    }

    @MainActor
    func testWhenBitwardenIsThePasswordManagerThenActivePromoIsNotShown() throws {
        let persistor = AutofillPreferencesPersistorMock()
        persistor.passwordManager = .bitwarden
        let syncPromoManager = MockSyncPromoManager()
        syncPromoManager.isPromoActiveSubject.send(true)

        let model = try AutofillPreferencesModel(persistor: persistor, userAuthenticator: UserAuthenticatorMock(),
                                                 neverPromptWebsitesManager: neverPromptWebsitesManager(), syncPromoManager: syncPromoManager)

        XCTAssertFalse(model.showSyncPromo)
    }

    // MARK: - Extension Managing Autofill

    @MainActor
    func testWhenAnExtensionManagesAutofill_ThenTheModelReportsIt() throws {
        let persistor = AutofillPreferencesPersistorMock()
        persistor.isManagedByExtension = true

        let model = try makeModel(persistor: persistor, notificationCenter: NotificationCenter())

        XCTAssertTrue(model.isManagedByExtension)
    }

    @MainActor
    func testWhenAnExtensionTakesOverWhileSettingsAreOpen_ThenTheModelFollows() throws {
        let persistor = AutofillPreferencesPersistorMock()
        let notificationCenter = NotificationCenter()
        let model = try makeModel(persistor: persistor, notificationCenter: notificationCenter)
        XCTAssertFalse(model.isManagedByExtension)

        let updated = expectation(description: "isManagedByExtension updated")
        let cancellable = model.$isManagedByExtension.dropFirst().sink { _ in updated.fulfill() }

        persistor.isManagedByExtension = true
        notificationCenter.post(name: .autofillUserSettingsDidChange, object: nil)

        wait(for: [updated], timeout: 1)
        XCTAssertTrue(model.isManagedByExtension)
        cancellable.cancel()
    }

    // MARK: - Password Manager

    @MainActor
    func testWhenWebExtensionsAreSupportedAndDuckDuckGoUserSelectsBitwarden_ThenDuckDuckGoStaysSelected() throws {
        let persistor = AutofillPreferencesPersistorMock()
        let model = try makeModel(persistor: persistor, notificationCenter: NotificationCenter(), areWebExtensionsSupported: true)

        model.passwordManagerSettingsChange(passwordManager: .bitwarden)

        XCTAssertEqual(model.passwordManager, .duckduckgo)
        XCTAssertEqual(persistor.passwordManager, .duckduckgo)
    }

    @MainActor
    func testWhenPasswordManagerChangesWhileSettingsAreOpen_ThenTheModelFollows() throws {
        let persistor = AutofillPreferencesPersistorMock()
        persistor.passwordManager = .bitwarden
        let notificationCenter = NotificationCenter()
        let model = try makeModel(persistor: persistor, notificationCenter: notificationCenter)
        XCTAssertEqual(model.passwordManager, .bitwarden)

        let updated = expectation(description: "passwordManager updated")
        let cancellable = model.$passwordManager.dropFirst().sink { _ in updated.fulfill() }

        persistor.passwordManager = .duckduckgo
        notificationCenter.post(name: .autofillUserSettingsDidChange, object: nil)

        wait(for: [updated], timeout: 1)
        XCTAssertEqual(model.passwordManager, .duckduckgo)
        cancellable.cancel()
    }

    @MainActor
    private func makeModel(persistor: AutofillPreferencesPersistorMock, notificationCenter: NotificationCenter,
                           areWebExtensionsSupported: Bool = true) throws -> AutofillPreferencesModel {
        try AutofillPreferencesModel(persistor: persistor, userAuthenticator: UserAuthenticatorMock(),
                                     neverPromptWebsitesManager: neverPromptWebsitesManager(), syncPromoManager: MockSyncPromoManager(),
                                     notificationCenter: notificationCenter, areWebExtensionsSupported: areWebExtensionsSupported)
    }
}
