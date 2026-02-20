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
///
/// When the embedded extension feature flag is disabled, only embedded extensions are uninstalled.
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
///     webExtensionManager: manager,
///     featureFlagPublisher: webExtensionsPublisher,
///     embeddedExtensionFlagPublisher: embeddedPublisher,
///     onFeatureFlagDisabled: { [weak self] in
///         self?.cleanupReferences()
///     }
/// )
/// ```
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionFeatureFlagHandler {

    private var webExtensionsCancellable: AnyCancellable?
    private var embeddedExtensionCancellable: AnyCancellable?
    private weak var webExtensionManager: WebExtensionManaging?
    private let onFeatureFlagDisabled: () -> Void

    /// Creates a feature flag handler.
    /// - Parameters:
    ///   - webExtensionManager: The web extension manager to manage extensions.
    ///   - featureFlagPublisher: A publisher that emits `true` when the main webExtensions feature is enabled.
    ///   - embeddedExtensionFlagPublisher: A publisher that emits `true` when the embedded extension feature is enabled.
    ///   - onFeatureFlagDisabled: Callback invoked when the main feature flag is disabled, after uninstalling extensions.
    public init(webExtensionManager: WebExtensionManaging?,
                featureFlagPublisher: AnyPublisher<Bool, Never>?,
                embeddedExtensionFlagPublisher: AnyPublisher<Bool, Never>? = nil,
                onFeatureFlagDisabled: @escaping () -> Void) {
        self.webExtensionManager = webExtensionManager
        self.onFeatureFlagDisabled = onFeatureFlagDisabled
        subscribeToWebExtensionsFlagChanges(featureFlagPublisher)
        subscribeToEmbeddedExtensionFlagChanges(embeddedExtensionFlagPublisher)
    }

    private func subscribeToWebExtensionsFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        webExtensionsCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled {
                    self?.handleWebExtensionsFlagDisabled()
                }
            }
    }

    private func subscribeToEmbeddedExtensionFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        embeddedExtensionCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled {
                    self?.handleEmbeddedExtensionFlagDisabled()
                }
            }
    }

    private func handleWebExtensionsFlagDisabled() {
        webExtensionManager?.uninstallAllExtensions()
        onFeatureFlagDisabled()
    }

    private func handleEmbeddedExtensionFlagDisabled() {
        webExtensionManager?.uninstallEmbeddedExtension(type: .embedded)
    }
}
