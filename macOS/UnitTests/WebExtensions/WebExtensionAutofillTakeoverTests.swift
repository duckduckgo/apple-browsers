//
//  WebExtensionAutofillTakeoverTests.swift
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

import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WebExtensionAutofillTakeoverTests: XCTestCase {

    private static let bitwarden = AutofillManagingExtension(identifier: "bitwarden", name: "Bitwarden", icon: nil)

    private var notificationCenter: NotificationCenter!
    private var preferences: AutofillPreferencesPersistorMock!
    private var managingExtensions: WebExtensionAutofillTakeover.ManagingExtensions = [:]
    private var clearedKinds: [ExtensionManagedAutofillKind] = []

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        preferences = AutofillPreferencesPersistorMock()
    }

    override func tearDown() {
        notificationCenter = nil
        preferences = nil
        managingExtensions = [:]
        clearedKinds = []
        super.tearDown()
    }

    private func makeTakeover() -> WebExtensionAutofillTakeover {
        WebExtensionAutofillTakeover(preferences: preferences,
                                     readManagingExtensions: { [unowned self] in self.managingExtensions },
                                     clearSetting: { [unowned self] in self.clearedKinds.append($0) },
                                     notificationCenter: notificationCenter)
    }

    // MARK: - Refresh

    func testWhenAnExtensionTakesPasswordsOver_ThenOnlyPasswordAutofillStepsAsideAndScriptsAreRebuilt() {
        let takeover = makeTakeover()
        managingExtensions = [.passwords: Self.bitwarden]
        let rebuilt = expectation(forNotification: .autofillUserSettingsDidChange, object: nil, notificationCenter: notificationCenter)

        takeover.refresh()

        wait(for: [rebuilt], timeout: 1)
        XCTAssertEqual(takeover.managingExtension(for: .passwords), Self.bitwarden)
        XCTAssertEqual(preferences.kindsManagedByExtension, [.passwords])
        XCTAssertFalse(preferences.isUsernamesAndPasswordsAutofillActive)
        XCTAssertTrue(preferences.isAddressesAutofillActive)
        XCTAssertTrue(preferences.isPaymentMethodsAutofillActive)
    }

    /// Every rebuild reloads the autofill scripts, and extensions loading or setting the same value
    /// again refresh often, so nothing may be rebuilt unless the answer changed.
    func testWhenNothingChanged_ThenAutofillScriptsAreNotRebuilt() {
        let takeover = makeTakeover()
        managingExtensions = [.passwords: Self.bitwarden]
        takeover.refresh()
        let rebuilt = expectation(forNotification: .autofillUserSettingsDidChange, object: nil, notificationCenter: notificationCenter)
        rebuilt.isInverted = true

        takeover.refresh()

        wait(for: [rebuilt], timeout: 0.2)
    }

    /// The saved kinds apply at launch, before extensions load. Once nothing manages them, the first
    /// refresh hands autofill back.
    func testWhenSavedKindsAreNoLongerManaged_ThenRefreshHandsAutofillBack() {
        preferences.kindsManagedByExtension = [.passwords, .cards]
        let takeover = makeTakeover()
        XCTAssertFalse(preferences.isUsernamesAndPasswordsAutofillActive)

        takeover.refresh()

        XCTAssertEqual(preferences.kindsManagedByExtension, [])
        XCTAssertTrue(preferences.isUsernamesAndPasswordsAutofillActive)
    }

    func testWhenAnExtensionChangesItsPrivacySettings_ThenTheTakeoverIsReadAgain() {
        let takeover = makeTakeover()
        managingExtensions = [.cards: Self.bitwarden]

        notificationCenter.post(name: .webExtensionPrivacySettingsDidChange, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(takeover.managingExtension(for: .cards), Self.bitwarden)
        XCTAssertEqual(preferences.kindsManagedByExtension, [.cards])
    }

    func testWhenAKindIsGivenBack_ThenItsSettingIsCleared() {
        let takeover = makeTakeover()

        takeover.giveBackToDuckDuckGo(.addresses)

        XCTAssertEqual(clearedKinds, [.addresses])
    }

    // MARK: - Whether DuckDuckGo Autofill Is Active

    func testWhenTheUserTurnedAKindOff_ThenItStaysOffWithoutAnExtension() {
        preferences.askToSaveAddresses = false

        XCTAssertFalse(preferences.isAddressesAutofillActive)
        XCTAssertTrue(preferences.isUsernamesAndPasswordsAutofillActive)
    }
}
