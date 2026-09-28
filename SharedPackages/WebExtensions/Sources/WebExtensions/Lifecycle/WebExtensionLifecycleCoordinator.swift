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
import ConcurrencyExtensions
import os.log

public typealias WebExtensionInitialLoadWaiter = @MainActor () async -> Void

/// Delays the first restored web navigation until Web Extension background content is ready. The gate
/// fails open after a bounded wait so an extension startup failure cannot block page loading.
public struct WebExtensionNavigationGate {
    public static let defaultInitialLoadTimeout: TimeInterval = 10

    private let initialLoadTimeout: TimeInterval

    public init(initialLoadTimeout: TimeInterval = Self.defaultInitialLoadTimeout) {
        self.initialLoadTimeout = initialLoadTimeout
    }

    public func waitIfNeeded(isMainFrame: Bool,
                             url: URL?,
                             initialLoadWaiter: WebExtensionInitialLoadWaiter?) async {
        guard isMainFrame,
              let scheme = url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let initialLoadWaiter else { return }

        // Timing out cancels only this waiter; the shared extension load must continue for other tabs.
        try? await withTimeout(initialLoadTimeout) {
            await initialLoadWaiter()
        }
    }
}

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

    /// The first launch / re-init operation while it is in progress. Tabs should await this before
    /// their first navigation so WebKit has loaded extension contexts before it decides which
    /// document-start scripts to inject.
    private var initialLoadAndSync: Task<Void, Never>?
    private var didEnqueueInitialLoadAndSync = false
    private var initialLoadAndSyncWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    var isInitialLoadAndSyncPending: Bool {
        initialLoadAndSync != nil
    }

    public var initialLoadWaiter: WebExtensionInitialLoadWaiter? {
        guard initialLoadAndSync != nil else { return nil }
        return { [weak self] in
            await self?.waitOnInitialLoadAndSync()
        }
    }

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
        let isInitialLoadAndSync = !didEnqueueInitialLoadAndSync
        didEnqueueInitialLoadAndSync = true
        let task = enqueue(clearPendingOnStart: { [weak self] in self?.pendingLoadAndSync = nil },
                           onCompletion: { [weak self] in
                               guard isInitialLoadAndSync else { return }
                               self?.initialLoadAndSyncDidComplete()
                           }) { [weak self] in
            guard let self else { return }
            await self.manager.loadInstalledExtensions()
            guard !Task.isCancelled else { return }
            await self.manager.syncEmbeddedExtensions(enabledTypes: self.enabledTypesProvider())
            guard !Task.isCancelled else { return }
            // Loading the context is not enough: WebKit must also restore its background listeners
            // before a restored page starts, otherwise document-start extension work can be missed.
            await self.manager.loadEmbeddedExtensionBackgroundContent()
            guard !Task.isCancelled else { return }
            self.reportConsistency()
        }
        pendingLoadAndSync = task
        if isInitialLoadAndSync {
            initialLoadAndSync = task
        }
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
        initialLoadAndSync?.cancel()
        tail?.cancel()
        tail = nil
        pendingSync = nil
        pendingLoadAndSync = nil
        initialLoadAndSyncDidComplete()
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
                         onCompletion: (@MainActor () -> Void)? = nil,
                         _ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let enqueuedGeneration = generation
        let task = Task { @MainActor [weak self] in
            defer { onCompletion?() }
            await previous?.value
            clearPendingOnStart?()
            guard !Task.isCancelled, self?.generation == enqueuedGeneration else { return }
            await body()
        }
        tail = task
        return task
    }

    private func initialLoadAndSyncDidComplete() {
        initialLoadAndSync = nil
        let waiters = Array(initialLoadAndSyncWaiters.values)
        initialLoadAndSyncWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitOnInitialLoadAndSync() async {
        guard initialLoadAndSync != nil else { return }
        let waiterID = UUID()
        // Do not await `initialLoadAndSync.value` directly: `withTimeout` uses structured
        // cancellation and would still wait for that non-cooperative task. This continuation lets
        // the timed-out navigation stop waiting without cancelling the shared initial load.
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard initialLoadAndSync != nil, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                initialLoadAndSyncWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.initialLoadAndSyncWaiters.removeValue(forKey: waiterID)?.resume()
            }
        }
    }
}
