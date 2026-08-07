//
//  WebExtensionLifecycleCoordinator.swift
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

import Foundation
import os.log

/// Serializes every web-extension lifecycle operation (load, sync, reload, unload) through a single
/// FIFO async chain so exactly one runs at a time. This prevents `WebExtensionManager`'s
/// orphan-cleanup (in `loadInstalledExtensions()`) from running while an embedded install
/// (`installEmbeddedExtension`) is mid-flight, which would otherwise delete the in-flight extension's
/// files before its registry record is written and surface later as `extensionNotFound`.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class WebExtensionLifecycleCoordinator {

    private let manager: WebExtensionManaging
    private let enabledTypesProvider: @MainActor () -> Set<DuckDuckGoWebExtensionType>
    private let pixelFiring: WebExtensionPixelFiring

    /// Tail of the serial chain; each enqueued op awaits the previous one.
    private var tail: Task<Void, Never>?

    /// The most recently enqueued but not-yet-started coalescing op, reused to collapse redundant
    /// requests. Cleared when the op begins executing so a later request (capturing newer state)
    /// can queue a fresh op.
    private var pendingSync: Task<Void, Never>?
    private var pendingLoadAndSync: Task<Void, Never>?

    /// Bumped by `cancelAll()`; every queued op captures the generation at enqueue time and bails if
    /// it changed, so a single cancel stops the whole chain (not just the tail).
    private var generation = 0

    public init(manager: WebExtensionManaging,
                enabledTypesProvider: @escaping @MainActor () -> Set<DuckDuckGoWebExtensionType>,
                pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring()) {
        self.manager = manager
        self.enabledTypesProvider = enabledTypesProvider
        self.pixelFiring = pixelFiring
    }

    /// Full load followed by embedded sync, as one indivisible chain entry. Launch / re-init.
    @discardableResult
    public func loadAndSync() -> Task<Void, Never> {
        if let pendingLoadAndSync { return pendingLoadAndSync }
        let task = enqueue(clearPendingOnStart: { [weak self] in self?.pendingLoadAndSync = nil }) { [weak self] in
            guard let self else { return }
            await self.manager.loadInstalledExtensions()
            guard !Task.isCancelled else { return }
            await self.manager.syncEmbeddedExtensions(enabledTypes: self.enabledTypesProvider())
            guard !Task.isCancelled else { return }
            self.reportConsistency()
        }
        pendingLoadAndSync = task
        return task
    }

    /// Embedded sync only. Appearance / YouTube / feature-flag triggers.
    @discardableResult
    public func sync() -> Task<Void, Never> {
        if let pendingSync { return pendingSync }
        let task = enqueue(clearPendingOnStart: { [weak self] in self?.pendingSync = nil }) { [weak self] in
            guard let self else { return }
            await self.manager.syncEmbeddedExtensions(enabledTypes: self.enabledTypesProvider())
            guard !Task.isCancelled else { return }
            self.reportConsistency()
        }
        pendingSync = task
        return task
    }

    /// Full load without sync. Fire data-clearing fallback when lightweight reload is disabled.
    @discardableResult
    public func load() -> Task<Void, Never> {
        enqueue { [weak self] in
            guard let self else { return }
            await self.manager.loadInstalledExtensions()
            guard !Task.isCancelled else { return }
            self.reportConsistency()
        }
    }

    /// Lightweight reload (reuses parsed extensions). Fire data-clearing.
    @discardableResult
    public func reload() -> Task<Void, Never> {
        enqueue { [weak self] in
            guard let self else { return }
            await self.manager.reloadInstalledExtensions()
            guard !Task.isCancelled else { return }
            self.reportConsistency()
        }
    }

    /// Unload all extensions from memory. Fire data-clearing (before cache clear).
    @discardableResult
    public func unload() -> Task<Void, Never> {
        enqueue { [weak self] in
            self?.manager.unloadAllExtensions()
        }
    }

    /// Runs a standalone consistency check on the serial chain. For the debug menu, tests, and a
    /// possible future periodic backstop.
    @discardableResult
    public func verify() -> Task<Void, Never> {
        enqueue { [weak self] in self?.reportConsistency() }
    }

    /// Cancels the in-flight tail and prevents every queued operation from running. Used on
    /// feature-flag disable / teardown.
    public func cancelAll() {
        generation += 1
        tail?.cancel()
        tail = nil
        pendingSync = nil
        pendingLoadAndSync = nil
    }

    /// Compares enabled embedded types against loaded ones and fires pixels. Runs on the chain.
    private func reportConsistency() {
        let expected = enabledTypesProvider()
        let loaded = manager.loadedEmbeddedExtensionTypes

        Logger.webExtensions.debug("🩺 Web extension state check — expected: [\(expected.map(\.shortLabel).sorted().joined(separator: ", "), privacy: .public)], loaded: [\(loaded.map(\.shortLabel).sorted().joined(separator: ", "), privacy: .public)] — firing web_extension_state_checked")
        pixelFiring.fire(.stateChecked)

        for type in expected.subtracting(loaded) {
            Logger.webExtensions.error("❌ Expected web extension not loaded: \(type.shortLabel, privacy: .public) — firing web_extension_*_not_loaded")
            pixelFiring.fire(.expectedExtensionNotLoaded(type: type))
        }

        if expected.contains(.adBlockingExtension), manager.adBlockingScriptletsVersion() == nil {
            let extensionLoaded = loaded.contains(.adBlockingExtension)
            Logger.webExtensions.error("❌ Ad-blocking scriptlets not fetched (extensionLoaded: \(extensionLoaded, privacy: .public)) — firing web_extension_ad_blocking_scriptlets_not_fetched")
            pixelFiring.fire(.adBlockingScriptletsNotFetched(extensionLoaded: extensionLoaded))
        }
    }

    // MARK: - Serial chain

    @discardableResult
    private func enqueue(clearPendingOnStart: (@MainActor () -> Void)? = nil,
                         _ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let enqueuedGeneration = generation
        let task = Task { @MainActor [weak self] in
            await previous?.value
            clearPendingOnStart?()
            guard !Task.isCancelled, self?.generation == enqueuedGeneration else { return }
            await body()
        }
        tail = task
        return task
    }
}
