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
/// When the feature flag is disabled, this handler automatically uninstalls all extensions
/// and calls the provided callback for additional cleanup.
///
/// Usage:
/// ```swift
/// let publisher = featureFlagPublisher
///     .filter { $0.0 == .webExtensions }
///     .map { $0.1 }
///     .eraseToAnyPublisher()
///
/// handler = WebExtensionFeatureFlagHandler(
///     webExtensionManager: manager,
///     featureFlagPublisher: publisher,
///     onFeatureFlagDisabled: { [weak self] in
///         self?.cleanupReferences()
///     }
/// )
/// ```
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionFeatureFlagHandler {

    private var cancellable: AnyCancellable?
    private weak var webExtensionManager: WebExtensionManaging?
    private let onFeatureFlagDisabled: () -> Void

    /// Creates a feature flag handler.
    /// - Parameters:
    ///   - webExtensionManager: The web extension manager to call uninstallAllExtensions on.
    ///   - featureFlagPublisher: A publisher that emits `true` when the feature is enabled and `false` when disabled.
    ///                          This should be pre-filtered for the webExtensions flag.
    ///   - onFeatureFlagDisabled: Callback invoked when the feature flag is disabled, after uninstalling extensions.
    public init(webExtensionManager: WebExtensionManaging?,
                featureFlagPublisher: AnyPublisher<Bool, Never>?,
                onFeatureFlagDisabled: @escaping () -> Void) {
        self.webExtensionManager = webExtensionManager
        self.onFeatureFlagDisabled = onFeatureFlagDisabled
        subscribeToFeatureFlagChanges(featureFlagPublisher)
    }

    private func subscribeToFeatureFlagChanges(_ publisher: AnyPublisher<Bool, Never>?) {
        guard let publisher else { return }

        cancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled {
                    self?.handleFeatureFlagDisabled()
                }
            }
    }

    private func handleFeatureFlagDisabled() {
        webExtensionManager?.uninstallAllExtensions()
        onFeatureFlagDisabled()
    }
}
