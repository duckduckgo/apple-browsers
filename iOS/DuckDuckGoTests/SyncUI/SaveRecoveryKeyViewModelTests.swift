//
//  SaveRecoveryKeyViewModelTests.swift
//  DuckDuckGoTests
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
@testable import SyncUI_iOS

final class SaveRecoveryKeyViewModelTests: XCTestCase {

    func testWhenFeatureEnabledAndNoExistingDecisionThenPersistsDefaultEnabledDecision() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = nil

        _ = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {},
            autoRestoreProvider: autoRestoreProvider
        )

        XCTAssertEqual(autoRestoreProvider.persistedDecisions, [true])
    }

    func testWhenFeatureEnabledAndNoExistingDecisionAndPersistFailsThenKeepsDisabledState() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = nil
        autoRestoreProvider.persistError = AutoRestoreProviderTestError.expected

        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {},
            autoRestoreProvider: autoRestoreProvider
        )

        XCTAssertFalse(sut.isAutoRestoreEnabled)
        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
    }

    func testWhenFeatureEnabledAndExistingDecisionProvidedThenUsesDecisionWithoutPersisting() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = false

        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {},
            autoRestoreProvider: autoRestoreProvider
        )

        XCTAssertFalse(sut.isAutoRestoreEnabled)
        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
    }

    func testWhenFeatureDisabledThenDoesNotPersistInitialDecision() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = false
        autoRestoreProvider.existingAutoRestoreDecision = nil

        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {},
            autoRestoreProvider: autoRestoreProvider
        )

        XCTAssertFalse(sut.isAutoRestoreFeatureEnabled)
        XCTAssertFalse(sut.isAutoRestoreEnabled)
        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
    }

    func testWhenAutoRestoreToggledAndValueUnchangedThenDoesNotPersist() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = true
        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {},
            autoRestoreProvider: autoRestoreProvider
        )

        sut.autoRestoreToggled(true)

        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
    }

    func testWhenAutoRestoreToggledAndPersistSucceedsThenUpdatesState() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = true
        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {},
            autoRestoreProvider: autoRestoreProvider
        )

        sut.autoRestoreToggled(false)

        XCTAssertFalse(sut.isAutoRestoreEnabled)
        XCTAssertEqual(autoRestoreProvider.persistedDecisions, [false])
    }

    func testWhenAutoRestoreToggledAndPersistFailsThenKeepsOriginalState() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = true
        autoRestoreProvider.persistError = AutoRestoreProviderTestError.expected
        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {},
            autoRestoreProvider: autoRestoreProvider
        )

        sut.autoRestoreToggled(false)

        XCTAssertTrue(sut.isAutoRestoreEnabled)
        XCTAssertTrue(autoRestoreProvider.persistedDecisions.isEmpty)
    }

    func testWhenNextButtonPressedThenDismissesFlow() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = false
        var onDismissCalled = false
        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {
                onDismissCalled = true
            },
            autoRestoreProvider: autoRestoreProvider
        )

        sut.nextButtonPressed()

        XCTAssertTrue(onDismissCalled)
    }

    func testWhenNextButtonPressedAndAutoRestoreIsDisabledThenFiresOptOutAndDismissesFlow() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = false
        var onDismissCalled = false
        var optedOutCalled = false
        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {
                onDismissCalled = true
            },
            autoRestoreProvider: autoRestoreProvider,
            onAutoRestoreToggleOptedOut: {
                optedOutCalled = true
            }
        )

        sut.nextButtonPressed()

        XCTAssertTrue(optedOutCalled)
        XCTAssertTrue(onDismissCalled)
    }

    func testWhenNextButtonPressedAndAutoRestoreIsEnabledThenDoesNotFireOptOutAndDismissesFlow() {
        let autoRestoreProvider = MockSyncAutoRestoreHandler()
        autoRestoreProvider.isAutoRestoreFeatureEnabled = true
        autoRestoreProvider.existingAutoRestoreDecision = true
        var onDismissCalled = false
        var optedOutCalled = false
        let sut = SaveRecoveryKeyViewModel(
            key: "test-key",
            showRecoveryPDFAction: {},
            onDismiss: {
                onDismissCalled = true
            },
            autoRestoreProvider: autoRestoreProvider,
            onAutoRestoreToggleOptedOut: {
                optedOutCalled = true
            }
        )

        sut.nextButtonPressed()

        XCTAssertFalse(optedOutCalled)
        XCTAssertTrue(onDismissCalled)
    }

}

private enum AutoRestoreProviderTestError: Error {
    case expected
}
