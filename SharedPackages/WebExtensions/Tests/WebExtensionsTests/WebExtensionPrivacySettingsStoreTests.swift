//
//  WebExtensionPrivacySettingsStoreTests.swift
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

#if os(macOS)
@_spi(Testing) import Persistence
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class WebExtensionPrivacySettingsStoreTests: XCTestCase {

    private let keyValueStore = InMemoryThrowingKeyValueStore()
    private var date = Date(timeIntervalSince1970: 1_000)
    private var allowed: Set<String> = ["bitwarden", "other"]

    private func makeStore() -> WebExtensionPrivacySettingsStore {
        let store = WebExtensionPrivacySettingsStore(keyValueStore: keyValueStore, now: { [unowned self] in self.date })
        store.canControl = { [unowned self] in self.allowed.contains($0) }
        return store
    }

    // MARK: - Control

    func testWhenNothingIsSet_ThenNobodyControlsTheSettingAndExtensionsCanTakeIt() {
        let store = makeStore()

        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
        let details = store.details(of: .passwordSavingEnabled, for: "bitwarden")
        XCTAssertTrue(details.value)
        XCTAssertEqual(details.levelOfControl, .controllableByThisExtension)
    }

    func testWhenAnExtensionTurnsASettingOff_ThenItControlsItAndOthersSeeThat() {
        let store = makeStore()

        XCTAssertNoThrow(try store.set(false, for: .passwordSavingEnabled, by: "bitwarden"))

        XCTAssertEqual(store.identifierTurningOff(.passwordSavingEnabled), "bitwarden")
        let own = store.details(of: .passwordSavingEnabled, for: "bitwarden")
        XCTAssertFalse(own.value)
        XCTAssertEqual(own.levelOfControl, .controlledByThisExtension)
        let other = store.details(of: .passwordSavingEnabled, for: "other")
        XCTAssertFalse(other.value)
        XCTAssertEqual(other.levelOfControl, .controlledByOtherExtensions)
    }

    func testWhenAnExtensionTurnsASettingOn_ThenItControlsItButNothingIsTurnedOff() throws {
        let store = makeStore()

        try store.set(true, for: .passwordSavingEnabled, by: "bitwarden")

        XCTAssertEqual(store.controllingIdentifier(for: .passwordSavingEnabled), "bitwarden")
        XCTAssertNil(store.identifierTurningOff(.passwordSavingEnabled))
    }

    func testWhenSettingsAreSetSeparately_ThenEachHasItsOwnController() throws {
        let store = makeStore()

        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")

        XCTAssertNil(store.identifierTurningOff(.autofillAddressEnabled))
        XCTAssertNil(store.identifierTurningOff(.autofillCreditCardEnabled))
    }

    func testWhenTwoExtensionsSetTheSameSetting_ThenTheMostRecentControlsIt() throws {
        let store = makeStore()

        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")
        date += 1
        try store.set(true, for: .passwordSavingEnabled, by: "other")

        XCTAssertEqual(store.controllingIdentifier(for: .passwordSavingEnabled), "other")
        XCTAssertNil(store.identifierTurningOff(.passwordSavingEnabled))
        XCTAssertEqual(store.details(of: .passwordSavingEnabled, for: "bitwarden").levelOfControl, .controlledByOtherExtensions)
    }

    func testWhenTheControllingExtensionClearsTheSetting_ThenTheNextOneControlsIt() throws {
        let store = makeStore()
        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")
        date += 1
        try store.set(false, for: .passwordSavingEnabled, by: "other")

        try store.clear(.passwordSavingEnabled, for: "other")

        XCTAssertEqual(store.identifierTurningOff(.passwordSavingEnabled), "bitwarden")
    }

    func testWhenTheOnlyControllerClearsTheSetting_ThenItGoesBackToItsDefault() throws {
        let store = makeStore()
        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")

        try store.clear(.passwordSavingEnabled, for: "bitwarden")

        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
        XCTAssertEqual(store.details(of: .passwordSavingEnabled, for: "bitwarden").levelOfControl, .controllableByThisExtension)
    }

    func testWhenEveryValueOfASettingIsCleared_ThenNoExtensionControlsItAndOtherSettingsAreKept() throws {
        let store = makeStore()
        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")
        date += 1
        try store.set(false, for: .passwordSavingEnabled, by: "other")
        try store.set(false, for: .autofillAddressEnabled, by: "other")

        store.clearAll(.passwordSavingEnabled)

        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
        XCTAssertEqual(store.identifierTurningOff(.autofillAddressEnabled), "other")
    }

    // MARK: - Extensions That May Not Control Settings

    func testWhenAnExtensionMayNotControlSettings_ThenItsSetIsRefused() {
        let store = makeStore()

        XCTAssertThrowsError(try store.set(false, for: .passwordSavingEnabled, by: "undeclared"))

        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
        XCTAssertEqual(store.details(of: .passwordSavingEnabled, for: "undeclared").levelOfControl, .notControllable)
    }

    func testWhenTheControllingExtensionIsUnloaded_ThenItNoLongerControlsTheSetting() throws {
        let store = makeStore()
        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")

        allowed.remove("bitwarden")

        XCTAssertNil(store.identifierTurningOff(.passwordSavingEnabled))

        allowed.insert("bitwarden")

        XCTAssertEqual(store.identifierTurningOff(.passwordSavingEnabled), "bitwarden")
    }

    // MARK: - Persistence

    func testWhenTheStoreIsRecreated_ThenTheSettingsAreKept() throws {
        try makeStore().set(false, for: .passwordSavingEnabled, by: "bitwarden")

        XCTAssertEqual(makeStore().identifierTurningOff(.passwordSavingEnabled), "bitwarden")
    }

    func testWhenAnInstallationIsUpdated_ThenItsSettingsAreCopiedToTheNewInstallation() throws {
        let store = makeStore()
        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")
        allowed = ["updated"]

        store.copySettingsForUpdate(from: "bitwarden", to: "updated")

        XCTAssertEqual(store.identifierTurningOff(.passwordSavingEnabled), "updated")
    }

    func testWhenAnInstallationIsRemoved_ThenOnlyItsSettingsAreRemoved() throws {
        let store = makeStore()
        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")
        try store.set(false, for: .autofillAddressEnabled, by: "other")

        store.removeSettings(for: "bitwarden")

        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
        XCTAssertEqual(store.identifierTurningOff(.autofillAddressEnabled), "other")
    }

    // MARK: - Notifications

    func testWhenASettingChanges_ThenObserversAreTold() throws {
        let store = makeStore()
        let changed = expectation(forNotification: .webExtensionPrivacySettingsDidChange, object: store)

        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")

        wait(for: [changed], timeout: 1)
    }

    func testWhenASetChangesNothing_ThenObserversAreNotTold() throws {
        let store = makeStore()
        let changed = expectation(forNotification: .webExtensionPrivacySettingsDidChange, object: store)
        changed.isInverted = true

        try store.clear(.passwordSavingEnabled, for: "bitwarden")

        wait(for: [changed], timeout: 0.2)
    }
}
#endif
