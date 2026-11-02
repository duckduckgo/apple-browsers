//
//  ChromeWebStoreUpdateCoordinator.swift
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

/// Owns discovery for one store. Installation state is read on MainActor; checks run on this actor.
@available(macOS 15.4, iOS 18.4, *)
actor ChromeWebStoreUpdateCoordinator {
    struct Version: Sendable {
        let installedVersion: String
        let reportedVersion: String
    }

    typealias Check = @Sendable (String, String) async -> ChromeWebStoreUpdateChecker.CheckResult
    typealias IdentifiersProvider = @MainActor @Sendable () async -> [String]?
    typealias VersionProvider = @MainActor @Sendable (String) async -> Version?

    static let defaultCheckInterval: TimeInterval = 2 * 60 * 60

    private let interval: TimeInterval
    private var installedIdentifiers: IdentifiersProvider?
    private var version: VersionProvider?
    private var check: Check?
    private var schedulerTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?
    private var retryNotBefore: Date?
    private var lastCheckedIdentifier: String?
    private var isStopped = false

    init(interval: TimeInterval = ChromeWebStoreUpdateCoordinator.defaultCheckInterval,
         installedIdentifiers: @escaping IdentifiersProvider,
         version: @escaping VersionProvider,
         check: @escaping Check) {
        self.interval = interval
        self.installedIdentifiers = installedIdentifiers
        self.version = version
        self.check = check
    }

    func start() {
        guard !isStopped, schedulerTask == nil else { return }
        let interval = interval
        Logger.webExtensions.info("Extension update discovery: started (interval \(interval, privacy: .public)s)")
        schedulerTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                let batch = await self?.startBatch()
                await batch?.value
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    /// A terminal stop also prevents a delayed startup task from restarting discovery.
    func stop() {
        isStopped = true
        schedulerTask?.cancel()
        batchTask?.cancel()
        schedulerTask = nil
        installedIdentifiers = nil
        version = nil
        check = nil
    }

    func checkForUpdatesNow() async {
        guard !Task.isCancelled else { return }
        let batch = startBatch()
        await batch?.value
    }

    private func startBatch() -> Task<Void, Never>? {
        guard !isStopped else { return nil }
        if let batchTask { return batchTask }
        if let retryNotBefore, retryNotBefore > Date() {
            Logger.webExtensions.info("Extension update discovery: deferred until server retry deadline=\(retryNotBefore, privacy: .public)")
            return nil
        }
        // Reserve the batch before any provider await can let another caller enter the actor.
        let batch = Task<Void, Never>(priority: .utility) { [weak self] in
            await self?.runBatch()
        }
        batchTask = batch
        return batch
    }

    private func runBatch() async {
        defer { batchTask = nil }
        guard !isStopped, !Task.isCancelled, let installedIdentifiers else { return }
        let identifiers = await installedIdentifiers()
        guard !isStopped, !Task.isCancelled else { return }
        guard let identifiers else {
            stop()
            return
        }
        let candidates = orderedIdentifiers(identifiers)
        Logger.webExtensions.info("Extension update discovery: checking \(candidates.count) installed extensions")
        for identifier in candidates {
            guard !isStopped, !Task.isCancelled, let version else { return }
            // Installs and removals can happen while an earlier request is suspended.
            let currentVersion = await version(identifier)
            guard !isStopped, !Task.isCancelled else { return }
            guard let currentVersion, let check else { continue }
            let result = await check(identifier, currentVersion.reportedVersion)
            guard !isStopped, !Task.isCancelled else { return }
            lastCheckedIdentifier = identifier
            logUpdateCheck(result, identifier: identifier, version: currentVersion)
            if let deadline = result.retryNotBefore, deadline > Date() {
                retryNotBefore = deadline
                break
            }
        }
    }

    private func orderedIdentifiers(_ identifiers: [String]) -> [String] {
        let candidates = identifiers.sorted()
        guard let lastCheckedIdentifier, let next = candidates.firstIndex(where: { $0 > lastCheckedIdentifier }) else { return candidates }
        return Array(candidates[next...]) + Array(candidates[..<next])
    }

    private func logUpdateCheck(_ result: ChromeWebStoreUpdateChecker.CheckResult, identifier: String, version: Version) {
        switch result.outcome {
        case .update(let update):
            Logger.webExtensions.info("Extension update discovery: \(identifier, privacy: .public) installed=\(version.installedVersion, privacy: .public) reported=\(version.reportedVersion, privacy: .public) available=\(update.version, privacy: .public)")
        case .noUpdate:
            Logger.webExtensions.info("Extension update discovery: \(identifier, privacy: .public) installed=\(version.installedVersion, privacy: .public) reported=\(version.reportedVersion, privacy: .public) noUpdate")
        case .failure(let failure):
            Logger.webExtensions.error("Extension update discovery: \(identifier, privacy: .public) installed=\(version.installedVersion, privacy: .public) reported=\(version.reportedVersion, privacy: .public) failed=\(String(describing: failure), privacy: .public)")
        }
        if let deadline = result.retryNotBefore {
            Logger.webExtensions.info("Extension update discovery: server retry deadline=\(deadline, privacy: .public)")
        }
    }
}
