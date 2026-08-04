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

/// Both flags start off, mirroring the opt-in product default.
private final class MockPromptBarPreferencesPersistor: PromptBarPreferencesPersistor {
    var isKeyboardShortcutEnabled: Bool = false
    var keyboardShortcut: PromptBarShortcut = .defaultShortcut
    var isMenuBarIconVisible: Bool = false
}

private extension MockPromptBarPreferencesPersistor {
    /// Opted in, so a test asserting nothing is registered isolates the gate it exercises
    /// instead of passing on the off-by-default preference.
    static var optedIn: MockPromptBarPreferencesPersistor {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isKeyboardShortcutEnabled = true
        persistor.isMenuBarIconVisible = true
        return persistor
    }
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
    private(set) var toggleSources: [PromptBarPresentationSource] = []

    func show(source: PromptBarPresentationSource) { isVisible = true }
    func dismiss(reason: PromptBarDismissReason) { isVisible = false }
    func toggle(source: PromptBarPresentationSource) {
        toggleCallCount += 1
        toggleSources.append(source)
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
        let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.promptBar.rawValue: isFeatureOn])

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
        let (coordinator, _, registrar, _) = makeCoordinator(isFeatureOn: false, persistor: .optedIn)

        coordinator.start()

        XCTAssertEqual(registrar.registerCallCount, 0)
        XCTAssertNil(registrar.registeredShortcut)
    }

    func testWhenPreferencesAreAtTheirDefaultsThenNoShortcutIsRegistered() {
        let (coordinator, _, registrar, _) = makeCoordinator()

        coordinator.start()

        XCTAssertEqual(registrar.registerCallCount, 0)
        XCTAssertNil(registrar.registeredShortcut)
    }

    func testWhenStartedThenStoredShortcutIsRegistered() {
        let persistor = MockPromptBarPreferencesPersistor.optedIn
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])
        let (coordinator, _, registrar, _) = makeCoordinator(persistor: persistor)

        coordinator.start()

        XCTAssertEqual(registrar.registeredShortcut, persistor.keyboardShortcut)
    }

    func testWhenShortcutSettingIsOffThenNothingIsRegistered() {
        let persistor = MockPromptBarPreferencesPersistor.optedIn
        persistor.isKeyboardShortcutEnabled = false
        let (coordinator, _, registrar, _) = makeCoordinator(persistor: persistor)

        coordinator.start()

        XCTAssertNil(registrar.registeredShortcut)
        XCTAssertEqual(registrar.unregisterCallCount, 1)
    }

    func testWhenDuckAIIsUnavailableThenNothingIsRegistered() {
        let (coordinator, _, registrar, _) = makeCoordinator(persistor: .optedIn, isDuckAIAvailable: false)

        coordinator.start()

        XCTAssertNil(registrar.registeredShortcut)
    }

    func testWhenShortcutChangesThenItIsReRegistered() {
        let (coordinator, preferences, registrar, _) = makeCoordinator(persistor: .optedIn)
        coordinator.start()

        let updated = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .shift])
        preferences.keyboardShortcut = updated

        XCTAssertEqual(registrar.registeredShortcut, updated)
        XCTAssertEqual(registrar.registerCallCount, 2)
    }

    func testWhenShortcutIsEnabledAfterStartThenItIsRegistered() {
        let (coordinator, preferences, registrar, _) = makeCoordinator()
        coordinator.start()

        preferences.isKeyboardShortcutEnabled = true

        XCTAssertEqual(registrar.registeredShortcut, preferences.keyboardShortcut)
        XCTAssertEqual(registrar.registerCallCount, 1)
    }

    func testWhenShortcutIsDisabledAfterStartThenItIsUnregistered() {
        let (coordinator, preferences, registrar, _) = makeCoordinator(persistor: .optedIn)
        coordinator.start()

        preferences.isKeyboardShortcutEnabled = false

        XCTAssertNil(registrar.registeredShortcut)
        XCTAssertGreaterThanOrEqual(registrar.unregisterCallCount, 1)
    }

    func testWhenTogglingThenPresenterIsToggled() {
        let (coordinator, _, _, presenter) = makeCoordinator()

        coordinator.togglePromptBar(source: .menuBarIcon)

        XCTAssertEqual(presenter.toggleCallCount, 1)
        XCTAssertTrue(presenter.isVisible)
    }

    /// The source decides which visibility pixel is reported, so it has to survive the hop.
    func testWhenTogglingThenTheEntryPointIsPassedThrough() {
        let (coordinator, _, _, presenter) = makeCoordinator()

        coordinator.togglePromptBar(source: .menuBarIcon)
        coordinator.togglePromptBar(source: .keyboardShortcut)

        XCTAssertEqual(presenter.toggleSources, [.menuBarIcon, .keyboardShortcut])
    }

    func testWhenTheShortcutIsPressedThenItTogglesAsTheKeyboardShortcut() async {
        let (coordinator, _, registrar, presenter) = makeCoordinator(persistor: .optedIn)
        coordinator.start()

        registrar.simulateShortcutPressed()
        // The handler hops to the main actor; this queues behind it, so awaiting it means it ran.
        await Task { @MainActor in }.value

        XCTAssertEqual(presenter.toggleSources, [.keyboardShortcut])
    }

    func testWhenFeatureFlagIsOffThenTogglingDoesNothing() {
        let (coordinator, _, _, presenter) = makeCoordinator(isFeatureOn: false)

        coordinator.togglePromptBar(source: .keyboardShortcut)

        XCTAssertEqual(presenter.toggleCallCount, 0)
    }
}
