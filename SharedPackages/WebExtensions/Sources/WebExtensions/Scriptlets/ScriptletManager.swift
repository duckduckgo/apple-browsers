//
//  ScriptletManager.swift
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

import Combine
import Foundation
import os.log

/// Manages the lifecycle of scriptlets for each web extension type.
///
/// `ScriptletManager` is responsible for fetching, validating, caching, and
/// publishing scriptlet availability. It maintains a per-extension-type state machine
/// with three states:
/// - `.notAvailable` — no scriptlets are cached or the config manifest was removed.
/// - `.available` — scriptlets are cached and ready for installation.
/// - `.updating` — a fetch is in progress; the previous scriptlets remain usable.
///
/// ## Lifecycle
///
/// Call ``start(for:)`` to activate an extension type. This loads any cached scriptlets
/// from disk for immediate availability, then fetches updates if the config manifest
/// version differs from the cached version. A shared subscription to privacy config
/// changes triggers re-fetches for all active types (debounced at 500ms).
///
/// Call ``stop(for:)`` to deactivate an extension type and cancel any in-flight fetch.
///
/// ## Validation
///
/// Fetched scriptlets are validated via ``ScriptletValidating`` (ECDSA signature check).
/// In production, validation failure blocks the update and preserves the previous state.
/// In non-production builds, validation failures are logged as warnings and the update proceeds.
@MainActor
@available(macOS 15.4, iOS 18.4, *)
public final class ScriptletManager: ScriptletProviding {

    private let configProvider: ScriptletConfigProviding
    private let fetcher: ScriptletFetching
    private let validator: ScriptletValidating
    private let store: ScriptletStoring
    private let pixelFiring: WebExtensionPixelFiring
    private let isProduction: Bool

    @Published private var availabilities: [DuckDuckGoWebExtensionType: ScriptletAvailability] = [:]

    private var currentFetchTasks: [DuckDuckGoWebExtensionType: Task<Void, Never>] = [:]
    private var activeExtensionTypes: Set<DuckDuckGoWebExtensionType> = []
    private var configCancellable: AnyCancellable?

    public init(
        configProvider: ScriptletConfigProviding,
        fetcher: ScriptletFetching,
        validator: ScriptletValidating,
        store: ScriptletStoring,
        pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
        isProduction: Bool = true
    ) {
        self.configProvider = configProvider
        self.fetcher = fetcher
        self.validator = validator
        self.store = store
        self.pixelFiring = pixelFiring
        self.isProduction = isProduction
    }

    // MARK: - ScriptletProviding

    public func availability(for extensionType: DuckDuckGoWebExtensionType) -> ScriptletAvailability {
        availabilities[extensionType] ?? .notAvailable
    }

    public func availabilityPublisher(for extensionType: DuckDuckGoWebExtensionType) -> AnyPublisher<ScriptletAvailability, Never> {
        $availabilities
            .map { $0[extensionType] ?? .notAvailable }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public func scriptlets(for extensionType: DuckDuckGoWebExtensionType) -> [Scriptlet]? {
        switch availability(for: extensionType) {
        case .notAvailable:
            return nil
        case .available(let scriptlets), .updating(let scriptlets):
            return scriptlets
        }
    }

    public func scriptletVersion(for extensionType: DuckDuckGoWebExtensionType) -> String? {
        store.cachedVersion(for: extensionType)
    }

    public func isReady(for extensionType: DuckDuckGoWebExtensionType) -> Bool {
        scriptlets(for: extensionType) != nil
    }

    // MARK: - Lifecycle

    public func start(for extensionType: DuckDuckGoWebExtensionType) async {
        activeExtensionTypes.insert(extensionType)
        loadCachedScriptlets(for: extensionType)
        await refreshIfNeeded(for: extensionType)
        subscribeToConfigUpdatesIfNeeded()
    }

    public func stop(for extensionType: DuckDuckGoWebExtensionType) {
        activeExtensionTypes.remove(extensionType)
        currentFetchTasks[extensionType]?.cancel()
        currentFetchTasks.removeValue(forKey: extensionType)
    }

    public func clearCachedScriptlets() {
        Logger.webExtensions.info("[Scriptlets] Clearing all cached scriptlets")
        store.clearAll()
        availabilities.removeAll()
    }

    public func refreshIfNeeded(for extensionType: DuckDuckGoWebExtensionType) async {
        guard let manifest = configProvider.currentManifest(for: extensionType) else {
            clearCachedScriptletsIfNeeded(for: extensionType)
            return
        }

        let cachedVersion = store.cachedVersion(for: extensionType)
        guard manifest.version != cachedVersion else { return }

        Logger.webExtensions.info("[Scriptlets] Refreshing '\(extensionType.rawValue)': \(cachedVersion ?? "none") -> \(manifest.version)")
        await fetchAndUpdate(for: extensionType, manifest: manifest)
    }

    // MARK: - Private

    private func clearCachedScriptletsIfNeeded(for extensionType: DuckDuckGoWebExtensionType) {
        guard availabilities[extensionType] != nil,
              availabilities[extensionType] != .notAvailable else { return }
        store.clearCache(for: extensionType)
        availabilities[extensionType] = .notAvailable
        Logger.webExtensions.info("[Scriptlets] Cleared cached scriptlets for '\(extensionType.rawValue)' (manifest removed from config)")
    }

    private func loadCachedScriptlets(for extensionType: DuckDuckGoWebExtensionType) {
        guard let cached = store.loadCached(for: extensionType),
              let currentManifest = configProvider.currentManifest(for: extensionType),
              cached.version == currentManifest.version else {
            return
        }

        Logger.webExtensions.info("[Scriptlets] Loaded \(cached.scriptlets.count) cached scriptlet(s) v\(cached.version) for '\(extensionType.rawValue)'")
        availabilities[extensionType] = .available(cached.scriptlets)
    }

    private func subscribeToConfigUpdatesIfNeeded() {
        guard configCancellable == nil else { return }

        configCancellable = configProvider.configUpdatedPublisher
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshAllActiveExtensions()
                }
            }
    }

    private func refreshAllActiveExtensions() {
        for extensionType in activeExtensionTypes {
            currentFetchTasks[extensionType]?.cancel()

            currentFetchTasks[extensionType] = Task { [weak self] in
                await self?.refreshIfNeeded(for: extensionType)
            }
        }
    }

    private func fetchAndUpdate(for extensionType: DuckDuckGoWebExtensionType, manifest: ScriptletManifest) async {
        let existingScriptlets = scriptlets(for: extensionType)

        if let existing = existingScriptlets {
            availabilities[extensionType] = .updating(existing)
        }

        do {
            let fetched = try await fetcher.fetch(manifest.scriptlets)

            do {
                try validator.validate(fetched)
                Logger.webExtensions.info("[Scriptlets] Signature validation passed for '\(extensionType.rawValue)' (\(fetched.count) scriptlet(s))")
            } catch {
                if isProduction {
                    pixelFiring.fire(.scriptletValidationError(type: extensionType, error: error))
                    throw error
                }
                Logger.webExtensions.warning("[Scriptlets] Validation failed for '\(extensionType.rawValue)' (non-production, continuing): \(error)")
            }

            let scriptlets = try store.save(fetched, version: manifest.version, for: extensionType)

            availabilities[extensionType] = .available(scriptlets)
            pixelFiring.fire(.scriptletFetchSuccess(type: extensionType, version: manifest.version, count: scriptlets.count))
            Logger.webExtensions.info("[Scriptlets] Updated to v\(manifest.version) with \(scriptlets.count) scriptlet(s) for '\(extensionType.rawValue)'")
        } catch {
            Logger.webExtensions.error("[Scriptlets] Failed to fetch/update scriptlets for '\(extensionType.rawValue)': \(error)")
            pixelFiring.fire(.scriptletFetchError(type: extensionType, error: error))
            if let existing = existingScriptlets {
                availabilities[extensionType] = .available(existing)
            } else {
                availabilities[extensionType] = .notAvailable
            }
        }
    }
}
