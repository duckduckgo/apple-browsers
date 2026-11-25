//
//  AIChatLocalModelServiceTests.swift
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

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Combine
import Foundation
import Testing
@testable import AIChat

@MainActor
@Suite("Local model service")
final class AIChatLocalModelServiceTests {

    private let engine = StubLocalModelEngine()
    private let storage = PageSummariesModelStore()
    private let flag = FlagStub()
    private let notificationCenter = NotificationCenter()
    private let page = RecordingLocalModelPage()
    private let pixels = RecordingLocalModelInstrumentation()

    private lazy var service = AIChatLocalModelService(isFeatureFlagOn: { [flag] in flag.isOn },
                                                       featureFlagUpdates: flag.updates.eraseToAnyPublisher(),
                                                       storage: storage,
                                                       engine: engine,
                                                       notificationCenter: notificationCenter,
                                                       instrumentation: pixels)

    private func request(content: String = "Page text", requestId: String = "r1") -> AIChatLocalRunRequest {
        AIChatLocalRunRequest(requestId: requestId, task: .summarize, instruction: "Summarize", content: content)
    }

    private func postDidBecomeActive() {
#if os(macOS)
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
#else
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
#endif
    }

    // MARK: - State

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off Duck.ai gets no localModel field", .timeLimit(.minutes(1)))
    func flagOffLeavesOutTheField() {
        flag.isOn = false
        storage.pageSummariesModel = .appleIntelligence

        #expect(service.config() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Available but not opted in is not_set_up", .timeLimit(.minutes(1)))
    func availableNotOptedInIsNotSetUp() {
        let config = service.config()

        #expect(config == AIChatLocalModelConfig(state: .notSetUp, tasks: [.summarize, .title], model: engine.model))
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

    @available(iOS 16, macOS 13, *)
    @Test("A run carries on through the script that replaced its page's old one", .timeLimit(.minutes(1)))
    func movedRunStreamsToTheReplacement() async throws {
        storage.pageSummariesModel = .appleIntelligence
        engine.keepsRunning = true
        let replacement = RecordingLocalModelPage()
        _ = try service.startRun(request(), for: page)

        service.moveRuns(from: page, to: replacement)
        service.cancelRun(requestId: "r1", for: page)
        service.cancelRun(requestId: "r1", for: replacement)
        await waitUntil { replacement.chunks.last?.done == true }

        #expect(page.chunks.isEmpty)
        #expect(replacement.chunks.last?.status == .cancelled)
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
    @Test("Turning the model off ends a run that already started", .timeLimit(.minutes(1)))
    func optOutCancelsRuns() async throws {
        storage.pageSummariesModel = .appleIntelligence
        engine.keepsRunning = true
        service.register(page)
        _ = try service.startRun(request(), for: page)

        service.optOut()
        await waitUntil { self.page.chunks.last?.done == true }

        #expect(page.chunks.last?.status == .cancelled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Coming back to the app picks up Apple Intelligence being turned off", .timeLimit(.minutes(1)))
    func appActivationRefreshesAvailability() {
        storage.pageSummariesModel = .appleIntelligence
        service.register(page)

        engine.availability = .appleIntelligenceNotEnabled
        postDidBecomeActive()

        #expect(service.availability == .appleIntelligenceNotEnabled)
        #expect(page.states == [.unsupported])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off tells open pages the model is unsupported", .timeLimit(.minutes(1)))
    func flagOffIsPushedAsUnsupported() async {
        storage.pageSummariesModel = .appleIntelligence
        service.register(page)

        flag.isOn = false
        flag.updates.send()
        await waitUntil { !self.page.states.isEmpty }

        #expect(page.states == [.unsupported])
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off Apple Intelligence is never checked", .timeLimit(.minutes(1)))
    func flagOffNeverChecksAvailability() {
        flag.isOn = false

        postDidBecomeActive()
        _ = service.config()

        #expect(engine.availabilityReads == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag on checks Apple Intelligence and tells open pages", .timeLimit(.minutes(1)))
    func flagOnChecksAvailabilityAndPushes() async {
        flag.isOn = false
        service.register(page)

        flag.isOn = true
        flag.updates.send()
        await waitUntil { !self.page.states.isEmpty }

        #expect(service.availability == .available)
        #expect(page.states == [.notSetUp])
    }

    // MARK: - Access

    @available(iOS 16, macOS 13, *)
    @Test("Turn On in the prompt opts in", .timeLimit(.minutes(1)))
    func allowedOptsIn() async throws {
        let result = try await service.requestAccess { .allowed }

        #expect(result == .allowed)
        #expect(storage.pageSummariesModel == .appleIntelligence)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No Thanks or closing the prompt leaves the model off", .timeLimit(.minutes(1)))
    func declinedLeavesItOff() async throws {
        let result = try await service.requestAccess { .declined }

        #expect(result == .declined)
        #expect(storage.pageSummariesModel == .duckAI)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Someone who already turned it on isn't asked again", .timeLimit(.minutes(1)))
    func optedInIsNotAsked() async throws {
        service.optIn()
        var asked = false

        let result = try await service.requestAccess {
            asked = true
            return .declined
        }

        #expect(result == .allowed)
        #expect(!asked)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without Apple Intelligence the request is refused without asking", .timeLimit(.minutes(1)))
    func refusedWhenUnavailable() async {
        engine.availability = .modelNotReady
        var asked = false

        await #expect(throws: AIChatLocalModelRequestError.unavailable) {
            try await self.service.requestAccess {
                asked = true
                return .allowed
            }
        }
        #expect(!asked)
        #expect(storage.pageSummariesModel == .duckAI)
    }

    // MARK: - Pixels

    @available(iOS 16, macOS 13, *)
    @Test("The state pixel goes out at launch and on every return to the app", .timeLimit(.minutes(1)))
    func statePixelAtLaunchAndOnReturn() {
        _ = service
        postDidBecomeActive()

        let state = AIChatLocalModelPixel.state(selected: .duckAI, state: .notSetUp, availability: .available)
        #expect(pixels.fired == [state, state])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The state pixel shows someone who opted in but lost Apple Intelligence", .timeLimit(.minutes(1)))
    func statePixelForOptedInButUnavailable() {
        storage.pageSummariesModel = .appleIntelligence
        engine.availability = .appleIntelligenceNotEnabled

        _ = service

        #expect(pixels.fired == [.state(selected: .appleIntelligence, state: .unsupported, availability: .appleIntelligenceNotEnabled)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("No state pixel while the flag is off, and one as soon as it turns on", .timeLimit(.minutes(1)))
    func statePixelOnlyWithTheFlag() async {
        flag.isOn = false
        _ = service
        postDidBecomeActive()
        #expect(pixels.fired.isEmpty)

        flag.isOn = true
        flag.updates.send()
        await waitUntil { !self.pixels.fired.isEmpty }

        #expect(pixels.fired == [.state(selected: .duckAI, state: .notSetUp, availability: .available)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("An accepted run sends run_started and a refused one doesn't", .timeLimit(.minutes(1)))
    func runStartedOnlyForAcceptedRuns() throws {
        _ = try? service.startRun(request(), for: page)
        storage.pageSummariesModel = .appleIntelligence
        _ = try? service.startRun(request(content: ""), for: page)

        _ = try service.startRun(request(), for: page)

        #expect(pixels.fired.filter { $0.name == "aichat_local_model_run_started" } == [.runStarted(engine: .appleIntelligence, task: .summarize)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turn On in the prompt saves the choice and sends selected once", .timeLimit(.minutes(1)))
    func promptTurnOnSendsSelected() async throws {
        _ = try await service.requestAccess { .allowed }
        service.select(.appleIntelligence, source: .settings)

        #expect(storage.pageSummariesModel == .appleIntelligence)
        #expect(selectedPixels == [.selected(.appleIntelligence, source: .duckAIPromo)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("No Thanks in the prompt sends no selected", .timeLimit(.minutes(1)))
    func promptNoThanksSendsNoSelected() async throws {
        _ = try await service.requestAccess { .declined }

        #expect(selectedPixels.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Selecting the model that's already chosen saves nothing and sends nothing", .timeLimit(.minutes(1)))
    func selectingTheSameModelSendsNothing() {
        var writes = 0
        let cancellable = storage.pageSummariesModelPublisher.dropFirst().sink { _ in writes += 1 }

        service.select(.duckAI, source: .settings)
        service.select(.appleIntelligence, source: .settings)
        service.select(.appleIntelligence, source: .settings)

        #expect(writes == 1)
        #expect(selectedPixels == [.selected(.appleIntelligence, source: .settings)])
        cancellable.cancel()
    }

    private var selectedPixels: [AIChatLocalModelPixel] {
        pixels.fired.filter { $0.name == "aichat_local_model_selected" }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private final class FlagStub {
    var isOn = true
    let updates = PassthroughSubject<Void, Never>()
}

/// Publishes on every write, during the write, like the UserDefaults-backed stores do.
private final class PageSummariesModelStore: AIChatPageSummariesModelStoring {
    private let subject = CurrentValueSubject<AIChatPageSummariesModel, Never>(.duckAI)

    var pageSummariesModel: AIChatPageSummariesModel {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var pageSummariesModelPublisher: AnyPublisher<AIChatPageSummariesModel, Never> {
        subject.eraseToAnyPublisher()
    }
}

/// Reports whatever availability the test sets and replies with `reply`, one event per string.
private final class StubLocalModelEngine: AIChatLocalModelEngine {

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
    /// Leaves the stream open, like a model that's still writing.
    var keepsRunning = false
    private(set) var runRequests: [AIChatLocalRunRequest] = []

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        runRequests.append(request)
        let (stream, continuation) = AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.makeStream()
        reply.forEach { continuation.yield(.text($0)) }
        if !keepsRunning {
            continuation.finish()
        }
        return stream
    }
}

private final class RecordingLocalModelInstrumentation: AIChatLocalModelInstrumentation {
    private(set) var fired: [AIChatLocalModelPixel] = []

    func fire(_ pixel: AIChatLocalModelPixel) {
        fired.append(pixel)
    }
}

@MainActor
private final class RecordingLocalModelPage: AIChatLocalModelPushing {

    private(set) var states: [AIChatLocalModelState] = []
    private(set) var chunks: [AIChatLocalRunChunk] = []

    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate) {
        states.append(update.state)
    }

    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk) {
        chunks.append(chunk)
    }
}
