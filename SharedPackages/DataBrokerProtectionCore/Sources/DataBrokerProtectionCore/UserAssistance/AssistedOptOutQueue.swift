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

    private struct Candidate: Sendable {
        let data: BrokerProfileQueryData
        let job: OptOutJobData
        let id: AssistedOptOutID
    }

    private let dependencies: BrokerProfileJobDependencyProviding
    private let attemptTimeout: TimeInterval
    private let now: () -> Date
    private let instrumentation: AssistedOptOutInstrumentation?
    public weak var presenter: AssistedOptOutPresenting?

    private var session: AssistedOptOutSession?
    private var runningTask: Task<Void, Never>?
    private var runningCancellation: AttemptCancellation?
    private var cache: (config: UserAssistanceConfig, candidates: [Candidate])?

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
        session.map { [$0] } ?? []
    }

    public func invalidate() {
        cache = nil
    }

    public func configurationDidChange() {
        invalidate()
        if dependencies.isPausedForRevokedSigningKey { cancelAll() }
        cancelAttemptNotEnabled()
    }

    public func assistedOptOuts() async throws -> [AssistedOptOut] {
        guard let candidates = try await availableCandidates() else { return [] }
        let live = session.map { [$0.dashboardItem] } ?? []
        let waiting = candidates.filter { $0.id != session?.id && needsUser($0) }.map {
            AssistedOptOut(id: $0.id.description,
                           dataBroker: .init(name: $0.data.dataBroker.name, url: $0.data.dataBroker.url),
                           state: .waiting)
        }
        return live + waiting
    }

    public func start(id: AssistedOptOutID) async throws {
        guard let candidates = try await availableCandidates() else { return }
        if let session, session.phase != .submitted || session.id == id {
            presenter?.present(session)
            return
        }
        guard let candidate = candidates.first(where: { $0.id == id && needsUser($0) }),
              let actions = candidate.data.dataBroker.optOutStep()?.actions else { return }
        if let finished = self.session {
            self.session = nil
            presenter?.dismiss(finished)
        }
        let session = AssistedOptOutSession(id: id,
                                            broker: .init(name: candidate.data.dataBroker.name, url: candidate.data.dataBroker.url),
                                            steps: AssistedOptOutSteps(actions: actions),
                                            instrumentation: instrumentation, now: now)
        session.onBeginRequested = { [weak self] in self?.begin($0, candidate: candidate) }
        session.onUserTurnStarted = { [weak self] in self?.presenter?.userTurnStarted(in: $0) }
        session.onCancelRequested = { [weak self] in self?.cancel($0.id) }
        self.session = session
        presenter?.present(session)
    }

    public func cancel(_ id: AssistedOptOutID) {
        guard let session, session.id == id else { return }
        session.markCancelled()
        if runningTask != nil {
            runningCancellation?.cancel()
            runningTask?.cancel()
        } else {
            session.finish(outcome: .cancelled)
            self.session = nil
            presenter?.dismiss(session)
        }
    }

    public func cancelAll() {
        invalidate()
        if let session { cancel(session.id) }
    }

    private func cancelAttemptNotEnabled() {
        if let session, !config.isEnabled(forBrokerURL: session.broker.url) {
            cancel(session.id)
        }
    }

    private func begin(_ session: AssistedOptOutSession, candidate: Candidate) {
        guard self.session === session, runningTask == nil,
              config.isEnabled(forBrokerURL: session.broker.url), !dependencies.isPausedForRevokedSigningKey else {
            cancel(session.id)
            return
        }
        let cancellation = AttemptCancellation()
        runningCancellation = cancellation
        runningTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.run(session, candidate: candidate, cancellation: cancellation)
            self.runningTask = nil
            self.runningCancellation = nil
            session.finish(outcome: outcome)
            if outcome != .submitted {
                self.session = nil
                self.presenter?.dismiss(session)
            }
            self.invalidate()
        }
    }

    private func run(_ session: AssistedOptOutSession, candidate: Candidate,
                     cancellation: AttemptCancellation) async -> AssistedOptOutOutcome {
        guard await dependencies.isAuthenticatedUser(), !cancellation.isCancelled else { return .cancelled }
        let subJob = BrokerProfileOptOutSubJob(dependencies: dependencies)
        do {
            let submitted = try await withTimeout(attemptTimeout, throwing: DataBrokerProtectionError.jobTimeout) {
                try await subJob.runAssistedOptOut(for: candidate.job.extractedProfile,
                                                   brokerProfileQueryData: candidate.data,
                                                   observer: session,
                                                   shouldRunNextStep: { !cancellation.isCancelled })
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

    private func availableCandidates() async throws -> [Candidate]? {
        let isAuthenticated = await dependencies.isAuthenticatedUser()
        guard isAuthenticated, !dependencies.isPausedForRevokedSigningKey else {
            cancelAll()
            return nil
        }
        cancelAttemptNotEnabled()
        return try loadCandidates()
    }

    private func loadCandidates() throws -> [Candidate] {
        let config = config
        if let cache, cache.config == config { return cache.candidates }
        let database = dependencies.database
        let candidates = try config.enabledBrokers.sorted().flatMap { url -> [Candidate] in
            guard let broker = try database.fetchBroker(withURL: url), let brokerID = broker.id,
                  broker.requiresUserAssistance, !broker.isRemoved, !broker.performsOptOutWithinParent() else { return [] }
            return try database.fetchBrokerProfileQueryData(forBrokerId: brokerID).flatMap { data in
                data.optOutJobData.compactMap { job -> Candidate? in
                    guard job.extractedProfile.removedDate == nil, !job.isRemovedByUser,
                          let extractedID = job.extractedProfile.id else { return nil }
                    return Candidate(data: data, job: job,
                                     id: .init(brokerId: job.brokerId, profileQueryId: job.profileQueryId,
                                               extractedProfileId: extractedID))
                }
            }
        }
        cache = (config, candidates)
        return candidates
    }

    private func needsUser(_ candidate: Candidate) -> Bool {
        switch candidate.job.historyEvents.max(by: { $0.date < $1.date })?.type {
        case .optOutSubmittedAndAwaitingEmailConfirmation:
            return false
        case .optOutStarted, .optOutAwaitingUserAssistance:
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
