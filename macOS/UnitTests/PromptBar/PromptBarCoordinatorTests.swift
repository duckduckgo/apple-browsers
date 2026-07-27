//
//  PromptBarCoordinatorTests.swift
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

import Carbon.HIToolbox
import FeatureFlags
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

private final class MockPromptBarPreferencesPersistor: PromptBarPreferencesPersistor {
    var isKeyboardShortcutEnabled: Bool = true
    var keyboardShortcut: PromptBarShortcut = .defaultShortcut
    var isMenuBarIconVisible: Bool = true
}

private final class MockGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var registeredShortcut: PromptBarShortcut?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private var handler: (() -> Void)?

    func register(_ shortcut: PromptBarShortcut, handler: @escaping () -> Void) -> Bool {
        registerCallCount += 1
        registeredShortcut = shortcut
        self.handler = handler
        return true
    }

    func unregister() {
        unregisterCallCount += 1
        registeredShortcut = nil
        handler = nil
    }

    func simulateShortcutPressed() {
        handler?()
    }
}

@MainActor
private final class MockPromptBarPresenter: PromptBarPresenting {
    var isVisible = false
    private(set) var toggleCallCount = 0

    func show() { isVisible = true }
    func dismiss() { isVisible = false }
    func toggle() {
        toggleCallCount += 1
        isVisible.toggle()
    }
}

@MainActor
final class PromptBarCoordinatorTests: XCTestCase {

    // Doubles are built here, not passed as defaults: defaults are evaluated nonisolated.
    private func makeCoordinator(
        isFeatureOn: Bool = true,
        persistor: MockPromptBarPreferencesPersistor = MockPromptBarPreferencesPersistor(),
        isDuckAIAvailable: Bool = true
    ) -> (PromptBarCoordinator, PromptBarPreferences, MockGlobalShortcutRegistrar, MockPromptBarPresenter) {
        let registrar = MockGlobalShortcutRegistrar()
        let presenter = MockPromptBarPresenter()
        let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.macosPromptBar.rawValue: isFeatureOn])

        let configuration = MockAIChatConfig()
        configuration.shouldDisplayAnyAIChatFeature = isDuckAIAvailable

        let preferences = PromptBarPreferences(persistor: persistor, aiChatMenuConfiguration: configuration)
        let coordinator = PromptBarCoordinator(featureFlagger: featureFlagger,
                                               preferences: preferences,
                                               shortcutRegistrar: registrar,
                                               presenter: presenter)
        return (coordinator, preferences, registrar, presenter)
    }

    func testWhenFeatureFlagIsOffThenNoShortcutIsRegistered() {
        let (coordinator, _, registrar, _) = makeCoordinator(isFeatureOn: false)

        coordinator.start()

        XCTAssertEqual(registrar.registerCallCount, 0)
        XCTAssertNil(registrar.registeredShortcut)
    }

    func testWhenStartedThenStoredShortcutIsRegistered() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])
        let (coordinator, _, registrar, _) = makeCoordinator(persistor: persistor)

        coordinator.start()

        XCTAssertEqual(registrar.registeredShortcut, persistor.keyboardShortcut)
    }

    func testWhenShortcutSettingIsOffThenNothingIsRegistered() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isKeyboardShortcutEnabled = false
        let (coordinator, _, registrar, _) = makeCoordinator(persistor: persistor)

        coordinator.start()

        XCTAssertNil(registrar.registeredShortcut)
        XCTAssertEqual(registrar.unregisterCallCount, 1)
    }

    func testWhenDuckAIIsUnavailableThenNothingIsRegistered() {
        let (coordinator, _, registrar, _) = makeCoordinator(isDuckAIAvailable: false)

        coordinator.start()

        XCTAssertNil(registrar.registeredShortcut)
    }

    func testWhenShortcutChangesThenItIsReRegistered() {
        let (coordinator, preferences, registrar, _) = makeCoordinator()
        coordinator.start()

        let updated = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .shift])
        preferences.keyboardShortcut = updated

        XCTAssertEqual(registrar.registeredShortcut, updated)
        XCTAssertEqual(registrar.registerCallCount, 2)
    }

    func testWhenShortcutIsDisabledAfterStartThenItIsUnregistered() {
        let (coordinator, preferences, registrar, _) = makeCoordinator()
        coordinator.start()

        preferences.isKeyboardShortcutEnabled = false

        XCTAssertNil(registrar.registeredShortcut)
        XCTAssertGreaterThanOrEqual(registrar.unregisterCallCount, 1)
    }

    func testWhenTogglingThenPresenterIsToggled() {
        let (coordinator, _, _, presenter) = makeCoordinator()

        coordinator.togglePromptBar()

        XCTAssertEqual(presenter.toggleCallCount, 1)
        XCTAssertTrue(presenter.isVisible)
    }

    func testWhenFeatureFlagIsOffThenTogglingDoesNothing() {
        let (coordinator, _, _, presenter) = makeCoordinator(isFeatureOn: false)

        coordinator.togglePromptBar()

        XCTAssertEqual(presenter.toggleCallCount, 0)
    }
}
