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

    private let extensionType: DuckDuckGoWebExtensionType
    private let configProvider: ScriptletConfigProviding
    private let fetcher: ScriptletFetching
    private let validator: ScriptletValidating
    private let store: ScriptletStoring

    @Published public private(set) var availability: ScriptletAvailability = .notAvailable

    private var lastSuccessfulVersion: String?
    private var currentFetchTask: Task<Void, Never>?
    private var configCancellable: AnyCancellable?

    public init(
        extensionType: DuckDuckGoWebExtensionType,
        configProvider: ScriptletConfigProviding,
        fetcher: ScriptletFetching,
        validator: ScriptletValidating,
        store: ScriptletStoring
    ) {
        self.extensionType = extensionType
        self.configProvider = configProvider
        self.fetcher = fetcher
        self.validator = validator
        self.store = store
    }

    public var availabilityPublisher: AnyPublisher<ScriptletAvailability, Never> {
        $availability.eraseToAnyPublisher()
    }

    public var scriptlets: [Scriptlet]? {
        switch availability {
        case .notAvailable:
            return nil
        case .available(let scriptlets), .updating(let scriptlets):
            return scriptlets
        }
    }

    public var isReady: Bool {
        scriptlets != nil
    }

    public func start() async {
        Logger.webExtensions.debug("[Scriptlets] 🔄 Starting scriptlet manager")
        loadCachedScriptlets()
        subscribeToConfigUpdates()
        await refreshIfNeeded()
    }

    public func refreshIfNeeded() async {
        guard let manifest = configProvider.currentManifest else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No manifest available, skipping refresh")
            return
        }

        guard manifest.version != lastSuccessfulVersion else {
            Logger.webExtensions.debug("[Scriptlets] ✓ Already on latest version \(manifest.version)")
            return
        }

        Logger.webExtensions.info("[Scriptlets] 🔄 Refreshing scriptlets: \(self.lastSuccessfulVersion ?? "none") → \(manifest.version)")
        await fetchAndUpdate(manifest: manifest)
    }

    private func loadCachedScriptlets() {
        guard let cached = store.loadCached(for: extensionType),
              let currentManifest = configProvider.currentManifest,
              cached.version == currentManifest.version else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No valid cache found for '\(self.extensionType.rawValue)'")
            return
        }

        Logger.webExtensions.info("[Scriptlets] ✅ Loaded \(cached.scriptlets.count) cached scriptlet(s) v\(cached.version) for '\(self.extensionType.rawValue)'")
        availability = .available(cached.scriptlets)
        lastSuccessfulVersion = cached.version
    }

    private func subscribeToConfigUpdates() {
        configCancellable = configProvider.configUpdatedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }

                self.currentFetchTask?.cancel()

                self.currentFetchTask = Task { [weak self] in
                    await self?.refreshIfNeeded()
                }
            }
    }

    private func fetchAndUpdate(manifest: ScriptletManifest) async {
        let existingScriptlets = scriptlets

        if let existing = existingScriptlets {
            Logger.webExtensions.debug("[Scriptlets] 🔄 Updating scriptlets (keeping \(existing.count) existing during update)")
            availability = .updating(existing)
        } else {
            Logger.webExtensions.debug("[Scriptlets] 🔄 Fetching scriptlets (no existing scriptlets)")
        }

        do {
            Logger.webExtensions.debug("[Scriptlets] 📥 Fetching \(manifest.scriptlets.count) scriptlet(s)")
            let fetched = try await fetcher.fetch(manifest.scriptlets)

            Logger.webExtensions.debug("[Scriptlets] ✓ Validating \(fetched.count) fetched scriptlet(s)")
            let validated = try validator.validate(fetched)

            let targetPaths = Dictionary(uniqueKeysWithValues: validated.map { ($0.name, $0.name) })

            Logger.webExtensions.debug("[Scriptlets] 💾 Saving \(validated.count) validated scriptlet(s)")
            try store.save(validated, version: manifest.version, for: extensionType, withTargetPaths: targetPaths)

            availability = .available(validated)
            lastSuccessfulVersion = manifest.version
            Logger.webExtensions.info("[Scriptlets] ✅ Successfully updated to version \(manifest.version) with \(validated.count) scriptlet(s) for '\(self.extensionType.rawValue)'")

        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to fetch/update scriptlets for '\(self.extensionType.rawValue)': \(error.localizedDescription)")
            if let existing = existingScriptlets {
                Logger.webExtensions.warning("[Scriptlets] ⚠️ Keeping \(existing.count) existing scriptlet(s) after error")
                availability = .available(existing)
            } else {
                Logger.webExtensions.warning("[Scriptlets] ⚠️ No scriptlets available after error")
                availability = .notAvailable
            }
        }
    }
}
