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

/// Shows assisted attempts to the user. The agent implements it with its own window.
@MainActor
public protocol AssistedOptOutPresenting: AnyObject {
    func present(_ session: AssistedOptOutSession)
    func userTurnStarted(in session: AssistedOptOutSession)
    func dismiss(_ session: AssistedOptOutSession)
}

/// Runs the opt-outs users start from Needs you, one attempt at a time and apart from the regular queue.
@MainActor
public final class AssistedOptOutQueue {
    public static let defaultAttemptTimeout: TimeInterval = .minutes(10)

    private let dependencies: BrokerProfileJobDependencyProviding
    private let attemptTimeout: TimeInterval
    private let now: () -> Date
    private let runningAttempts: RunningAssistedOptOuts
    public weak var presenter: AssistedOptOutPresenting?

    private var sessions: [AssistedOptOutID: AssistedOptOutSession] = [:]
    private var queuedIDs: [AssistedOptOutID] = []
    private var runningID: AssistedOptOutID?
    private var runningTask: Task<Void, Never>?
    private var runningCancellation: AttemptCancellation?

    public init(dependencies: BrokerProfileJobDependencyProviding,
                attemptTimeout: TimeInterval = AssistedOptOutQueue.defaultAttemptTimeout,
                now: @escaping () -> Date = Date.init,
                runningAttempts: RunningAssistedOptOuts = .shared) {
        self.dependencies = dependencies
        self.attemptTimeout = attemptTimeout
        self.now = now
        self.runningAttempts = runningAttempts
    }

    private var config: UserAssistanceConfig { dependencies.userAssistanceConfig }

    public var activeSessions: [AssistedOptOutSession] {
        sessions.values.sorted { $0.id.description < $1.id.description }
    }

    // MARK: - Needs you

    /// Applies the current config: stops attempts for brokers no longer enabled, and writes `optOutAwaitingUserAssistance`
    /// once for each due opt-out of an enabled broker, including ones a restart interrupted.
    public func refresh() {
        let config = self.config
        cancelAttempts(notEnabledIn: config)
        guard config.isEnabled else { return }
        do {
            for (data, job) in try candidateOptOuts(config: config) where entersNeedsYou(job) {
                guard let extractedProfileId = job.extractedProfile.id else { continue }
                try dependencies.database.add(HistoryEvent(extractedProfileId: extractedProfileId,
                                                           brokerId: job.brokerId,
                                                           profileQueryId: job.profileQueryId,
                                                           type: .optOutAwaitingUserAssistance))
                Logger.dataBrokerProtection.log("Opt-out entered Needs you: \(data.dataBroker.url, privacy: .public)")
            }
        } catch {
            Logger.dataBrokerProtection.error("Assisted opt-outs refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The Needs you list. Read-only apart from stopping attempts the config no longer allows.
    /// `droppingSubmitted` clears submitted attempts first, so a dashboard reload no longer shows them.
    public func assistedOptOuts(droppingSubmitted: Bool = false) -> [AssistedOptOut] {
        let config = self.config
        cancelAttempts(notEnabledIn: config)
        if droppingSubmitted {
            for session in sessions.values where session.phase == .submitted {
                sessions[session.id] = nil
            }
        }
        guard config.isEnabled else { return [] }

        let live = activeSessions.map(\.dashboardItem)
        let openBrokerIds = Set(sessions.keys.map(\.brokerId))
        let waiting: [AssistedOptOut]
        do {
            let groups = try waitingOptOutsByBroker(config: config).filter { !openBrokerIds.contains($0.brokerId) }
            waiting = groups.map { group in
                AssistedOptOut(id: group.ids[0].description,
                               dataBroker: group.broker,
                               recordCount: group.ids.count,
                               state: .waiting)
            }
        } catch {
            Logger.dataBrokerProtection.error("Assisted opt-outs fetch failed: \(error.localizedDescription, privacy: .public)")
            waiting = []
        }
        return live + waiting
    }

    // MARK: - Attempts

    /// Opens the attempt's window on its intro screen, or shows it if it's already open. Only one attempt is open at a
    /// time, so starting another opt-out meanwhile does nothing.
    public func start(id: AssistedOptOutID) {
        if let session = sessions[id] {
            presenter?.present(session)
            return
        }
        guard !sessions.values.contains(where: { $0.phase != .submitted }) else {
            Logger.dataBrokerProtection.log("Ignoring assisted opt-out start while another attempt is open")
            return
        }
        let config = self.config
        guard let (data, _) = try? candidateOptOuts(config: config).first(where: { Self.id(for: $0.job) == id }),
              let actions = data.dataBroker.optOutStep()?.actions else {
            Logger.dataBrokerProtection.error("Can't start assisted opt-out \(id.description, privacy: .public)")
            return
        }
        let recordCount = (try? waitingOptOutsByBroker(config: config).first { $0.brokerId == id.brokerId }?.ids.count) ?? 1
        let session = AssistedOptOutSession(id: id,
                                            broker: .init(name: data.dataBroker.name, url: data.dataBroker.url),
                                            recordCount: max(recordCount, 1),
                                            steps: AssistedOptOutSteps(actions: actions))
        session.onBeginRequested = { [weak self] in self?.enqueue($0) }
        session.onUserTurnStarted = { [weak self] in self?.presenter?.userTurnStarted(in: $0) }
        session.onCancelRequested = { [weak self] in self?.cancel($0.id) }
        sessions[id] = session
        presenter?.present(session)
    }

    private func enqueue(_ session: AssistedOptOutSession) {
        guard sessions[session.id] === session else { return }
        queuedIDs.append(session.id)
        runNextIfIdle()
    }

    public func cancel(_ id: AssistedOptOutID) {
        guard let session = sessions[id], session.phase != .submitted else { return }
        if runningID == id {
            runningCancellation?.cancel()
            runningTask?.cancel()
        } else {
            queuedIDs.removeAll { $0 == id }
            sessions[id] = nil
            presenter?.dismiss(session)
        }
    }

    public func cancelAll() {
        for id in Array(sessions.keys) {
            cancel(id)
        }
    }

    private func cancelAttempts(notEnabledIn config: UserAssistanceConfig) {
        for session in sessions.values where !config.isEnabled(forBrokerURL: session.broker.url) {
            cancel(session.id)
        }
    }

    private func runNextIfIdle() {
        guard runningID == nil, !queuedIDs.isEmpty else { return }
        let id = queuedIDs.removeFirst()
        guard let session = sessions[id] else { return runNextIfIdle() }
        runningID = id
        runningAttempts.insert(id)
        let cancellation = AttemptCancellation()
        runningCancellation = cancellation
        runningTask = Task { [weak self] in
            await self?.run(session, cancellation: cancellation)
            self?.finish(session)
        }
    }

    private func run(_ session: AssistedOptOutSession, cancellation: AttemptCancellation) async {
        guard let data = try? dependencies.database.fetchBrokerProfileQueryData(forBrokerId: session.id.brokerId)
                .first(where: { $0.profileQuery.id == session.id.profileQueryId }),
              let job = data.optOutJobData.first(where: { $0.extractedProfile.id == session.id.extractedProfileId }) else { return }

        let subJob = BrokerProfileOptOutSubJob(dependencies: dependencies)
        do {
            let submitted = try await withTimeout(attemptTimeout, throwing: DataBrokerProtectionError.jobTimeout) {
                try await subJob.runAssistedOptOut(for: job.extractedProfile,
                                                   brokerProfileQueryData: data,
                                                   observer: session,
                                                   shouldRunNextStep: { !cancellation.isCancelled })
            }
            if submitted {
                session.markSubmitted()
            }
        } catch {
            Logger.dataBrokerProtection.log("Assisted opt-out ended: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func finish(_ session: AssistedOptOutSession) {
        runningAttempts.remove(session.id)
        runningID = nil
        runningTask = nil
        runningCancellation = nil
        if session.phase != .submitted {
            sessions[session.id] = nil
            presenter?.dismiss(session)
        }
        runNextIfIdle()
    }

    // MARK: - Helpers

    private func candidateOptOuts(config: UserAssistanceConfig) throws -> [(data: BrokerProfileQueryData, job: OptOutJobData)] {
        try dependencies.database.fetchActiveBrokerProfileQueryData()
            .filter { config.isEnabled(forBrokerURL: $0.dataBroker.url) && !$0.dataBroker.isRemoved
                && !$0.dataBroker.performsOptOutWithinParent() }
            .flatMap { data in
                data.optOutJobData
                    .filter { $0.extractedProfile.removedDate == nil && !$0.isRemovedByUser }
                    .map { (data, $0) }
            }
    }

    private func entersNeedsYou(_ job: OptOutJobData) -> Bool {
        guard let id = Self.id(for: job), sessions[id] == nil else { return false }
        switch job.historyEvents.latest?.type {
        case .optOutAwaitingUserAssistance, .optOutSubmittedAndAwaitingEmailConfirmation:
            return false
        case .optOutStarted:
            return true
        default:
            return job.preferredRunDate.map { $0 <= now() } ?? false
        }
    }

    private func waitingOptOutsByBroker(config: UserAssistanceConfig) throws
        -> [(brokerId: Int64, broker: AssistedOptOut.DataBroker, ids: [AssistedOptOutID])] {
        var groups: [(brokerId: Int64, broker: AssistedOptOut.DataBroker, ids: [AssistedOptOutID])] = []
        for (data, job) in try candidateOptOuts(config: config)
        where job.historyEvents.latest?.type == .optOutAwaitingUserAssistance {
            guard let id = Self.id(for: job) else { continue }
            if let index = groups.firstIndex(where: { $0.brokerId == id.brokerId }) {
                groups[index].ids.append(id)
            } else {
                groups.append((id.brokerId, .init(name: data.dataBroker.name, url: data.dataBroker.url), [id]))
            }
        }
        return groups
    }

    nonisolated static func id(for job: OptOutJobData) -> AssistedOptOutID? {
        job.extractedProfile.id.map { AssistedOptOutID(brokerId: job.brokerId, profileQueryId: job.profileQueryId, extractedProfileId: $0) }
    }
}

/// The opt-outs with an assisted attempt running in this process, shared with the regular queue so it doesn't run
/// the same opt-out at the same time once user assistance is turned off.
public final class RunningAssistedOptOuts: @unchecked Sendable {
    public static let shared = RunningAssistedOptOuts()

    private let lock = NSLock()
    private var ids: Set<AssistedOptOutID> = []

    public init() {}

    func contains(_ id: AssistedOptOutID) -> Bool { lock.withLock { ids.contains(id) } }
    func insert(_ id: AssistedOptOutID) { lock.withLock { _ = ids.insert(id) } }
    func remove(_ id: AssistedOptOutID) { lock.withLock { _ = ids.remove(id) } }
}

private final class AttemptCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

private extension Array where Element == HistoryEvent {
    var latest: HistoryEvent? { self.max(by: { $0.date < $1.date }) }
}
