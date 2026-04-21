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
import Common
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
/// When the ad blocking extension feature flag is disabled, the ad blocking extension is uninstalled.
/// When enabled, it calls the provided callback for installation.
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionFeatureFlagHandler {

    private var webExtensionsCancellable: AnyCancellable?
    private var embeddedExtensionCancellable: AnyCancellable?
    private var adBlockingExtensionCancellable: AnyCancellable?
    private let webExtensionManagerProvider: () -> WebExtensionManaging?
    private let onFeatureFlagEnabled: (() async -> Void)?
    private let onFeatureFlagDisabled: () -> Void
    private let onEmbeddedExtensionFlagEnabled: (() async -> Void)?
    private let onAdBlockingExtensionFlagEnabled: (() async -> Void)?

    private var isWebExtensionsFlagEnabled = false
    private var isEmbeddedExtensionFlagEnabled = false
    private var isAdBlockingExtensionFlagEnabled = false
    private var webExtensionsEnableTask: Task<Void, Never>?
    private var embeddedExtensionEnableTask: Task<Void, Never>?
    private var adBlockingExtensionEnableTask: Task<Void, Never>?

    /// Creates a feature flag handler.
    /// - Parameters:
    ///   - webExtensionManagerProvider: A closure that returns the current web extension manager. Called when uninstalling extensions.
    ///   - featureFlagPublisher: A publisher that emits `true` when the main webExtensions feature is enabled.
    ///   - embeddedExtensionFlagPublisher: A publisher that emits `true` when the embedded extension feature is enabled.
    ///   - adBlockingExtensionFlagPublisher: A publisher that emits `true` when the ad blocking extension feature is enabled.
    ///   - onFeatureFlagEnabled: Callback invoked when the main feature flag is enabled. Use this to load/initialize extensions.
    ///   - onFeatureFlagDisabled: Callback invoked when the main feature flag is disabled, after uninstalling extensions.
    ///   - onEmbeddedExtensionFlagEnabled: Callback invoked when the embedded extension feature flag is enabled. Use this to sync/install embedded extensions.
    ///   - onAdBlockingExtensionFlagEnabled: Callback invoked when the ad blocking extension feature flag is enabled. Use this to sync/install the ad blocking extension.
    public init(webExtensionManagerProvider: @escaping () -> WebExtensionManaging?,
                featureFlagPublisher: AnyPublisher<Bool, Never>?,
                embeddedExtensionFlagPublisher: AnyPublisher<Bool, Never>? = nil,
                adBlockingExtensionFlagPublisher: AnyPublisher<Bool, Never>? = nil,
                onFeatureFlagEnabled: (() async -> Void)? = nil,
                onFeatureFlagDisabled: @escaping () -> Void,
                onEmbeddedExtensionFlagEnabled: (() async -> Void)? = nil,
                onAdBlockingExtensionFlagEnabled: (() async -> Void)? = nil) {
        self.webExtensionManagerProvider = webExtensionManagerProvider
        self.onFeatureFlagEnabled = onFeatureFlagEnabled
        self.onFeatureFlagDisabled = onFeatureFlagDisabled
        self.onEmbeddedExtensionFlagEnabled = onEmbeddedExtensionFlagEnabled
        self.onAdBlockingExtensionFlagEnabled = onAdBlockingExtensionFlagEnabled
        subscribeToWebExtensionsFlagChanges(featureFlagPublisher)
        subscribeToEmbeddedExtensionFlagChanges(embeddedExtensionFlagPublisher)
        subscribeToAdBlockingExtensionFlagChanges(adBlockingExtensionFlagPublisher)
    }

    private func subscribeToWebExtensionsFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        webExtensionsCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Task { @MainActor in
                    if enabled {
                        self?.handleWebExtensionsFlagEnabled()
                    } else {
                        self?.handleWebExtensionsFlagDisabled()
                    }
                }
            }
    }

    private func subscribeToEmbeddedExtensionFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        embeddedExtensionCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Task { @MainActor in
                    if enabled {
                        self?.handleEmbeddedExtensionFlagEnabled()
                    } else {
                        self?.handleEmbeddedExtensionFlagDisabled()
                    }
                }
            }
    }

    @MainActor
    private func handleWebExtensionsFlagEnabled() {
        guard let onFeatureFlagEnabled else { return }
        isWebExtensionsFlagEnabled = true
        webExtensionsEnableTask?.cancel()
        webExtensionsEnableTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.isWebExtensionsFlagEnabled == true else { return }
            await onFeatureFlagEnabled()
        }
    }

    @MainActor
    private func handleWebExtensionsFlagDisabled() {
        isWebExtensionsFlagEnabled = false
        webExtensionsEnableTask?.cancel()
        webExtensionsEnableTask = nil
        webExtensionManagerProvider()?.uninstallAllExtensions()
        onFeatureFlagDisabled()
    }

    @MainActor
    private func handleEmbeddedExtensionFlagEnabled() {
        guard let onEmbeddedExtensionFlagEnabled else { return }
        isEmbeddedExtensionFlagEnabled = true
        embeddedExtensionEnableTask?.cancel()
        embeddedExtensionEnableTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.isEmbeddedExtensionFlagEnabled == true else { return }
            await onEmbeddedExtensionFlagEnabled()
        }
    }

    @MainActor
    private func handleEmbeddedExtensionFlagDisabled() {
        isEmbeddedExtensionFlagEnabled = false
        embeddedExtensionEnableTask?.cancel()
        embeddedExtensionEnableTask = nil
        webExtensionManagerProvider()?.uninstallEmbeddedExtension(type: .embedded)
    }

    private func subscribeToAdBlockingExtensionFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        adBlockingExtensionCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Task { @MainActor in
                    if enabled {
                        self?.handleAdBlockingExtensionFlagEnabled()
                    } else {
                        self?.handleAdBlockingExtensionFlagDisabled()
                    }
                }
            }
    }

    @MainActor
    private func handleAdBlockingExtensionFlagEnabled() {
        guard let onAdBlockingExtensionFlagEnabled else { return }
        isAdBlockingExtensionFlagEnabled = true
        adBlockingExtensionEnableTask?.cancel()
        adBlockingExtensionEnableTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.isAdBlockingExtensionFlagEnabled == true else { return }
            await onAdBlockingExtensionFlagEnabled()
        }
    }

    @MainActor
    private func handleAdBlockingExtensionFlagDisabled() {
        isAdBlockingExtensionFlagEnabled = false
        adBlockingExtensionEnableTask?.cancel()
        adBlockingExtensionEnableTask = nil
        webExtensionManagerProvider()?.uninstallEmbeddedExtension(type: .adBlockingExtension)
    }
}
