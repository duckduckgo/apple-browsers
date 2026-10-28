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

import PrivacyConfig
import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WebExtensionAutofillTakeoverTests: XCTestCase {

    private static let bitwarden = AutofillManagingExtension(identifier: "bitwarden", name: "Bitwarden", icon: nil)

    private var notificationCenter: NotificationCenter!
    private var preferences: AutofillPreferencesPersistorMock!
    private var managingExtension: AutofillManagingExtension?
    private var givenBackCount = 0

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        preferences = AutofillPreferencesPersistorMock()
    }

    override func tearDown() {
        notificationCenter = nil
        preferences = nil
        managingExtension = nil
        givenBackCount = 0
        super.tearDown()
    }

    private func makeTakeover() -> WebExtensionAutofillTakeover {
        WebExtensionAutofillTakeover(preferences: preferences,
                                     notificationCenter: notificationCenter,
                                     readManagingExtension: { [unowned self] in self.managingExtension },
                                     clearSettings: { [unowned self] in self.givenBackCount += 1 })
    }

    // MARK: - Refresh

    func testWhenAnExtensionTakesOver_ThenAllDuckDuckGoAutofillStepsAsideAndScriptsAreRebuilt() {
        let takeover = makeTakeover()
        managingExtension = Self.bitwarden
        let rebuilt = expectation(forNotification: .autofillUserSettingsDidChange, object: nil, notificationCenter: notificationCenter)

        takeover.refresh()

        wait(for: [rebuilt], timeout: 1)
        XCTAssertEqual(takeover.managingExtension, Self.bitwarden)
        XCTAssertTrue(preferences.isManagedByExtension)
        XCTAssertFalse(preferences.isUsernamesAndPasswordsAutofillActive)
        XCTAssertFalse(preferences.isAddressesAutofillActive)
        XCTAssertFalse(preferences.isPaymentMethodsAutofillActive)
    }

    /// Every rebuild reloads the autofill scripts, and extensions loading or setting the same value
    /// again refresh often, so nothing may be rebuilt unless the answer changed.
    func testWhenNothingChanged_ThenAutofillScriptsAreNotRebuilt() {
        let takeover = makeTakeover()
        managingExtension = Self.bitwarden
        takeover.refresh()
        let rebuilt = expectation(forNotification: .autofillUserSettingsDidChange, object: nil, notificationCenter: notificationCenter)
        rebuilt.isInverted = true

        takeover.refresh()

        wait(for: [rebuilt], timeout: 0.2)
    }

    /// The saved state applies at launch, before extensions load. Once no extension manages autofill,
    /// the first refresh hands it back.
    func testWhenSavedTakeoverIsNoLongerTrue_ThenRefreshHandsAutofillBack() {
        preferences.isManagedByExtension = true
        let takeover = makeTakeover()
        XCTAssertFalse(preferences.isUsernamesAndPasswordsAutofillActive)

        takeover.refresh()

        XCTAssertFalse(preferences.isManagedByExtension)
        XCTAssertTrue(preferences.isUsernamesAndPasswordsAutofillActive)
        XCTAssertTrue(preferences.isAddressesAutofillActive)
    }

    func testWhenAnExtensionChangesItsPrivacySettings_ThenTheTakeoverIsReadAgain() {
        let takeover = makeTakeover()
        managingExtension = Self.bitwarden

        notificationCenter.post(name: .webExtensionPrivacySettingsDidChange, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(takeover.managingExtension, Self.bitwarden)
        XCTAssertTrue(preferences.isManagedByExtension)
    }

    /// Tabs restored at launch rely on the saved state until extensions finish loading.
    func testWhenTheTakeoverIsCreated_ThenTheSavedStateIsKept() {
        preferences.isManagedByExtension = true

        _ = makeTakeover()

        XCTAssertTrue(preferences.isManagedByExtension)
    }

    func testWhenAutofillIsGivenBack_ThenTheExtensionsSettingsAreCleared() {
        let takeover = makeTakeover()

        takeover.giveBackToDuckDuckGo()

        XCTAssertEqual(givenBackCount, 1)
    }

    // MARK: - Whether DuckDuckGo Autofill Is Active

    func testWhenTheUserTurnedAKindOff_ThenItStaysOffWithoutAnExtension() {
        preferences.askToSaveAddresses = false

        XCTAssertFalse(preferences.isAddressesAutofillActive)
        XCTAssertTrue(preferences.isUsernamesAndPasswordsAutofillActive)
    }
}
