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
    typealias SchedulerFactory = @Sendable (TimeInterval) -> any ChromeWebStorePeriodicScheduling

    typealias PersistState = @MainActor @Sendable (ChromeWebStoreUpdateState) -> Void
    typealias ResultHandler = @MainActor @Sendable (String, ChromeWebStoreUpdateChecker.Outcome) async -> Void

    static let defaultCheckInterval: TimeInterval = 5 * 60 * 60
    private static let launchCheckMinimumInterval: TimeInterval = 4 * 60 * 60

    private enum BatchAction {
        case continueChecking, pause, stop
    }

    private let interval: TimeInterval
    private let schedulerFactory: SchedulerFactory
    private let now: @Sendable () -> Date
    private var state: ChromeWebStoreUpdateState
    private var persistState: PersistState?
    private var resultHandler: ResultHandler?
    private var installedIdentifiers: IdentifiersProvider?
    private var version: VersionProvider?
    private var check: Check?
    private var periodicScheduler: (any ChromeWebStorePeriodicScheduling)?
    private var startupTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?
    private var lastCheckedIdentifier: String?
    private var isStopped = false
    private var isEnabled: Bool
    private var enableRevision: UInt64 = 0

    init(interval: TimeInterval = ChromeWebStoreUpdateCoordinator.defaultCheckInterval,
         schedulerFactory: @escaping SchedulerFactory = { ChromeWebStorePeriodicScheduler(interval: $0) },
         initialState: ChromeWebStoreUpdateState = .init(),
         isEnabled: Bool = true,
         now: @escaping @Sendable () -> Date = Date.init,
         persistState: PersistState? = nil,
         resultHandler: ResultHandler? = nil,
         installedIdentifiers: @escaping IdentifiersProvider,
         version: @escaping VersionProvider,
         check: @escaping Check) {
        self.interval = interval
        self.schedulerFactory = schedulerFactory
        self.now = now
        self.state = initialState
        self.isEnabled = isEnabled
        self.persistState = persistState
        self.resultHandler = resultHandler
        self.installedIdentifiers = installedIdentifiers
        self.version = version
        self.check = check
    }

    func start() async {
        while !Task.isCancelled, let startup = beginStartupIfNeeded() {
            await startup.value
        }
    }

    /// Revisions prevent queued MainActor updates from restoring an older flag value.
    func setEnabled(_ enabled: Bool, revision: UInt64) {
        guard !isStopped, revision > enableRevision else { return }
        enableRevision = revision
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if enabled {
            beginStartupIfNeeded()
        } else {
            pause()
        }
    }

    @discardableResult
    private func beginStartupIfNeeded() -> Task<Void, Never>? {
        guard !isStopped, isEnabled, periodicScheduler == nil else { return nil }
        if let startupTask { return startupTask }
        // Reserve activation before any await; cancelled activation drains before replacement.
        let startup = Task<Void, Never> { [weak self] in
            await self?.activate()
        }
        startupTask = startup
        return startup
    }

    private func activate() async {
        defer {
            startupTask = nil
            if isEnabled, !isStopped, periodicScheduler == nil {
                beginStartupIfNeeded()
            }
        }
        // A manual batch can still be draining cancellation when the flag is re-enabled.
        await batchTask?.value
        guard !isStopped, isEnabled, !Task.isCancelled else { return }
        let interval = interval
        Logger.webExtensions.info("Extension update discovery: started (interval \(interval, privacy: .public)s)")
        if let lastCompleted = state.lastCompletedBatch,
           (0..<Self.launchCheckMinimumInterval).contains(now().timeIntervalSince(lastCompleted)) {
            Logger.webExtensions.info("Extension update discovery: skipping launch check after recent completed batch")
        } else {
            let initialBatch = startBatch()
            await initialBatch?.value
        }
        guard !isStopped, isEnabled, !Task.isCancelled else { return }
        let scheduler = schedulerFactory(interval)
        periodicScheduler = scheduler
        scheduler.schedule { [weak self] in
            await self?.checkForUpdatesNow()
        }
    }

    /// A terminal stop also prevents a delayed startup task from restarting discovery.
    func stop() {
        isStopped = true
        pause()
        installedIdentifiers = nil
        version = nil
        check = nil
        persistState = nil
        resultHandler = nil
    }

    func checkForUpdatesNow() async {
        guard !isStopped, isEnabled, !Task.isCancelled else { return }
        while let previous = batchTask, previous.isCancelled {
            await previous.value
            guard !isStopped, isEnabled, !Task.isCancelled else { return }
        }
        let batch = startBatch()
        await batch?.value
    }

    private func pause() {
        isEnabled = false
        periodicScheduler?.invalidate()
        periodicScheduler = nil
        startupTask?.cancel()
        batchTask?.cancel()
    }

    private func startBatch() -> Task<Void, Never>? {
        guard !isStopped, isEnabled else { return nil }
        if let batchTask { return batchTask }
        if let retryNotBefore = state.retryNotBefore, retryNotBefore > now() {
            Logger.webExtensions.info("Extension update discovery: deferred until server retry deadline=\(retryNotBefore, privacy: .public)")
            return nil
        }
        // Reserve the batch before any provider await can let another caller enter the actor.
        let batch = Task<Void, Never> { [weak self] in
            await self?.runBatch()
        }
        batchTask = batch
        return batch
    }

    private func runBatch() async {
        defer { batchTask = nil }
        guard !isStopped, isEnabled, !Task.isCancelled, let installedIdentifiers else { return }
        let identifiers = await installedIdentifiers()
        guard !isStopped, isEnabled, !Task.isCancelled else { return }
        guard let identifiers else {
            stop()
            return
        }
        let candidates = orderedIdentifiers(identifiers)
        Logger.webExtensions.info("Extension update discovery: checking \(candidates.count) installed extensions")
        var completedCheck = false
        for (index, identifier) in candidates.enumerated() {
            guard !isStopped, isEnabled, !Task.isCancelled, let version else { return }
            // Installs and removals can happen while an earlier request is suspended.
            let currentVersion = await version(identifier)
            guard !isStopped, isEnabled, !Task.isCancelled else { return }
            guard let currentVersion, let check else { continue }
            let result = await check(identifier, currentVersion.reportedVersion)
            guard !isStopped, isEnabled, !Task.isCancelled else { return }
            let action = await processUpdateCheck(result, identifier: identifier, version: currentVersion)
            guard action != .stop, action != .pause || index == candidates.count - 1 else { return }
            completedCheck = true
        }
        if completedCheck { await recordCompletedBatch() }
    }

    private func recordCompletedBatch() async {
        let completedAt = now()
        state.lastCompletedBatch = completedAt
        if let deadline = state.retryNotBefore, deadline <= completedAt {
            state.retryNotBefore = nil
        }
        await persistState?(state)
    }

    /// Saves timing and reports the outcome before deciding whether more candidates may be checked.
    private func processUpdateCheck(_ result: ChromeWebStoreUpdateChecker.CheckResult, identifier: String, version: Version) async -> BatchAction {
        guard result.outcome != .failure(.cancelled) else { return .stop }
        lastCheckedIdentifier = identifier
        let shouldPause = result.retryNotBefore.map { $0 > now() } ?? false
        if shouldPause {
            state.retryNotBefore = result.retryNotBefore
            // Store the server deadline before yielding to telemetry or another caller.
            await persistState?(state)
            guard !isStopped, isEnabled, !Task.isCancelled else { return .stop }
        }
        logUpdateCheck(result, identifier: identifier, version: version)
        await resultHandler?(identifier, result.outcome)
        guard !isStopped, isEnabled, !Task.isCancelled else { return .stop }
        return shouldPause ? .pause : .continueChecking
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
        case .skipped:
            Logger.webExtensions.info("Extension update discovery: \(identifier, privacy: .public) skipped because Google flagged the extension")
        case .failure(let failure):
            Logger.webExtensions.error("Extension update discovery: \(identifier, privacy: .public) installed=\(version.installedVersion, privacy: .public) reported=\(version.reportedVersion, privacy: .public) failed=\(String(describing: failure), privacy: .public)")
        }
        if let deadline = result.retryNotBefore {
            Logger.webExtensions.info("Extension update discovery: server retry deadline=\(deadline, privacy: .public)")
        }
    }
}
