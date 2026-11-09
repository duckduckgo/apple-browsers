//
//  LocalModelServiceTests.swift
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

import AIChat
import AppKit
import FeatureFlags_macOS
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Local model service")
final class LocalModelServiceTests {

    private let engine = StubLocalModelEngine()
    private let storage = MockAIChatPreferencesStorage()
    private let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLocalModels.rawValue: true])
    private let notificationCenter = NotificationCenter()
    private let page = RecordingLocalModelPage()

    private lazy var service = LocalModelService(featureFlagger: featureFlagger,
                                                 storage: storage,
                                                 engine: engine,
                                                 notificationCenter: notificationCenter)

    private func request(content: String = "Page text", requestId: String = "r1") -> AIChatLocalRunRequest {
        AIChatLocalRunRequest(requestId: requestId, task: .summarize, instruction: "Summarize", content: content)
    }

    // MARK: - State

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off Duck.ai gets no localModel field", .timeLimit(.minutes(1)))
    func flagOffLeavesOutTheField() {
        featureFlagger.featuresStub = [:]
        storage.pageSummariesModel = .appleIntelligence

        #expect(service.config() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Available but not opted in is not_set_up", .timeLimit(.minutes(1)))
    func availableNotOptedInIsNotSetUp() {
        let config = service.config()

        #expect(config == AIChatLocalModelConfig(state: .notSetUp, tasks: [.summarize, .title], model: engine.model, downloadBytes: 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Available and opted in is ready", .timeLimit(.minutes(1)))
    func availableOptedInIsReady() {
        storage.pageSummariesModel = .appleIntelligence

        #expect(service.config()?.state == .ready)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Apple Intelligence that isn't available is unsupported, opted in or not",
          .timeLimit(.minutes(1)),
          arguments: [AIChatLocalModelAvailability.appleIntelligenceNotEnabled, .modelNotReady, .deviceNotEligible, .unsupportedOS],
          [AIChatPageSummariesModel.duckAI, .appleIntelligence])
    func unavailableIsUnsupported(availability: AIChatLocalModelAvailability, choice: AIChatPageSummariesModel) {
        engine.availability = availability
        storage.pageSummariesModel = choice

        #expect(service.config()?.state == .unsupported)
    }

    // MARK: - Runs

    @available(iOS 16, macOS 13, *)
    @Test("A run is refused until the user opts in", .timeLimit(.minutes(1)))
    func runRefusedWithoutOptIn() {
        #expect(throws: AIChatLocalModelRequestError.unavailable) {
            try self.service.startRun(self.request(), for: self.page)
        }
        #expect(engine.runRequests.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A run with nothing to summarize is refused", .timeLimit(.minutes(1)))
    func runRefusedWithoutContent() {
        storage.pageSummariesModel = .appleIntelligence

        #expect(throws: AIChatLocalModelRequestError.invalidArguments) {
            try self.service.startRun(self.request(content: ""), for: self.page)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A run replies with the model and streams to the page that asked", .timeLimit(.minutes(1)))
    func runRepliesAndStreamsToItsPage() async throws {
        storage.pageSummariesModel = .appleIntelligence
        engine.reply = ["Short", " summary"]
        let otherPage = RecordingLocalModelPage()
        service.register(page)
        service.register(otherPage)

        let reply = try service.startRun(request(), for: page)
        await waitUntil { self.page.chunks.last?.done == true }

        #expect(reply == AIChatLocalRunStartReply(model: engine.model))
        #expect(page.chunks.map(\.text).joined() == "Short summary")
        #expect(page.chunks.last?.status == .ok)
        #expect(otherPage.chunks.isEmpty)
    }

    // MARK: - Pushes

    @available(iOS 16, macOS 13, *)
    @Test("Opting in and out tells every open Duck.ai page", .timeLimit(.minutes(1)))
    func optInAndOutArePushed() {
        let otherPage = RecordingLocalModelPage()
        service.register(page)
        service.register(otherPage)

        service.optIn()
        service.optOut()

        #expect(page.states == [.ready, .notSetUp])
        #expect(otherPage.states == [.ready, .notSetUp])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Coming back to the app picks up Apple Intelligence being turned off", .timeLimit(.minutes(1)))
    func appActivationRefreshesAvailability() {
        storage.pageSummariesModel = .appleIntelligence
        service.register(page)

        engine.availability = .appleIntelligenceNotEnabled
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(service.availability == .appleIntelligenceNotEnabled)
        #expect(page.states == [.unsupported])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off tells open pages the model is unsupported", .timeLimit(.minutes(1)))
    func flagOffIsPushedAsUnsupported() async {
        storage.pageSummariesModel = .appleIntelligence
        service.register(page)

        featureFlagger.featuresStub = [:]
        featureFlagger.triggerUpdate()
        await waitUntil { !self.page.states.isEmpty }

        #expect(page.states == [.unsupported])
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off Apple Intelligence is never checked", .timeLimit(.minutes(1)))
    func flagOffNeverChecksAvailability() {
        featureFlagger.featuresStub = [:]

        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        _ = service.config()

        #expect(engine.availabilityReads == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag on checks Apple Intelligence and tells open pages", .timeLimit(.minutes(1)))
    func flagOnChecksAvailabilityAndPushes() async {
        featureFlagger.featuresStub = [:]
        service.register(page)

        featureFlagger.featuresStub = [FeatureFlag.aiChatLocalModels.rawValue: true]
        featureFlagger.triggerUpdate()
        await waitUntil { !self.page.states.isEmpty }

        #expect(service.availability == .available)
        #expect(page.states == [.notSetUp])
    }

    // MARK: - Setup

    @available(iOS 16, macOS 13, *)
    @Test("Setup opts in when Apple Intelligence is available", .timeLimit(.minutes(1)))
    func setUpOptsIn() throws {
        try service.setUp()

        #expect(storage.pageSummariesModel == .appleIntelligence)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Setup is refused when Apple Intelligence isn't available", .timeLimit(.minutes(1)))
    func setUpRefusedWhenUnavailable() {
        engine.availability = .modelNotReady

        #expect(throws: AIChatLocalModelRequestError.unavailable) {
            try self.service.setUp()
        }
        #expect(storage.pageSummariesModel == .duckAI)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

/// Reports whatever availability the test sets and replies with `reply`, one event per string.
final class StubLocalModelEngine: AIChatLocalModelEngine {

    let model = AIChatLocalModelInfo(id: "stub-model", name: "Stub Model")
    private var storedAvailability: AIChatLocalModelAvailability = .available
    private(set) var availabilityReads = 0
    var availability: AIChatLocalModelAvailability {
        get {
            availabilityReads += 1
            return storedAvailability
        }
        set { storedAvailability = newValue }
    }
    var reply: [String] = []
    private(set) var runRequests: [AIChatLocalRunRequest] = []

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        runRequests.append(request)
        let (stream, continuation) = AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.makeStream()
        reply.forEach { continuation.yield(.text($0)) }
        continuation.finish()
        return stream
    }
}

@MainActor
final class RecordingLocalModelPage: AIChatLocalModelPushing {

    private(set) var states: [AIChatLocalModelState] = []
    private(set) var chunks: [AIChatLocalRunChunk] = []

    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate) {
        states.append(update.state)
    }

    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk) {
        chunks.append(chunk)
    }
}
