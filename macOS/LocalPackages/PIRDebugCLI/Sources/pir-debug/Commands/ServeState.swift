//
//  ServeState.swift
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

import DataBrokerProtectionCore
import Foundation
import PIRDebugKit

/// Shared, lock-guarded state for the `serve` command: one `PIRDebugSession`, a job table, and a
/// buffered event log. Marked `@unchecked Sendable` because the HTTP route handlers (which run on
/// the server's serial queue) and the background `@MainActor` job tasks both touch it; all mutable
/// state is guarded by `lock`, and `session` is only ever used from `@MainActor`.
final class ServeState: @unchecked Sendable {

    /// A single asynchronous job (scan or optout).
    final class Job {
        enum Kind: String { case scan, optout }
        enum Status: String { case running, succeeded, failed }

        let id: String
        let kind: Kind
        var status: Status
        var resultData: Data?
        var error: String?

        init(id: String, kind: Kind) {
            self.id = id
            self.kind = kind
            self.status = .running
        }
    }

    /// The shared session. Touch only from `@MainActor`.
    let session: PIRDebugSession
    /// Brokers cached at startup (immutable).
    let brokers: [DataBroker]

    /// Caps to keep a long-running server's memory bounded.
    private let maxJobs = 1000
    private let maxEvents = 50_000

    private let lock = NSLock()
    private var jobs: [String: Job] = [:]
    private var jobOrder: [String] = []
    /// The single in-flight job, if any. Only one job runs at a time so concurrent scans/opt-outs
    /// cannot trample the shared session's multi-step state (`pendingOptOut`, the email store).
    private var activeJobId: String?
    private var events: [PIRDebugEvent] = []
    /// Number of events dropped off the front by the `maxEvents` cap; keeps `/events` cursors
    /// monotonic across trims.
    private var eventsBase = 0

    init(session: PIRDebugSession, brokers: [DataBroker]) {
        self.session = session
        self.brokers = brokers
    }

    // MARK: - Jobs

    /// Creates a job only if none is currently running, returning its id; returns `nil` (→ HTTP 409)
    /// when a job is already in flight.
    func tryCreateJob(kind: Job.Kind) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard activeJobId == nil else { return nil }
        let id = UUID().uuidString
        jobs[id] = Job(id: id, kind: kind)
        jobOrder.append(id)
        activeJobId = id
        evictOldJobsLocked()
        return id
    }

    func completeJob(id: String, resultData: Data) {
        lock.lock(); defer { lock.unlock() }
        if activeJobId == id { activeJobId = nil }
        guard let job = jobs[id] else { return }
        job.status = .succeeded
        job.resultData = resultData
    }

    func failJob(id: String, error: String) {
        lock.lock(); defer { lock.unlock() }
        if activeJobId == id { activeJobId = nil }
        guard let job = jobs[id] else { return }
        job.status = .failed
        job.error = error
    }

    /// Drops the oldest finished jobs once over `maxJobs`; never evicts the active job. Must be
    /// called with `lock` held.
    private func evictOldJobsLocked() {
        while jobs.count > maxJobs, let oldest = jobOrder.first(where: { $0 != activeJobId }) {
            jobs[oldest] = nil
            jobOrder.removeAll { $0 == oldest }
        }
    }

    /// A JSON body for `GET /jobs/<id>`, embedding the stored result JSON verbatim, or `nil` if the
    /// job is unknown.
    func jobResponse(id: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let job = jobs[id] else { return nil }
        var object: [String: Any] = ["id": job.id, "kind": job.kind.rawValue, "status": job.status.rawValue]
        if let error = job.error { object["error"] = error }
        if let resultData = job.resultData,
           let parsed = try? JSONSerialization.jsonObject(with: resultData) {
            object["result"] = parsed
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Events

    func appendEvent(_ event: PIRDebugEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
        if events.count > maxEvents {
            let overflow = events.count - maxEvents
            events.removeFirst(overflow)
            eventsBase += overflow
        }
    }

    /// Returns events with absolute index >= `since` and the next cursor to poll with. Cursors are
    /// absolute counts (surviving trims); a `since` older than the trim window jumps forward to the
    /// oldest retained event.
    func eventsSince(_ since: Int) -> (nextCursor: Int, events: [PIRDebugEvent]) {
        lock.lock(); defer { lock.unlock() }
        let total = eventsBase + events.count
        let effectiveSince = max(since, eventsBase)
        let start = max(0, min(effectiveSince - eventsBase, events.count))
        return (total, Array(events[start...]))
    }
}
