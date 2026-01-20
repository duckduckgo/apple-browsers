//
//  AIChatTogglePopoverCoordinatorTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class MockAIChatTogglePopoverPresenter: AIChatTogglePopoverPresenting {
    var isPopoverBeingPresentedValue = false
    var showPopoverCalled = false
    var showPopoverViewController: PopoverMessageViewController?
    var showPopoverToggleControl: NSView?
    var dismissPopoverCalled = false
    var notifyPopoverDismissedCalled = false

    func isPopoverBeingPresented() -> Bool {
        return isPopoverBeingPresentedValue
    }

    func showPopover(viewController: PopoverMessageViewController, relativeTo toggleControl: NSView) {
        showPopoverCalled = true
        showPopoverViewController = viewController
        showPopoverToggleControl = toggleControl
        isPopoverBeingPresentedValue = true
    }

    func dismissPopover() {
        dismissPopoverCalled = true
        isPopoverBeingPresentedValue = false
    }

    func notifyPopoverDismissed() {
        notifyPopoverDismissedCalled = true
        isPopoverBeingPresentedValue = false
    }

    func reset() {
        isPopoverBeingPresentedValue = false
        showPopoverCalled = false
        showPopoverViewController = nil
        showPopoverToggleControl = nil
        dismissPopoverCalled = false
        notifyPopoverDismissedCalled = false
    }
}

@MainActor
final class AIChatTogglePopoverCoordinatorTests: XCTestCase {

    var coordinator: AIChatTogglePopoverCoordinator!
    var mockPresenter: MockAIChatTogglePopoverPresenter!
    var mockWindowControllersManager: WindowControllersManagerMock!
    var mockToggleControl: NSView!

    private let popoverSeenKey = "aichat.toggle.popover.seen"

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockPresenter = MockAIChatTogglePopoverPresenter()
        mockWindowControllersManager = WindowControllersManagerMock()
        mockToggleControl = NSView()

        // Clear the popover seen flag before each test
        UserDefaults.standard.removeObject(forKey: popoverSeenKey)

        coordinator = AIChatTogglePopoverCoordinator(
            windowControllersManager: mockWindowControllersManager,
            themeManager: MockThemeManager(),
            presenter: mockPresenter
        )
    }

    override func tearDown() {
        coordinator = nil
        mockPresenter = nil
        mockWindowControllersManager = nil
        mockToggleControl = nil

        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: popoverSeenKey)

        super.tearDown()
    }

    // MARK: - Tests for showPopoverIfNeeded

    func testWhenPopoverAlreadyPresentedThenDoesNotShowPopover() {
        // Given
        mockPresenter.isPopoverBeingPresentedValue = true

        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )

        // Then
        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    func testWhenPopoverHasBeenPresentedBeforeThenDoesNotShowPopover() {
        // Given
        UserDefaults.standard.set(true, forKey: popoverSeenKey)

        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )

        // Then
        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    func testWhenUserIsNewThenDoesNotShowPopover() {
        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: true,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )

        // Then
        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    func testWhenUserHasInteractedWithToggleThenDoesNotShowPopover() {
        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: true,
            userDidSeeToggleOnboarding: false
        )

        // Then
        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    func testWhenAllConditionsMetThenShowsPopover() {
        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )

        // Then
        XCTAssertTrue(mockPresenter.showPopoverCalled)
        XCTAssertNotNil(mockPresenter.showPopoverViewController)
        XCTAssertEqual(mockPresenter.showPopoverToggleControl, mockToggleControl)
    }

    func testWhenMultipleConditionsFailThenDoesNotShowPopover() {
        // Given - multiple failing conditions
        UserDefaults.standard.set(true, forKey: popoverSeenKey)

        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: true,
            userDidInteractWithToggle: true,
            userDidSeeToggleOnboarding: false
        )

        // Then
        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    // MARK: - Tests for dismissPopover

    func testWhenPopoverIsPresentedThenDismissesPopover() {
        // Given
        mockPresenter.isPopoverBeingPresentedValue = true

        // When
        coordinator.dismissPopover()

        // Then
        XCTAssertTrue(mockPresenter.dismissPopoverCalled)
    }

    func testWhenPopoverIsNotPresentedThenDoesNotCallDismiss() {
        // Given
        mockPresenter.isPopoverBeingPresentedValue = false

        // When
        coordinator.dismissPopover()

        // Then
        XCTAssertFalse(mockPresenter.dismissPopoverCalled)
    }

    // MARK: - Tests for showPopoverForDebug

    func testWhenDebugShowAndPopoverNotPresentedThenShowsPopover() {
        // When
        coordinator.showPopoverForDebug(relativeTo: mockToggleControl)

        // Then
        XCTAssertTrue(mockPresenter.showPopoverCalled)
        XCTAssertNotNil(mockPresenter.showPopoverViewController)
    }

    func testWhenDebugShowAndPopoverAlreadyPresentedThenDoesNotShowPopover() {
        // Given
        mockPresenter.isPopoverBeingPresentedValue = true

        // When
        coordinator.showPopoverForDebug(relativeTo: mockToggleControl)

        // Then
        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    func testDebugShowIgnoresOtherConditions() {
        // Given - conditions that would normally prevent showing
        UserDefaults.standard.set(true, forKey: popoverSeenKey)

        // When - debug show should still work
        coordinator.showPopoverForDebug(relativeTo: mockToggleControl)

        // Then
        XCTAssertTrue(mockPresenter.showPopoverCalled)
    }

    // MARK: - Tests for clearPopoverSeenFlag

    func testClearPopoverSeenFlagRemovesFlag() {
        // Given
        UserDefaults.standard.set(true, forKey: popoverSeenKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: popoverSeenKey))

        // When
        coordinator.clearPopoverSeenFlag()

        // Then
        XCTAssertFalse(UserDefaults.standard.bool(forKey: popoverSeenKey))
    }

    // MARK: - Tests for popover seen flag being set

    func testWhenPopoverShownAndClosedThenMarksAsSeen() {
        // Given
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )
        XCTAssertTrue(mockPresenter.showPopoverCalled)

        // When - simulate close
        mockPresenter.showPopoverViewController?.viewModel.onClose?()

        // Then
        XCTAssertTrue(UserDefaults.standard.bool(forKey: popoverSeenKey))
    }

    func testWhenPopoverButtonClickedThenMarksAsSeen() {
        // Given
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )
        XCTAssertTrue(mockPresenter.showPopoverCalled)

        // When - simulate button action
        mockPresenter.showPopoverViewController?.viewModel.buttonAction?()

        // Then
        XCTAssertTrue(UserDefaults.standard.bool(forKey: popoverSeenKey))
    }

    // MARK: - Tests for popover configuration

    func testPopoverHasCorrectConfiguration() {
        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )

        // Then
        let viewController = mockPresenter.showPopoverViewController
        XCTAssertNotNil(viewController)

        guard let viewController = viewController else {
            XCTFail("ViewController should not be nil")
            return
        }

        XCTAssertEqual(viewController.viewModel.title, UserText.aiChatTogglePopoverTitle)
        XCTAssertEqual(viewController.viewModel.message, UserText.aiChatTogglePopoverMessage)
        XCTAssertTrue(viewController.viewModel.shouldShowCloseButton)
        XCTAssertNotNil(viewController.viewModel.image)

        if case .featureDiscovery = viewController.viewModel.popoverStyle {
            // Correct style
        } else {
            XCTFail("Expected featureDiscovery popover style")
        }
    }

    func testPopoverHasCorrectAutoDismissDuration() {
        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )

        // Then
        let viewController = mockPresenter.showPopoverViewController
        XCTAssertNotNil(viewController)
        XCTAssertEqual(viewController?.autoDismissDuration, 8.0)
    }

    // MARK: - Test showing popover again after clearing flag

    func testCanShowPopoverAgainAfterClearingFlag() {
        // Given - first show
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )
        XCTAssertTrue(mockPresenter.showPopoverCalled)

        // Simulate close and mark as seen
        mockPresenter.showPopoverViewController?.viewModel.onClose?()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: popoverSeenKey))

        // Reset mock
        mockPresenter.reset()

        // Second attempt should fail (already seen)
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )
        XCTAssertFalse(mockPresenter.showPopoverCalled)

        // Clear the flag
        coordinator.clearPopoverSeenFlag()

        // Third attempt should succeed
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: false
        )
        XCTAssertTrue(mockPresenter.showPopoverCalled)
    }

    func testWhenUserDidSeeToggleOnboardingThenDoesNotShowPopover() {
        // When
        coordinator.showPopoverIfNeeded(
            relativeTo: mockToggleControl,
            isNewUser: false,
            userDidInteractWithToggle: false,
            userDidSeeToggleOnboarding: true
        )

        // Then
        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }
}
