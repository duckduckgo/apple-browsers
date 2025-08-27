//
//  SessionRestorePromptCoordinatorTests.swift
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
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

final class SessionRestorePromptCoordinatorTests: XCTestCase {

    private var coordinator: SessionRestorePromptCoordinator!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var notificationCenter: NotificationCenter!
    private var receivedNotifications: [Notification] = []

    override func setUpWithError() throws {
        mockFeatureFlagger = MockFeatureFlagger()
        coordinator = SessionRestorePromptCoordinator(featureFlagger: mockFeatureFlagger)
        notificationCenter = NotificationCenter.default
        receivedNotifications = []

        // Set up notification observer
        notificationCenter.addObserver(
            forName: .sessionRestorePromptShouldBeShown,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.receivedNotifications.append(notification)
        }
    }

    override func tearDownWithError() throws {
        notificationCenter.removeObserver(self)
        notificationCenter = nil
        coordinator = nil
        mockFeatureFlagger = nil
        receivedNotifications = []
    }

    // MARK: - Initial State Tests

    func testMarkUIReady_whenInitialState_doesNotTriggerPrompt() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.restoreSessionPrompt]
        coordinator.markUIReady()

        XCTAssertTrue(receivedNotifications.isEmpty)
    }

    func testShowRestoreSessionPrompt_whenInitialState_doesNotTriggerPrompt() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.restoreSessionPrompt]
        coordinator.showRestoreSessionPrompt(restoreAction: { _ in })

        XCTAssertTrue(receivedNotifications.isEmpty)
    }

    // MARK: - State Transition Tests

    func testMarkUIReady_afterShowRestoreSessionPrompt_triggersPromptWhenFeatureEnabled() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.restoreSessionPrompt]
        coordinator.showRestoreSessionPrompt(restoreAction: { _ in })

        coordinator.markUIReady()

        XCTAssertEqual(receivedNotifications.count, 1)
        XCTAssertEqual(receivedNotifications.first?.name, .sessionRestorePromptShouldBeShown)
    }

    func testMarkUIReady_afterShowRestoreSessionPrompt_doesNotTriggerPromptWhenFeatureDisabled() throws {
        mockFeatureFlagger.enabledFeatureFlags = []
        coordinator.showRestoreSessionPrompt(restoreAction: { _ in })

        coordinator.markUIReady()

        XCTAssertTrue(receivedNotifications.isEmpty)
    }

    func testShowRestoreSessionPrompt_afterMarkUIReady_triggersPromptImmediatelyWhenFeatureEnabled() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.restoreSessionPrompt]
        coordinator.markUIReady()

        coordinator.showRestoreSessionPrompt(restoreAction: { _ in })

        XCTAssertEqual(receivedNotifications.count, 1)
        XCTAssertEqual(receivedNotifications.first?.name, .sessionRestorePromptShouldBeShown)
    }

    func testShowRestoreSessionPrompt_afterMarkUIReady_doesNotTriggerPromptWhenFeatureDisabled() throws {
        mockFeatureFlagger.enabledFeatureFlags = []
        coordinator.markUIReady()

        coordinator.showRestoreSessionPrompt(restoreAction: { _ in })

        XCTAssertTrue(receivedNotifications.isEmpty)
    }

    func testShowRestoreSessionPrompt_afterMarkUIReady_triggersPromptWithExpectedRestoreAction() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.restoreSessionPrompt]
        coordinator.markUIReady()
        var restoreSession = false
        let restoreAction: (Bool) -> Void = { _ in restoreSession = true }

        coordinator.showRestoreSessionPrompt(restoreAction: restoreAction)

        XCTAssertEqual(receivedNotifications.count, 1)
        if let notificationAction = receivedNotifications.first?.object as? (Bool) -> Void {
            notificationAction(true)
            XCTAssertTrue(restoreSession)
        } else {
            XCTFail("Notification action is not of expected type")
        }
    }

    // MARK: - Multiple Call Protection Tests

    func testMultipleShowRestoreSessionPromptCalls_onlyFirstOneIsProcessed() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.restoreSessionPrompt]
        coordinator.markUIReady()
        var firstActionCalled = false
        var secondActionCalled = false
        let firstAction: (Bool) -> Void = { _ in firstActionCalled = true }
        let secondAction: (Bool) -> Void = { _ in secondActionCalled = true }

        coordinator.showRestoreSessionPrompt(restoreAction: firstAction)
        coordinator.showRestoreSessionPrompt(restoreAction: secondAction)

        XCTAssertEqual(receivedNotifications.count, 1)
        if let notificationAction = receivedNotifications.first?.object as? (Bool) -> Void {
            notificationAction(true)
            XCTAssertTrue(firstActionCalled)
            XCTAssertFalse(secondActionCalled)
        } else {
            XCTFail("Notification action is not of expected type")
        }
    }

    func testMultipleMarkUIReadyCalls_afterPromptShown_doesNotTriggerAdditionalNotifications() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.restoreSessionPrompt]
        coordinator.markUIReady()
        coordinator.showRestoreSessionPrompt(restoreAction: { _ in })

        coordinator.markUIReady()
        coordinator.markUIReady()

        XCTAssertEqual(receivedNotifications.count, 1)
    }
}
