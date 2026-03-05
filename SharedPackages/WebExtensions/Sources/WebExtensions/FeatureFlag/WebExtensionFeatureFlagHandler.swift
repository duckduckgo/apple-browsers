//
//  WebExtensionFeatureFlagHandler.swift
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

import Combine
import Foundation

/// Handles feature flag changes for web extensions.
///
/// When the main web extensions feature flag is disabled, this handler automatically
/// uninstalls all extensions and calls the provided callback for cleanup.
/// When enabled, it calls the provided callback for initialization.
///
/// When the embedded extension feature flag is disabled, only embedded extensions are uninstalled.
/// When enabled, it calls the provided callback for installation.
///
/// Usage:
/// ```swift
/// let webExtensionsPublisher = featureFlagPublisher
///     .filter { $0.0 == .webExtensions }
///     .map { $0.1 }
///     .eraseToAnyPublisher()
///
/// let embeddedPublisher = featureFlagPublisher
///     .filter { $0.0 == .embeddedExtension }
///     .map { $0.1 }
///     .eraseToAnyPublisher()
///
/// handler = WebExtensionFeatureFlagHandler(
///     webExtensionManagerProvider: { [weak self] in self?.webExtensionManager },
///     featureFlagPublisher: webExtensionsPublisher,
///     embeddedExtensionFlagPublisher: embeddedPublisher,
///     onFeatureFlagEnabled: { [weak self] in
///         await self?.initializeWebExtensions()
///     },
///     onFeatureFlagDisabled: { [weak self] in
///         self?.cleanupReferences()
///     },
///     onEmbeddedExtensionFlagEnabled: { [weak self] in
///         await self?.syncEmbeddedExtensions()
///     }
/// )
/// ```
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionFeatureFlagHandler {

    private var webExtensionsCancellable: AnyCancellable?
    private var embeddedExtensionCancellable: AnyCancellable?
    private let webExtensionManagerProvider: () -> WebExtensionManaging?
    private let onFeatureFlagEnabled: (() async -> Void)?
    private let onFeatureFlagDisabled: () -> Void
    private let onEmbeddedExtensionFlagEnabled: (() async -> Void)?

    private var isWebExtensionsFlagEnabled = false
    private var isEmbeddedExtensionFlagEnabled = false
    private var webExtensionsEnableTask: Task<Void, Never>?
    private var embeddedExtensionEnableTask: Task<Void, Never>?

    /// Creates a feature flag handler.
    /// - Parameters:
    ///   - webExtensionManagerProvider: A closure that returns the current web extension manager. Called when uninstalling extensions.
    ///   - featureFlagPublisher: A publisher that emits `true` when the main webExtensions feature is enabled.
    ///   - embeddedExtensionFlagPublisher: A publisher that emits `true` when the embedded extension feature is enabled.
    ///   - onFeatureFlagEnabled: Callback invoked when the main feature flag is enabled. Use this to load/initialize extensions.
    ///   - onFeatureFlagDisabled: Callback invoked when the main feature flag is disabled, after uninstalling extensions.
    ///   - onEmbeddedExtensionFlagEnabled: Callback invoked when the embedded extension feature flag is enabled. Use this to sync/install embedded extensions.
    public init(webExtensionManagerProvider: @escaping () -> WebExtensionManaging?,
                featureFlagPublisher: AnyPublisher<Bool, Never>?,
                embeddedExtensionFlagPublisher: AnyPublisher<Bool, Never>? = nil,
                onFeatureFlagEnabled: (() async -> Void)? = nil,
                onFeatureFlagDisabled: @escaping () -> Void,
                onEmbeddedExtensionFlagEnabled: (() async -> Void)? = nil) {
        self.webExtensionManagerProvider = webExtensionManagerProvider
        self.onFeatureFlagEnabled = onFeatureFlagEnabled
        self.onFeatureFlagDisabled = onFeatureFlagDisabled
        self.onEmbeddedExtensionFlagEnabled = onEmbeddedExtensionFlagEnabled
        subscribeToWebExtensionsFlagChanges(featureFlagPublisher)
        subscribeToEmbeddedExtensionFlagChanges(embeddedExtensionFlagPublisher)
    }

    private func subscribeToWebExtensionsFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        webExtensionsCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.handleWebExtensionsFlagEnabled()
                } else {
                    self?.handleWebExtensionsFlagDisabled()
                }
            }
    }

    private func subscribeToEmbeddedExtensionFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        embeddedExtensionCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.handleEmbeddedExtensionFlagEnabled()
                } else {
                    self?.handleEmbeddedExtensionFlagDisabled()
                }
            }
    }

    private func handleWebExtensionsFlagEnabled() {
        guard let onFeatureFlagEnabled else { return }
        isWebExtensionsFlagEnabled = true
        webExtensionsEnableTask?.cancel()
        webExtensionsEnableTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.isWebExtensionsFlagEnabled == true else { return }
            await onFeatureFlagEnabled()
        }
    }

    private func handleWebExtensionsFlagDisabled() {
        isWebExtensionsFlagEnabled = false
        webExtensionsEnableTask?.cancel()
        webExtensionsEnableTask = nil
        webExtensionManagerProvider()?.uninstallAllExtensions()
        onFeatureFlagDisabled()
    }

    private func handleEmbeddedExtensionFlagEnabled() {
        guard let onEmbeddedExtensionFlagEnabled else { return }
        isEmbeddedExtensionFlagEnabled = true
        embeddedExtensionEnableTask?.cancel()
        embeddedExtensionEnableTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.isEmbeddedExtensionFlagEnabled == true else { return }
            await onEmbeddedExtensionFlagEnabled()
        }
    }

    private func handleEmbeddedExtensionFlagDisabled() {
        isEmbeddedExtensionFlagEnabled = false
        embeddedExtensionEnableTask?.cancel()
        embeddedExtensionEnableTask = nil
        webExtensionManagerProvider()?.uninstallEmbeddedExtension(type: .embedded)
    }
}
