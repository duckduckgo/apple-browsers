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
import PrivacyConfigTestsUtils
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
    var kindsManagedByExtension: Set<ExtensionManagedAutofillKind> = []
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

    // MARK: - Extensions Managing Autofill

    @MainActor
    func testWhenOneExtensionManagesEverything_ThenItIsShownOnceWithAllKinds() throws {
        let bitwarden = AutofillManagingExtension(identifier: "bitwarden", name: "Bitwarden", icon: nil)
        let takeover = makeTakeover([.passwords: bitwarden, .addresses: bitwarden, .cards: bitwarden])

        let model = try makeModel(takeover: takeover)

        XCTAssertEqual(model.managingExtension(for: .passwords), bitwarden)
        XCTAssertEqual(model.kinds(managedBy: bitwarden), [.passwords, .addresses, .cards])
        XCTAssertTrue(model.extensionsManagingOnlyAddressesOrCards.isEmpty)
    }

    @MainActor
    func testWhenAnotherExtensionManagesOnlyCards_ThenItIsShownSeparately() throws {
        let bitwarden = AutofillManagingExtension(identifier: "bitwarden", name: "Bitwarden", icon: nil)
        let cardsOnly = AutofillManagingExtension(identifier: "cards", name: "Cards", icon: nil)
        let takeover = makeTakeover([.passwords: bitwarden, .cards: cardsOnly])

        let model = try makeModel(takeover: takeover)

        XCTAssertEqual(model.kinds(managedBy: bitwarden), [.passwords])
        XCTAssertEqual(model.extensionsManagingOnlyAddressesOrCards, [cardsOnly])
    }

    @MainActor
    func testWhenTheUserUsesDuckDuckGoInstead_ThenEveryKindOfThatExtensionIsGivenBack() throws {
        var clearedKinds: [ExtensionManagedAutofillKind] = []
        let bitwarden = AutofillManagingExtension(identifier: "bitwarden", name: "Bitwarden", icon: nil)
        let takeover = makeTakeover([.passwords: bitwarden, .cards: bitwarden]) { clearedKinds.append($0) }
        let model = try makeModel(takeover: takeover)

        model.useDuckDuckGoInstead(for: model.kinds(managedBy: bitwarden))

        XCTAssertEqual(clearedKinds, [.passwords, .cards])
    }

    @MainActor
    func testWhenAnExtensionTakesOverWhileSettingsAreOpen_ThenTheModelFollows() throws {
        let bitwarden = AutofillManagingExtension(identifier: "bitwarden", name: "Bitwarden", icon: nil)
        var managing: WebExtensionAutofillTakeover.ManagingExtensions = [:]
        let takeover = WebExtensionAutofillTakeover(preferences: AutofillPreferencesPersistorMock(),
                                                    privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                    notificationCenter: NotificationCenter(),
                                                    readManagingExtensions: { managing },
                                                    clearSetting: { _ in })
        let model = try makeModel(takeover: takeover)
        XCTAssertNil(model.managingExtension(for: .passwords))

        managing = [.passwords: bitwarden]
        takeover.refresh()
        NotificationCenter.default.post(name: .autofillUserSettingsDidChange, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(model.managingExtension(for: .passwords), bitwarden)
    }

    @MainActor
    private func makeTakeover(_ managing: WebExtensionAutofillTakeover.ManagingExtensions,
                              clearSetting: @escaping @MainActor (ExtensionManagedAutofillKind) -> Void = { _ in }) -> WebExtensionAutofillTakeover {
        let takeover = WebExtensionAutofillTakeover(preferences: AutofillPreferencesPersistorMock(),
                                                    privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                    notificationCenter: NotificationCenter(),
                                                    readManagingExtensions: { managing },
                                                    clearSetting: clearSetting)
        takeover.refresh()
        return takeover
    }

    @MainActor
    private func makeModel(takeover: WebExtensionAutofillTakeover) throws -> AutofillPreferencesModel {
        try AutofillPreferencesModel(persistor: AutofillPreferencesPersistorMock(), userAuthenticator: UserAuthenticatorMock(),
                                     neverPromptWebsitesManager: neverPromptWebsitesManager(), syncPromoManager: MockSyncPromoManager(),
                                     autofillTakeover: takeover)
    }
}
