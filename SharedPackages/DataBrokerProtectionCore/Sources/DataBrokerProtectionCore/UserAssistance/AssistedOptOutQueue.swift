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

@MainActor
public protocol AssistedOptOutPresenting: AnyObject {
    func present(_ session: AssistedOptOutSession)
    func userTurnStarted(in session: AssistedOptOutSession)
    func dismiss(_ session: AssistedOptOutSession)
}

@MainActor
public final class AssistedOptOutQueue {
    public static let defaultAttemptTimeout: TimeInterval = .minutes(10)

    private struct Candidate: Sendable {
        let data: BrokerProfileQueryData
        let job: OptOutJobData
        let id: AssistedOptOutID
    }

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

    private var sessions: [AssistedOptOutID: AssistedOptOutSession] = [:]
    private var runningID: AssistedOptOutID?
    private var runningTask: Task<Void, Never>?
    private var runningCancellation: AttemptCancellation?
    private var snapshot: [Candidate]?
    private var snapshotConfig: UserAssistanceConfig?
    private var snapshotTask: Task<[Candidate], Error>?
    private var generation = 0
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
        let loaded = try await loadSnapshot()
        guard try await isAuthenticated(for: loaded) else {
            cancelAll()
            return
        }
        let candidates = loaded.candidates
        let candidateIDs = Set(candidates.map(\.id))
        for session in activeSessions where session.phase != .submitted && !candidateIDs.contains(session.id) {
            cancel(session.id)
        }
        for candidate in candidates where entersNeedsYou(candidate) {
            guard config.isEnabled(forBrokerURL: candidate.data.dataBroker.url) else { continue }
            try dependencies.database.add(HistoryEvent(extractedProfileId: candidate.id.extractedProfileId,
                                                       brokerId: candidate.id.brokerId,
                                                       profileQueryId: candidate.id.profileQueryId,
                                                       type: .optOutAwaitingUserAssistance))
            awaitingIDs.insert(candidate.id)
        }
    }

    public func assistedOptOuts(droppingSubmitted: Bool = false) async throws -> [AssistedOptOut] {
        cancelAttemptsNotEnabled()
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
        let loaded = try await loadSnapshot()
        guard try await isAuthenticated(for: loaded) else {
            cancelAll()
            return []
        }
        guard config.isEnabled else { return [] }
        let candidates = loaded.candidates
        let live = activeSessions.filter { config.isEnabled(forBrokerURL: $0.broker.url) }.map(\.dashboardItem)
        let openBrokerIDs = Set(sessions.keys.map(\.brokerId))
        let groups = Dictionary(grouping: candidates.filter {
            isAwaiting($0) && !openBrokerIDs.contains($0.id.brokerId)
        }, by: { $0.id.brokerId })
        let waiting = groups.keys.sorted().compactMap { brokerID -> AssistedOptOut? in
            guard let group = groups[brokerID], let first = group.first else { return nil }
            return AssistedOptOut(id: first.id.description,
                                  dataBroker: .init(name: first.data.dataBroker.name, url: first.data.dataBroker.url),
                                  recordCount: group.count, state: .waiting)
        }
        return live + waiting
    }

    public func start(id: AssistedOptOutID) async throws {
        cancelAttemptsNotEnabled()
        guard try await isAuthenticated(), config.isEnabled, !dependencies.isPausedForRevokedSigningKey else {
            cancelAll()
            return
        }
        if let session = sessions[id] {
            presenter?.present(session)
            return
        }
        guard runningID == nil, !sessions.values.contains(where: { $0.phase != .submitted }) else { return }
        let loaded = try await loadSnapshot()
        guard try await isAuthenticated(for: loaded), config.isEnabled, !dependencies.isPausedForRevokedSigningKey,
              runningID == nil, !sessions.values.contains(where: { $0.phase != .submitted }),
              let candidate = loaded.candidates.first(where: { $0.id == id && isAwaiting($0) }),
              let actions = candidate.data.dataBroker.optOutStep()?.actions else { return }
        let recordCount = loaded.candidates.filter { $0.id.brokerId == id.brokerId && isAwaiting($0) }.count
        let session = AssistedOptOutSession(id: id,
                                            broker: .init(name: candidate.data.dataBroker.name, url: candidate.data.dataBroker.url),
                                            recordCount: recordCount, steps: AssistedOptOutSteps(actions: actions),
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

    private func isAuthenticated(for loaded: LoadedSnapshot? = nil) async throws -> Bool {
        let expectedGeneration = loaded?.generation ?? generation
        let expectedConfig = loaded?.config ?? config
        let authenticated = await dependencies.isAuthenticatedUser()
        guard expectedGeneration == generation, expectedConfig == config else { throw CancellationError() }
        return authenticated
    }

    private func loadSnapshot() async throws -> LoadedSnapshot {
        let requestedConfig = config
        guard requestedConfig.isEnabled else { return LoadedSnapshot(candidates: [], generation: generation, config: requestedConfig) }
        if snapshotConfig != requestedConfig { invalidate() }
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

    private func isAwaiting(_ candidate: Candidate) -> Bool {
        guard !dependencies.runningAssistedOptOuts.isRegularRunning(candidate.id) else { return false }
        return awaitingIDs.contains(candidate.id) || candidate.job.historyEvents.max(by: { $0.date < $1.date })?.type == .optOutAwaitingUserAssistance
    }

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
