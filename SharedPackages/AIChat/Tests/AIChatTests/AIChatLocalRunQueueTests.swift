//
//  AIChatLocalRunQueueTests.swift
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
import Testing
@testable import AIChat

@MainActor
@Suite("Local run queue")
final class AIChatLocalRunQueueTests {

    private let engine = ScriptedLocalModelEngine()
    private let owner = NSObject()
    private var chunks: [AIChatLocalRunChunk] = []

    private func makeQueue(batchInterval: TimeInterval = 0) -> AIChatLocalRunQueue {
        AIChatLocalRunQueue(engine: engine, batchInterval: batchInterval)
    }

    private func enqueue(_ requestId: String, on queue: AIChatLocalRunQueue, owner: AnyObject? = nil) {
        let request = AIChatLocalRunRequest(requestId: requestId, task: .summarize, instruction: "Summarize", content: "Page text")
        queue.enqueue(request, ownerID: ObjectIdentifier(owner ?? self.owner)) { [weak self] chunk in
            self?.chunks.append(chunk)
        }
    }

    private func chunks(for requestId: String) -> [AIChatLocalRunChunk] {
        chunks.filter { $0.requestId == requestId }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Chunks are numbered from 0 and the last one has the status and metrics", .timeLimit(.minutes(1)))
    func chunksAreNumberedAndClosed() async throws {
        let queue = makeQueue()
        enqueue("r1", on: queue)
        await waitUntil { engine.startedRequestIds == ["r1"] }

        engine.send(.text("Hello"), to: "r1")
        engine.send(.text(" world"), to: "r1")
        engine.send(.finished(AIChatLocalModelRunSummary(promptTokens: 120, outputTokens: 4, inputTruncated: true)), to: "r1")
        engine.finish("r1")
        await waitUntil { chunks.last?.done == true }

        #expect(chunks.map(\.seq) == [0, 1, 2])
        #expect(chunks.map(\.text) == ["Hello", " world", ""])
        let last = try #require(chunks.last)
        #expect(last.status == .ok)
        #expect(last.errorCode == nil)
        #expect(last.metrics?.promptTokens == 120)
        #expect(last.metrics?.outputTokens == 4)
        #expect(last.metrics?.inputTruncated == true)
        #expect(last.metrics?.timeToFirstWordMs != nil)
        #expect(queue.isIdle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Text that arrives within the batch interval goes out with the next chunk", .timeLimit(.minutes(1)))
    func textIsBatched() async {
        let queue = makeQueue(batchInterval: 100)
        enqueue("r1", on: queue)
        await waitUntil { engine.startedRequestIds == ["r1"] }

        engine.send(.text("a"), to: "r1")
        engine.send(.text("b"), to: "r1")
        engine.finish("r1")
        await waitUntil { chunks.last?.done == true }

        #expect(chunks.count == 1)
        #expect(chunks.first?.text == "ab")
        #expect(chunks.first?.seq == 0)
        #expect(chunks.first?.status == .ok)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An engine error ends the run with its error code", .timeLimit(.minutes(1)))
    func engineErrorEndsTheRun() async {
        let queue = makeQueue()
        enqueue("r1", on: queue)
        await waitUntil { engine.startedRequestIds == ["r1"] }

        engine.send(.text("Partial"), to: "r1")
        engine.fail("r1", code: .contentFiltered)
        await waitUntil { chunks.last?.done == true }

        #expect(chunks.first?.text == "Partial")
        #expect(chunks.last?.status == .error)
        #expect(chunks.last?.errorCode == .contentFiltered)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling the running request ends it as cancelled", .timeLimit(.minutes(1)))
    func cancellingTheRunningRequest() async {
        let queue = makeQueue()
        enqueue("r1", on: queue)
        await waitUntil { engine.startedRequestIds == ["r1"] }

        queue.cancel(requestId: "r1", ownerID: ObjectIdentifier(owner))
        await waitUntil { chunks.last?.done == true }

        #expect(chunks.last?.status == .cancelled)
        await waitUntil { queue.isIdle }
        #expect(queue.isIdle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Requests run one at a time, in order", .timeLimit(.minutes(1)))
    func requestsRunOneAtATime() async {
        let queue = makeQueue()
        enqueue("r1", on: queue)
        enqueue("r2", on: queue)
        await waitUntil { engine.startedRequestIds == ["r1"] }
        #expect(engine.startedRequestIds == ["r1"])

        engine.finish("r1")
        await waitUntil { engine.startedRequestIds == ["r1", "r2"] }
        #expect(engine.startedRequestIds == ["r1", "r2"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling a waiting request ends it without running it", .timeLimit(.minutes(1)))
    func cancellingAWaitingRequest() async {
        let queue = makeQueue()
        enqueue("r1", on: queue)
        enqueue("r2", on: queue)
        await waitUntil { engine.startedRequestIds == ["r1"] }

        queue.cancel(requestId: "r2", ownerID: ObjectIdentifier(owner))
        #expect(chunks(for: "r2") == [AIChatLocalRunChunk(requestId: "r2", seq: 0, text: "", done: true, status: .cancelled)])

        engine.finish("r1")
        await waitUntil { queue.isIdle }
        #expect(engine.startedRequestIds == ["r1"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Another page can't cancel a run, even with the same request id", .timeLimit(.minutes(1)))
    func cancelFromAnotherPageIsIgnored() async {
        let queue = makeQueue()
        let otherOwner = NSObject()
        enqueue("r1", on: queue)
        enqueue("r2", on: queue)
        await waitUntil { engine.startedRequestIds == ["r1"] }

        queue.cancel(requestId: "r1", ownerID: ObjectIdentifier(otherOwner))
        queue.cancel(requestId: "r2", ownerID: ObjectIdentifier(otherOwner))
        engine.finish("r1")
        await waitUntil { engine.startedRequestIds == ["r1", "r2"] }

        #expect(chunks(for: "r1").last?.status == .ok)
        #expect(chunks(for: "r2").isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page that goes away loses its waiting requests without being told", .timeLimit(.minutes(1)))
    func cancelAllDropsTheOwnersRequests() async {
        let queue = makeQueue()
        let otherOwner = NSObject()
        enqueue("r1", on: queue)
        enqueue("r2", on: queue)
        enqueue("r3", on: queue, owner: otherOwner)
        await waitUntil { engine.startedRequestIds == ["r1"] }

        queue.cancelAll(ownerID: ObjectIdentifier(owner))
        await waitUntil { engine.startedRequestIds == ["r1", "r3"] }

        #expect(chunks(for: "r2").isEmpty)
        #expect(engine.startedRequestIds == ["r1", "r3"])
    }
}

/// Starts a stream per request and lets the test decide what it yields and when it ends.
private final class ScriptedLocalModelEngine: AIChatLocalModelEngine {

    let model = AIChatLocalModelInfo(id: "scripted", name: "Scripted")
    var availability: AIChatLocalModelAvailability = .available
    private(set) var startedRequestIds: [String] = []
    private var continuations: [String: AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.Continuation] = [:]

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.makeStream()
        startedRequestIds.append(request.requestId)
        continuations[request.requestId] = continuation
        return stream
    }

    func send(_ event: AIChatLocalModelEngineEvent, to requestId: String) {
        continuations[requestId]?.yield(event)
    }

    func finish(_ requestId: String) {
        continuations[requestId]?.finish()
    }

    func fail(_ requestId: String, code: AIChatLocalRunChunk.ErrorCode) {
        continuations[requestId]?.finish(throwing: AIChatLocalModelEngineError(code: code))
    }
}
