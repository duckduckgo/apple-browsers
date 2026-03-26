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

@available(macOS 15.4, iOS 18.4, *)
public final class ScriptletManager: ScriptletProviding {

    private let configProvider: ScriptletConfigProviding
    private let fetcher: ScriptletFetching
    private let validator: ScriptletValidating
    private let store: ScriptletStoring

    @Published private var availabilities: [DuckDuckGoWebExtensionType: ScriptletAvailability] = [:]

    private var lastSuccessfulVersions: [DuckDuckGoWebExtensionType: String] = [:]
    private var currentFetchTasks: [DuckDuckGoWebExtensionType: Task<Void, Never>] = [:]
    private var activeExtensionTypes: Set<DuckDuckGoWebExtensionType> = []
    private var configCancellable: AnyCancellable?

    public init(
        configProvider: ScriptletConfigProviding,
        fetcher: ScriptletFetching,
        validator: ScriptletValidating,
        store: ScriptletStoring
    ) {
        self.configProvider = configProvider
        self.fetcher = fetcher
        self.validator = validator
        self.store = store
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

    public func isReady(for extensionType: DuckDuckGoWebExtensionType) -> Bool {
        scriptlets(for: extensionType) != nil
    }

    public func cacheDirectory(for extensionType: DuckDuckGoWebExtensionType) -> URL {
        store.cacheDirectory(for: extensionType)
    }

    // MARK: - Lifecycle

    public func start(for extensionType: DuckDuckGoWebExtensionType) async {
        Logger.webExtensions.debug("[Scriptlets] 🔄 Starting scriptlet manager for '\(extensionType.rawValue)'")
        activeExtensionTypes.insert(extensionType)
        loadCachedScriptlets(for: extensionType)
        subscribeToConfigUpdatesIfNeeded()
        await refreshIfNeeded(for: extensionType)
    }

    public func clearCachedScriptlets() {
        Logger.webExtensions.debug("[Scriptlets] 🗑️ Clearing all cached scriptlets and resetting state")
        store.clearAll()
        lastSuccessfulVersions.removeAll()
        availabilities.removeAll()
    }

    public func refreshIfNeeded(for extensionType: DuckDuckGoWebExtensionType) async {
        guard let manifest = configProvider.currentManifest(for: extensionType) else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No manifest available for '\(extensionType.rawValue)', skipping refresh")
            return
        }

        guard manifest.version != lastSuccessfulVersions[extensionType] else {
            Logger.webExtensions.debug("[Scriptlets] ✓ Already on latest version \(manifest.version) for '\(extensionType.rawValue)'")
            return
        }

        Logger.webExtensions.info("[Scriptlets] 🔄 Refreshing scriptlets for '\(extensionType.rawValue)': \(self.lastSuccessfulVersions[extensionType] ?? "none") → \(manifest.version)")
        await fetchAndUpdate(for: extensionType, manifest: manifest)
    }

    // MARK: - Private

    private func loadCachedScriptlets(for extensionType: DuckDuckGoWebExtensionType) {
        guard let cached = store.loadCached(for: extensionType),
              let currentManifest = configProvider.currentManifest(for: extensionType),
              cached.version == currentManifest.version else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No valid cache found for '\(extensionType.rawValue)'")
            return
        }

        Logger.webExtensions.info("[Scriptlets] ✅ Loaded \(cached.scriptlets.count) cached scriptlet(s) v\(cached.version) for '\(extensionType.rawValue)'")
        availabilities[extensionType] = .available(cached.scriptlets)
        lastSuccessfulVersions[extensionType] = cached.version
    }

    private func subscribeToConfigUpdatesIfNeeded() {
        guard configCancellable == nil else { return }

        configCancellable = configProvider.configUpdatedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }

                for extensionType in self.activeExtensionTypes {
                    self.currentFetchTasks[extensionType]?.cancel()

                    self.currentFetchTasks[extensionType] = Task { [weak self] in
                        await self?.refreshIfNeeded(for: extensionType)
                    }
                }
            }
    }

    private func fetchAndUpdate(for extensionType: DuckDuckGoWebExtensionType, manifest: ScriptletManifest) async {
        let existingScriptlets = scriptlets(for: extensionType)

        if let existing = existingScriptlets {
            Logger.webExtensions.debug("[Scriptlets] 🔄 Updating scriptlets for '\(extensionType.rawValue)' (keeping \(existing.count) existing during update)")
            availabilities[extensionType] = .updating(existing)
        } else {
            Logger.webExtensions.debug("[Scriptlets] 🔄 Fetching scriptlets for '\(extensionType.rawValue)' (no existing scriptlets)")
        }

        do {
            Logger.webExtensions.debug("[Scriptlets] 📥 Fetching \(manifest.scriptlets.count) scriptlet(s) for '\(extensionType.rawValue)'")
            let fetched = try await fetcher.fetch(manifest.scriptlets)

            Logger.webExtensions.debug("[Scriptlets] ✓ Validating \(fetched.count) fetched scriptlet(s) for '\(extensionType.rawValue)'")
            try validator.validate(fetched)

            Logger.webExtensions.debug("[Scriptlets] 💾 Saving \(fetched.count) validated scriptlet(s) for '\(extensionType.rawValue)'")
            let scriptlets = try store.save(fetched, version: manifest.version, for: extensionType)

            availabilities[extensionType] = .available(scriptlets)
            lastSuccessfulVersions[extensionType] = manifest.version
            Logger.webExtensions.info("[Scriptlets] ✅ Successfully updated to version \(manifest.version) with \(scriptlets.count) scriptlet(s) for '\(extensionType.rawValue)'")

        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to fetch/update scriptlets for '\(extensionType.rawValue)': \(error.localizedDescription)")
            if let existing = existingScriptlets {
                Logger.webExtensions.warning("[Scriptlets] ⚠️ Keeping \(existing.count) existing scriptlet(s) for '\(extensionType.rawValue)' after error")
                availabilities[extensionType] = .available(existing)
            } else {
                Logger.webExtensions.warning("[Scriptlets] ⚠️ No scriptlets available for '\(extensionType.rawValue)' after error")
                availabilities[extensionType] = .notAvailable
            }
        }
    }
}
