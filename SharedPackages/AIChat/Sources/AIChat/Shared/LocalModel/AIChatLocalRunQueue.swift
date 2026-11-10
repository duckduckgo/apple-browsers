//
//  AIChatLocalRunQueue.swift
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

/// Runs local-model requests one at a time across the app and turns the engine's output into
/// `submitAIChatLocalRunChunk` payloads: numbered from 0 per request, batched, and closed by a
/// final chunk with the status and metrics.
@MainActor
public final class AIChatLocalRunQueue {

    public typealias ChunkHandler = @MainActor (AIChatLocalRunChunk) -> Void

    private struct Job {
        let request: AIChatLocalRunRequest
        let ownerID: ObjectIdentifier
        let onChunk: ChunkHandler
    }

    private let engine: AIChatLocalModelEngine
    private let batchInterval: TimeInterval
    private let now: () -> TimeInterval
    private var pending: [Job] = []
    private var running: (job: Job, task: Task<Void, Never>)?

    /// - Parameter batchInterval: Text that arrives within this interval of the previous chunk is
    ///   held back and sent with the next one, to keep bridge traffic low.
    public init(engine: AIChatLocalModelEngine,
                batchInterval: TimeInterval = 0.05,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.engine = engine
        self.batchInterval = batchInterval
        self.now = now
    }

    public var isIdle: Bool {
        running == nil && pending.isEmpty
    }

    /// - Parameter ownerID: Identifies the page that asked, so its runs can be dropped when it goes away.
    public func enqueue(_ request: AIChatLocalRunRequest, ownerID: ObjectIdentifier, onChunk: @escaping ChunkHandler) {
        pending.append(Job(request: request, ownerID: ownerID, onChunk: onChunk))
        startNextIfIdle()
    }

    /// Request ids come from the page, so another page's run with the same id is left alone.
    public func cancel(requestId: String, ownerID: ObjectIdentifier) {
        if let running, running.job.request.requestId == requestId, running.job.ownerID == ownerID {
            running.task.cancel()
            return
        }
        guard let index = pending.firstIndex(where: { $0.request.requestId == requestId && $0.ownerID == ownerID }) else { return }
        let job = pending.remove(at: index)
        job.onChunk(AIChatLocalRunChunk(requestId: requestId, seq: 0, text: "", done: true, status: .cancelled))
    }

    /// Drops every run the page asked for, without telling it: the page is gone.
    public func cancelAll(ownerID: ObjectIdentifier) {
        pending.removeAll { $0.ownerID == ownerID }
        if let running, running.job.ownerID == ownerID {
            running.task.cancel()
        }
    }

    private func startNextIfIdle() {
        guard running == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.execute(job)
            self.running = nil
            self.startNextIfIdle()
        }
        running = (job, task)
    }

    private func execute(_ job: Job) async {
        var emitter = ChunkEmitter(requestId: job.request.requestId, onChunk: job.onChunk)
        let start = now()
        var lastSent = start
        var firstWordAt: TimeInterval?
        var buffer = ""
        var summary: AIChatLocalModelRunSummary?

        func finish(_ status: AIChatLocalRunChunk.Status, errorCode: AIChatLocalRunChunk.ErrorCode? = nil) {
            let end = now()
            let metrics = AIChatLocalRunChunk.Metrics(timeToFirstWordMs: firstWordAt.map { Self.milliseconds($0 - start) },
                                                      totalMs: Self.milliseconds(end - start),
                                                      loadMs: nil,
                                                      promptTokens: summary?.promptTokens,
                                                      outputTokens: summary?.outputTokens,
                                                      inputTruncated: summary?.inputTruncated ?? false)
            emitter.emit(text: buffer, done: true, status: status, errorCode: errorCode, metrics: metrics)
        }

        do {
            for try await event in engine.run(job.request) {
                switch event {
                case .text(let delta):
                    guard !delta.isEmpty else { continue }
                    let time = now()
                    if firstWordAt == nil {
                        firstWordAt = time
                    }
                    buffer += delta
                    if time - lastSent >= batchInterval {
                        emitter.emit(text: buffer)
                        buffer = ""
                        lastSent = time
                    }
                case .finished(let runSummary):
                    summary = runSummary
                }
            }
            finish(Task.isCancelled ? .cancelled : .ok)
        } catch {
            if Task.isCancelled || error is CancellationError {
                finish(.cancelled)
            } else {
                finish(.error, errorCode: (error as? AIChatLocalModelEngineError)?.code ?? .internal)
            }
        }
    }

    private static func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1000).rounded())
    }
}

private struct ChunkEmitter {
    let requestId: String
    let onChunk: AIChatLocalRunQueue.ChunkHandler
    private var seq = 0

    init(requestId: String, onChunk: @escaping AIChatLocalRunQueue.ChunkHandler) {
        self.requestId = requestId
        self.onChunk = onChunk
    }

    @MainActor
    mutating func emit(text: String,
                       done: Bool? = nil,
                       status: AIChatLocalRunChunk.Status? = nil,
                       errorCode: AIChatLocalRunChunk.ErrorCode? = nil,
                       metrics: AIChatLocalRunChunk.Metrics? = nil) {
        onChunk(AIChatLocalRunChunk(requestId: requestId, seq: seq, text: text, done: done, status: status, errorCode: errorCode, metrics: metrics))
        seq += 1
    }
}
