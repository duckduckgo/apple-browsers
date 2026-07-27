//
//  PromptBarCoordinator.swift
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

import AppKit
import Combine
import FeatureFlags
import PrivacyConfig

/// Owns the Prompt Bar's entry points: the global shortcut and the menu bar icon click.
///
/// Keeps the registered shortcut in step with the user's preference, and unregisters it when the
/// preference or Duck.ai itself is switched off.
@MainActor
final class PromptBarCoordinator {

    private let featureFlagger: FeatureFlagger
    private let preferences: PromptBarPreferences
    private let shortcutRegistrar: GlobalShortcutRegistering
    private let presenter: PromptBarPresenting

    private var shortcutCancellable: AnyCancellable?

    init(featureFlagger: FeatureFlagger,
         preferences: PromptBarPreferences,
         shortcutRegistrar: GlobalShortcutRegistering,
         presenter: PromptBarPresenting) {
        self.featureFlagger = featureFlagger
        self.preferences = preferences
        self.shortcutRegistrar = shortcutRegistrar
        self.presenter = presenter
    }

    /// Begins observing the shortcut preference. A no-op while the feature flag is off, so nothing
    /// is registered and the menu bar click stays inert.
    func start() {
        guard featureFlagger.isFeatureOn(.macosPromptBar) else { return }

        shortcutCancellable = preferences.effectiveKeyboardShortcutPublisher
            .sink { [weak self] shortcut in
                self?.applyShortcut(shortcut)
            }
    }

    /// Shows the bar, or hides it when it is already up. Called by the global shortcut and the
    /// menu bar icon.
    func togglePromptBar() {
        guard featureFlagger.isFeatureOn(.macosPromptBar) else { return }
        presenter.toggle()
    }

    private func applyShortcut(_ shortcut: PromptBarShortcut?) {
        guard let shortcut else {
            shortcutRegistrar.unregister()
            return
        }

        shortcutRegistrar.register(shortcut) { [weak self] in
            // The Carbon handler is not isolated, so hop to the main actor before touching UI.
            Task { @MainActor in
                self?.togglePromptBar()
            }
        }
    }
}
