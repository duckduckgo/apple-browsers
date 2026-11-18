//
//  AssistedOptOutQueue.swift
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

import ConcurrencyExtensions
import Foundation
import os.log

@MainActor
/// Shows and closes the window where the user works through an assisted opt-out.
public protocol AssistedOptOutPresenting: AnyObject {
    func present(_ session: AssistedOptOutSession)
    func userTurnStarted(in session: AssistedOptOutSession)
    func dismiss(_ session: AssistedOptOutSession)
}

@MainActor
/// Decides which opt-outs need the user, lists them for the dashboard, and runs the one the user starts.
/// Only one assisted attempt runs at a time.
public final class AssistedOptOutQueue {
    public static let defaultAttemptTimeout: TimeInterval = .minutes(10)

    /// An opt-out record the queue might ask the user about, read from the database for a broker on the remote list.
    /// Being a candidate doesn't put it on the "Needs you" list; `entersNeedsYou` and `isAwaiting` decide that.
    private struct Candidate: Sendable {
        let data: BrokerProfileQueryData
        let job: OptOutJobData
        let id: AssistedOptOutID
    }

    /// The candidate list plus the generation and config it was loaded under. Callers check sign-in after loading,
    /// and `isAuthenticated(for:)` uses these to throw away a list that went stale during that wait.
    private struct LoadedSnapshot {
        let candidates: [Candidate]
        let generation: Int
        let config: UserAssistanceConfig
    }

    private let dependencies: BrokerProfileJobDependencyProviding
    private let attemptTimeout: TimeInterval
    private let now: () -> Date
    private let instrumentation: AssistedOptOutInstrumentation?
    public weak var presenter: AssistedOptOutPresenting?

    /// Attempts with an open window, including submitted ones the dashboard still shows.
    private var sessions: [AssistedOptOutID: AssistedOptOutSession] = [:]
    /// The attempt currently working on a broker page, if any.
    private var runningID: AssistedOptOutID?
    private var runningTask: Task<Void, Never>?
    private var runningCancellation: AttemptCancellation?
    /// Cached candidates, so each dashboard refresh doesn't reread the database.
    private var snapshot: [Candidate]?
    /// The remote config the cache was built for. A different config means the cache is stale.
    private var snapshotConfig: UserAssistanceConfig?
    /// The database read in progress, shared by callers that ask while it runs.
    private var snapshotTask: Task<[Candidate], Error>?
    /// Bumped whenever the cache is cleared, for example after an attempt ends or the config changes.
    /// A load or sign-in check that started under an older generation is thrown away.
    private var generation = 0
    /// Records this queue put on the "Needs you" list that the cached candidates don't show yet.
    private var awaitingIDs: Set<AssistedOptOutID> = []

    public init(dependencies: BrokerProfileJobDependencyProviding,
                attemptTimeout: TimeInterval = AssistedOptOutQueue.defaultAttemptTimeout,
                now: @escaping () -> Date = Date.init,
                instrumentation: AssistedOptOutInstrumentation? = nil) {
        self.dependencies = dependencies
        self.attemptTimeout = attemptTimeout
        self.now = now
        self.instrumentation = instrumentation
    }

    private var config: UserAssistanceConfig { dependencies.userAssistanceConfig }

    public var activeSessions: [AssistedOptOutSession] {
        sessions.values.sorted { $0.id.description < $1.id.description }
    }

    public func invalidate() {
        generation += 1
        snapshot = nil
        snapshotTask = nil
        snapshotConfig = nil
        awaitingIDs.removeAll()
    }

    public func configurationDidChange() {
        invalidate()
        if dependencies.isPausedForRevokedSigningKey { cancelAll() }
        cancelAttemptsNotEnabled()
    }

    /// Puts due opt-outs onto the "Needs you" list by recording that they wait for the user,
    /// and closes attempts whose record is no longer a candidate.
    public func refresh() async throws {
        cancelAttemptsNotEnabled()
        guard !dependencies.isPausedForRevokedSigningKey else {
            cancelAll()
            return
        }
        guard try await isAuthenticated() else {
            cancelAll()
            return
        }
        guard let loaded = try await loadAuthenticatedSnapshot() else {
            cancelAll()
            return
        }
        let config = loaded.config
        let candidates = loaded.candidates
        let candidateIDs = Set(candidates.map(\.id))
        for session in activeSessions where session.phase != .submitted && !candidateIDs.contains(session.id) {
            cancel(session.id)
        }
        for candidate in candidates where entersNeedsYou(candidate) {
            guard config.isEnabled(forBrokerURL: candidate.data.dataBroker.url) else { continue }
            do {
                try dependencies.database.add(HistoryEvent(extractedProfileId: candidate.id.extractedProfileId,
                                                           brokerId: candidate.id.brokerId,
                                                           profileQueryId: candidate.id.profileQueryId,
                                                           type: .optOutAwaitingUserAssistance))
                awaitingIDs.insert(candidate.id)
            } catch {
                Logger.dataBrokerProtection.error("Failed to mark opt-out as awaiting user assistance: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The "Needs you" list for the dashboard: attempts with an open window, then opt-outs the user hasn't started.
    /// `droppingSubmitted` closes finished attempts first.
    public func assistedOptOuts(droppingSubmitted: Bool = false) async throws -> [AssistedOptOut] {
        cancelAttemptsNotEnabled()
        guard !dependencies.isPausedForRevokedSigningKey else {
            cancelAll()
            return []
        }
        guard try await isAuthenticated() else {
            cancelAll()
            return []
        }
        if droppingSubmitted {
            for session in activeSessions where session.phase == .submitted {
                sessions[session.id] = nil
                presenter?.dismiss(session)
            }
        }
        guard let loaded = try await loadAuthenticatedSnapshot(), !dependencies.isPausedForRevokedSigningKey else {
            cancelAll()
            return []
        }
        let config = loaded.config
        guard config.isEnabled else { return [] }
        let live = activeSessions.filter { config.isEnabled(forBrokerURL: $0.broker.url) }.map(\.dashboardItem)
        let waiting = loaded.candidates.filter { sessions[$0.id] == nil && isAwaiting($0) }.map {
            AssistedOptOut(id: $0.id.description,
                           dataBroker: .init(name: $0.data.dataBroker.name, url: $0.data.dataBroker.url),
                           extractedProfileId: $0.id.extractedProfileId, state: .waiting)
        }
        return live + waiting
    }

    /// Opens the window for an opt-out the user picked from the dashboard. Brings an already open window to the front,
    /// and while another attempt is in progress brings that attempt's window to the front instead.
    public func start(id: AssistedOptOutID) async throws {
        cancelAttemptsNotEnabled()
        guard try await isAuthenticated(), config.isEnabled, !dependencies.isPausedForRevokedSigningKey else {
            cancelAll()
            return
        }
        if let session = sessions[id] ?? sessions.values.first(where: { $0.phase != .submitted }) {
            presenter?.present(session)
            return
        }
        guard runningID == nil else { return }
        guard let loaded = try await loadAuthenticatedSnapshot(), loaded.config.isEnabled,
              !dependencies.isPausedForRevokedSigningKey else { return }
        if let blocking = sessions.values.first(where: { $0.phase != .submitted }) {
            presenter?.present(blocking)
            return
        }
        guard runningID == nil,
              let candidate = loaded.candidates.first(where: { $0.id == id && isAwaiting($0) }),
              let actions = candidate.data.dataBroker.optOutStep()?.actions else { return }
        let session = AssistedOptOutSession(id: id,
                                            broker: .init(name: candidate.data.dataBroker.name, url: candidate.data.dataBroker.url),
                                            steps: AssistedOptOutSteps(actions: actions),
                                            instrumentation: instrumentation, now: now)
        session.onBeginRequested = { [weak self] in self?.begin($0, candidate: candidate) }
        session.onUserTurnStarted = { [weak self] in self?.presenter?.userTurnStarted(in: $0) }
        session.onCancelRequested = { [weak self] in self?.cancel($0.id) }
        sessions[id] = session
        presenter?.present(session)
    }

    public func cancel(_ id: AssistedOptOutID) {
        guard let session = sessions[id] else { return }
        session.markCancelled()
        if runningID == id {
            runningCancellation?.cancel()
            runningTask?.cancel()
        } else {
            session.finish(outcome: .cancelled)
            sessions[id] = nil
            presenter?.dismiss(session)
        }
    }

    public func cancelAll() {
        invalidate()
        for id in Array(sessions.keys) { cancel(id) }
    }

    private func cancelAttemptsNotEnabled() {
        let config = config
        for session in activeSessions where !config.isEnabled(forBrokerURL: session.broker.url) {
            cancel(session.id)
        }
    }

    private func begin(_ session: AssistedOptOutSession, candidate: Candidate) {
        guard sessions[session.id] === session, runningID == nil,
              config.isEnabled(forBrokerURL: session.broker.url), !dependencies.isPausedForRevokedSigningKey,
              dependencies.runningAssistedOptOuts.tryInsertAssisted(session.id) else {
            cancel(session.id)
            return
        }
        runningID = session.id
        let cancellation = AttemptCancellation()
        runningCancellation = cancellation
        runningTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.run(session, candidate: candidate, cancellation: cancellation)
            self.dependencies.runningAssistedOptOuts.remove(session.id)
            self.runningID = nil
            self.runningTask = nil
            self.runningCancellation = nil
            session.finish(outcome: outcome)
            if outcome != .submitted {
                self.sessions[session.id] = nil
                self.presenter?.dismiss(session)
            }
            self.invalidate()
        }
    }

    private func run(_ session: AssistedOptOutSession, candidate: Candidate,
                     cancellation: AttemptCancellation) async -> AssistedOptOutOutcome {
        guard !Task.isCancelled, !cancellation.isCancelled,
              config.isEnabled(forBrokerURL: session.broker.url),
              !dependencies.isPausedForRevokedSigningKey else { return .cancelled }
        let subJob = BrokerProfileOptOutSubJob(dependencies: dependencies)
        let dependencies = self.dependencies
        let brokerURL = session.broker.url
        do {
            let submitted = try await withTimeout(attemptTimeout, throwing: DataBrokerProtectionError.jobTimeout) {
                guard await dependencies.isAuthenticatedUser(),
                      dependencies.userAssistanceConfig.isEnabled(forBrokerURL: brokerURL),
                      !dependencies.isPausedForRevokedSigningKey else { throw DataBrokerProtectionError.cancelled }
                try Task.checkCancellation()
                return try await subJob.runAssistedOptOut(for: candidate.job.extractedProfile,
                                                   brokerProfileQueryData: candidate.data,
                                                   observer: session,
                                                   shouldRunNextStep: { !cancellation.isCancelled && !dependencies.isPausedForRevokedSigningKey })
            }
            guard !cancellation.isCancelled else { return .cancelled }
            if submitted { session.markSubmitted() }
            return submitted ? .submitted : .failed
        } catch {
            if cancellation.isCancelled || error is CancellationError { return .cancelled }
            if case DataBrokerProtectionError.jobTimeout = error { return .timedOut }
            if case DataBrokerProtectionError.cancelled = error { return .cancelled }
            return .failed
        }
    }

    /// Throws if the cache was cleared or the config changed while waiting for the sign-in check,
    /// so the caller drops what it loaded.
    private func isAuthenticated(for loaded: LoadedSnapshot? = nil) async throws -> Bool {
        let expectedGeneration = loaded?.generation ?? generation
        let expectedConfig = loaded?.config ?? config
        let authenticated = await dependencies.isAuthenticatedUser()
        guard expectedGeneration == generation, expectedConfig == config else { throw CancellationError() }
        return authenticated
    }

    /// Loads the candidates and checks sign-in, loading again a few times if the cache is cleared meanwhile.
    /// Returns nil when the user isn't signed in.
    private func loadAuthenticatedSnapshot() async throws -> LoadedSnapshot? {
        var reloads = 0
        while true {
            do {
                let loaded = try await loadSnapshot()
                return try await isAuthenticated(for: loaded) ? loaded : nil
            } catch is CancellationError where reloads < 2 && !Task.isCancelled {
                reloads += 1
            }
        }
    }

    private func loadSnapshot() async throws -> LoadedSnapshot {
        let requestedConfig = config
        guard requestedConfig.isEnabled else { return LoadedSnapshot(candidates: [], generation: generation, config: requestedConfig) }
        if let snapshotConfig, snapshotConfig != requestedConfig { invalidate() }
        if let snapshot { return LoadedSnapshot(candidates: snapshot, generation: generation, config: requestedConfig) }
        let requestedGeneration = generation
        let task: Task<[Candidate], Error>
        if let snapshotTask {
            task = snapshotTask
        } else {
            let database = dependencies.database
            task = Task.detached(priority: .utility) {
                let brokers = try database.fetchAllDataBrokers().filter {
                    requestedConfig.isEnabled(forBrokerURL: $0.url) && !$0.isRemoved && !$0.performsOptOutWithinParent()
                }
                return try brokers.compactMap(\.id).sorted().flatMap { brokerID in
                    try database.fetchBrokerProfileQueryData(forBrokerId: brokerID).flatMap { data in
                        data.optOutJobData.compactMap { job -> Candidate? in
                            guard job.extractedProfile.removedDate == nil, !job.isRemovedByUser,
                                  let extractedID = job.extractedProfile.id else { return nil }
                            return Candidate(data: data, job: job,
                                             id: .init(brokerId: job.brokerId, profileQueryId: job.profileQueryId,
                                                       extractedProfileId: extractedID))
                        }
                    }
                }
            }
            snapshotConfig = requestedConfig
            snapshotTask = task
        }
        do {
            let loaded = try await task.value
            guard requestedGeneration == generation, requestedConfig == config else { throw CancellationError() }
            snapshot = loaded
            snapshotTask = nil
            return LoadedSnapshot(candidates: loaded, generation: requestedGeneration, config: requestedConfig)
        } catch {
            if requestedGeneration == generation { snapshotTask = nil }
            throw error
        }
    }

    /// Whether the record is on the "Needs you" list. It's hidden while a scheduled opt-out is running on it.
    private func isAwaiting(_ candidate: Candidate) -> Bool {
        guard !dependencies.runningAssistedOptOuts.isRegularRunning(candidate.id) else { return false }
        return awaitingIDs.contains(candidate.id) || candidate.job.historyEvents.max(by: { $0.date < $1.date })?.type == .optOutAwaitingUserAssistance
    }

    /// Whether `refresh` should add the record to the "Needs you" list: nothing is running it, it isn't listed yet,
    /// and its opt-out is due or was interrupted before submitting.
    private func entersNeedsYou(_ candidate: Candidate) -> Bool {
        guard sessions[candidate.id] == nil, !dependencies.runningAssistedOptOuts.contains(candidate.id),
              !isAwaiting(candidate) else { return false }
        switch candidate.job.historyEvents.max(by: { $0.date < $1.date })?.type {
        case .optOutSubmittedAndAwaitingEmailConfirmation:
            return false
        case .optOutStarted:
            return true
        default:
            return candidate.job.preferredRunDate.map { $0 <= now() } ?? true
        }
    }
}

private final class AttemptCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }
}
