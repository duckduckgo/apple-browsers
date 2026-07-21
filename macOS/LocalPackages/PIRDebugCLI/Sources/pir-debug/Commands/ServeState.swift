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
        let id: String
        let kind: String
        var status: String // "running" | "succeeded" | "failed"
        var resultData: Data?
        var error: String?

        init(id: String, kind: String) {
            self.id = id
            self.kind = kind
            self.status = "running"
        }
    }

    /// The shared session. Touch only from `@MainActor`.
    let session: PIRDebugSession
    /// Brokers cached at startup (immutable).
    let brokers: [DataBroker]

    private let lock = NSLock()
    private var jobs: [String: Job] = [:]
    private var events: [PIRDebugEvent] = []

    init(session: PIRDebugSession, brokers: [DataBroker]) {
        self.session = session
        self.brokers = brokers
    }

    // MARK: - Jobs

    func createJob(kind: String) -> String {
        let id = UUID().uuidString
        lock.lock(); defer { lock.unlock() }
        jobs[id] = Job(id: id, kind: kind)
        return id
    }

    func completeJob(id: String, resultData: Data) {
        lock.lock(); defer { lock.unlock() }
        guard let job = jobs[id] else { return }
        job.status = "succeeded"
        job.resultData = resultData
    }

    func failJob(id: String, error: String) {
        lock.lock(); defer { lock.unlock() }
        guard let job = jobs[id] else { return }
        job.status = "failed"
        job.error = error
    }

    /// A JSON body for `GET /jobs/<id>`, embedding the stored result JSON verbatim, or `nil` if the
    /// job is unknown.
    func jobResponse(id: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let job = jobs[id] else { return nil }
        var object: [String: Any] = ["id": job.id, "kind": job.kind, "status": job.status]
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
    }

    /// Returns events with index >= `since` and the next cursor to poll with.
    func eventsSince(_ since: Int) -> (nextCursor: Int, events: [PIRDebugEvent]) {
        lock.lock(); defer { lock.unlock() }
        let start = max(0, min(since, events.count))
        return (events.count, Array(events[start...]))
    }
}
