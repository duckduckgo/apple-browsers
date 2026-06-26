//
//  DuckAIFireOnboardingLockSyncTests.swift
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

// Regression tests for the race condition where `setDuckAIFireControlsLocked(true)`
// is called before the UTI coordinator exists (coordinator creation is intentionally
// deferred until after linear onboarding). Without an explicit sync step, the lock call
// is lost and the coordinator starts unlocked.
//
// Fix location: `MainViewController+UnifiedToggleInput.swift`
//   `setUpUnifiedToggleInputIfNeeded()` — after creating the coordinator, it checks
//   `duckAIFireOnboardingFlow.controlsLocked` and applies the lock if needed.

import AIChat
import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAIFireOnboardingLockSyncTests: XCTestCase {

    private var mockPreferences: MockAIChatPreferencesLockSync!
    private var mockToggleModeStorage: MockToggleModeStorageLockSync!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        mockPreferences = MockAIChatPreferencesLockSync()
        mockToggleModeStorage = MockToggleModeStorageLockSync()
    }

    override func tearDown() {
        cancellables.removeAll()
        mockPreferences = nil
        mockToggleModeStorage = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCoordinator() -> UnifiedToggleInputCoordinator {
        UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            preferences: mockPreferences,
            toggleModeStorage: mockToggleModeStorage
        )
    }

    /// Applies the exact sync guard from `setUpUnifiedToggleInputIfNeeded` to a freshly-created coordinator.
    private func applySyncIfNeeded(from context: DuckAIFireOnboardingFlowContext,
                                   to coordinator: UnifiedToggleInputCoordinator) {
        if context.controlsLocked {
            coordinator.setOnboardingControlsLocked(true)
        }
    }

    // MARK: - Lock was armed before coordinator existed

    func test_whenFlowContextIsLocked_coordinatorIsLockedAfterSync() {
        var context = DuckAIFireOnboardingFlowContext()
        context.controlsLocked = true

        let coordinator = makeCoordinator()
        applySyncIfNeeded(from: context, to: coordinator)

        XCTAssertTrue(coordinator.isOnboardingLocked,
                      "Coordinator created after fire onboarding armed the lock must be locked after sync")
    }

    func test_whenFlowContextIsLocked_syncedCoordinatorBlocksExpansion() {
        var context = DuckAIFireOnboardingFlowContext()
        context.controlsLocked = true

        let coordinator = makeCoordinator()
        applySyncIfNeeded(from: context, to: coordinator)

        coordinator.showExpanded()

        XCTAssertNotEqual(coordinator.displayState, .aiTab(.expanded),
                          "A coordinator that received the deferred lock must not expand during onboarding")
    }

    func test_whenFlowContextIsLocked_syncedCoordinatorDoesNotEmitExpandIntent() {
        var context = DuckAIFireOnboardingFlowContext()
        context.controlsLocked = true

        let coordinator = makeCoordinator()
        applySyncIfNeeded(from: context, to: coordinator)

        let exp = expectation(description: "showExpanded intent must not fire when coordinator is lock-synced")
        exp.isInverted = true
        coordinator.intentPublisher
            .sink { if case .showExpanded = $0 { exp.fulfill() } }
            .store(in: &cancellables)

        coordinator.showExpanded()

        waitForExpectations(timeout: 0.3)
    }

    // MARK: - Lock was not armed (normal path)

    func test_whenFlowContextIsNotLocked_coordinatorRemainsUnlocked() {
        let context = DuckAIFireOnboardingFlowContext()
        // controlsLocked defaults to false

        let coordinator = makeCoordinator()
        applySyncIfNeeded(from: context, to: coordinator)

        XCTAssertFalse(coordinator.isOnboardingLocked,
                       "Coordinator must not be locked when fire onboarding was never armed")
    }

    func test_whenFlowContextIsNotLocked_coordinatorCanExpand() {
        let context = DuckAIFireOnboardingFlowContext()

        let coordinator = makeCoordinator()
        applySyncIfNeeded(from: context, to: coordinator)

        coordinator.showExpanded()

        XCTAssertEqual(coordinator.displayState, .aiTab(.expanded),
                       "Coordinator must expand normally when the fire onboarding lock was never set")
    }
}

// MARK: - Private mocks

private final class MockAIChatPreferencesLockSync: AIChatPreferencesPersisting {
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningEffort: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class MockToggleModeStorageLockSync: ToggleModeStoring {
    private var storedMode: TextEntryMode?
    func save(_ mode: TextEntryMode) { storedMode = mode }
    func restore() -> TextEntryMode? { storedMode }
}
