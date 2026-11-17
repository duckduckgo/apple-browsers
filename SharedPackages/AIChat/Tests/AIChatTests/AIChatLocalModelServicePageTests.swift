//
//  AIChatLocalModelServicePageTests.swift
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

import Combine
import Foundation
import Testing
@testable import AIChat

/// A page's scripts are replaced while it stays open, for example when content blocking rules
/// change. Runs belong to the page, not the script that started them.
@MainActor
@Suite("Local model runs and the page's scripts")
final class AIChatLocalModelServicePageTests {

    private let engine = HeldEngine()
    private let storage = PageModelStore()
    private let page = NSObject()

    private lazy var service = AIChatLocalModelService(isFeatureFlagOn: { true },
                                                       featureFlagUpdates: Empty().eraseToAnyPublisher(),
                                                       storage: storage,
                                                       engine: engine,
                                                       notificationCenter: NotificationCenter())

    init() {
        storage.pageSummariesModel = .appleIntelligence
    }

    private func request(_ requestId: String = "r1") -> AIChatLocalRunRequest {
        AIChatLocalRunRequest(requestId: requestId, task: .summarize, instruction: "Summarize", content: "Page text")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A run reaches its page through the script that replaced the one that started it", .timeLimit(.minutes(1)))
    func runFollowsThePageToItsNewScript() async throws {
        var oldScript: PageScript? = PageScript(page: page)
        service.register(try #require(oldScript))
        _ = try service.startRun(request(), for: try #require(oldScript))
        await waitUntil { self.engine.isRunning }

        let newScript = PageScript(page: page)
        service.register(newScript)
        let oldChunks = oldScript?.chunks
        oldScript = nil
        engine.finish(with: "Summary")
        await waitUntil { newScript.chunks.last?.done == true }

        #expect(newScript.chunks.map(\.text).joined() == "Summary")
        #expect(newScript.chunks.last?.status == .ok)
        #expect(oldChunks?.isEmpty == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("While the old script is still around, only the newest one gets the chunks", .timeLimit(.minutes(1)))
    func onlyTheNewestScriptGetsChunks() async throws {
        let oldScript = PageScript(page: page)
        service.register(oldScript)
        _ = try service.startRun(request(), for: oldScript)
        await waitUntil { self.engine.isRunning }

        let newScript = PageScript(page: page)
        service.register(newScript)
        engine.finish(with: "Summary")
        await waitUntil { newScript.chunks.last?.done == true }

        #expect(oldScript.chunks.isEmpty)
        #expect(newScript.chunks.map(\.text).joined() == "Summary")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page that's gone ends its runs", .timeLimit(.minutes(1)))
    func goneTabEndsItsRuns() async throws {
        let script = PageScript(page: page)
        service.register(script)
        _ = try service.startRun(request(), for: script)
        await waitUntil { self.engine.isRunning }

        service.cancelRuns(ownerID: script.localModelPageID)
        await waitUntil { self.engine.wasCancelled }

        #expect(engine.wasCancelled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling from the new script stops a run the old script started", .timeLimit(.minutes(1)))
    func newScriptCanCancelTheRun() async throws {
        let oldScript = PageScript(page: page)
        service.register(oldScript)
        _ = try service.startRun(request(), for: oldScript)
        await waitUntil { self.engine.isRunning }

        let newScript = PageScript(page: page)
        service.register(newScript)
        service.cancelRun(requestId: "r1", for: newScript)
        await waitUntil { newScript.chunks.last?.done == true }

        #expect(newScript.chunks.last?.status == .cancelled)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

@MainActor
private final class PageScript: AIChatLocalModelPushing {
    let page: AnyObject
    private(set) var chunks: [AIChatLocalRunChunk] = []

    init(page: AnyObject) {
        self.page = page
    }

    var localModelPage: AnyObject? { page }

    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate) {}

    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk) {
        chunks.append(chunk)
    }
}

/// Keeps a run open until the test finishes it.
private final class HeldEngine: AIChatLocalModelEngine {
    let model = AIChatLocalModelInfo(id: "held", name: "Held")
    let availability = AIChatLocalModelAvailability.available
    private var continuation: AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.Continuation?
    private(set) var wasCancelled = false

    var isRunning: Bool { continuation != nil }

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.makeStream()
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination {
                DispatchQueue.main.async { self?.wasCancelled = true }
            }
        }
        self.continuation = continuation
        return stream
    }

    func finish(with text: String) {
        continuation?.yield(.text(text))
        continuation?.finish()
    }
}

private final class PageModelStore: AIChatPageSummariesModelStoring {
    private let subject = CurrentValueSubject<AIChatPageSummariesModel, Never>(.duckAI)

    var pageSummariesModel: AIChatPageSummariesModel {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var pageSummariesModelPublisher: AnyPublisher<AIChatPageSummariesModel, Never> {
        subject.eraseToAnyPublisher()
    }
}
