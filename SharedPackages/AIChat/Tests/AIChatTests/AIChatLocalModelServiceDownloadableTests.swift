//
//  AIChatLocalModelServiceDownloadableTests.swift
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

/// The service with both engines: Apple Intelligence, and a downloadable model for devices without it.
@MainActor
@Suite("Local model service with a downloadable model")
final class AIChatLocalModelServiceDownloadableTests {

    private let apple = SettableEngine(model: AIChatLocalModelInfo(id: "apple", name: "Apple Intelligence"))
    private let llama = SettableEngine(model: AIChatLocalModelInfo(id: "granite-4.0-1b", name: "Granite 4.0 1B"))
    private let installer = FakeInstaller()
    private let storage = SummariesModelStore()
    private let flagUpdates = PassthroughSubject<Void, Never>()
    private let overrideUpdates = PassthroughSubject<Void, Never>()
    private let page = StatePage()
    private let pixels = PixelRecorder()
    private var isFlagOn = true
    private var engineOverride: AIChatLocalModelEngineKind?

    private lazy var service: AIChatLocalModelService = {
        let service = AIChatLocalModelService(isFeatureFlagOn: { [unowned self] in self.isFlagOn },
                                              featureFlagUpdates: flagUpdates.eraseToAnyPublisher(),
                                              storage: storage,
                                              engine: apple,
                                              downloadableModel: AIChatDownloadableLocalModel(engine: llama, installer: installer),
                                              engineOverride: { [unowned self] in self.engineOverride },
                                              engineOverrideUpdates: overrideUpdates.eraseToAnyPublisher(),
                                              notificationCenter: NotificationCenter(),
                                              instrumentation: pixels)
        service.register(page)
        return service
    }()

    private func request(_ requestId: String = "r1") -> AIChatLocalRunRequest {
        AIChatLocalRunRequest(requestId: requestId, task: .summarize, instruction: "Summarize", content: "Page text")
    }

    // MARK: - Pixels

    /// The pixels only know the cloud and Apple Intelligence, so the downloaded model's state and
    /// runs would be counted as the cloud's.
    @available(iOS 16, macOS 13, *)
    @Test("The downloaded model sends no state or run pixels", .timeLimit(.minutes(1)))
    func downloadedModelSendsNoPixels() throws {
        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))

        _ = try service.startRun(request(), for: page)

        #expect(service.activeEngineKind == .llama)
        #expect(pixels.fired.isEmpty)
    }

    // MARK: - Which engine

    @available(iOS 16, macOS 13, *)
    @Test("Without Apple Intelligence the downloadable model is offered",
          .timeLimit(.minutes(1)),
          arguments: [AIChatLocalModelAvailability.deviceNotEligible, .unsupportedOS, .appleIntelligenceNotEnabled])
    func withoutAppleIntelligenceTheDownloadableModelIsOffered(availability: AIChatLocalModelAvailability) {
        apple.availability = availability

        #expect(service.activeEngineKind == .llama)
        #expect(service.config() == AIChatLocalModelConfig(state: .notSetUp, tasks: [.summarize, .title], model: llama.model))
    }

    @available(iOS 16, macOS 13, *)
    @Test("With Apple Intelligence available it's the one offered", .timeLimit(.minutes(1)))
    func appleIntelligenceIsOfferedWhenAvailable() {
        #expect(service.activeEngineKind == .appleIntelligence)
        #expect(service.config()?.model == apple.model)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An installed downloadable model stays in use when Apple Intelligence is available", .timeLimit(.minutes(1)))
    func installedModelStaysInUse() {
        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))

        #expect(service.activeEngineKind == .llama)
        #expect(service.config()?.state == .ready)
    }

    @available(iOS 16, macOS 13, *)
    @Test("While Apple's own model downloads, Duck.ai is told it's unsupported", .timeLimit(.minutes(1)))
    func appleModelDownloadingIsUnsupported() {
        apple.availability = .modelNotReady

        #expect(service.activeEngineKind == .appleIntelligence)
        #expect(service.config()?.state == .unsupported)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A device llama.cpp can't run on without Apple Intelligence is unsupported", .timeLimit(.minutes(1)))
    func noEngineIsUnsupported() {
        apple.availability = .deviceNotEligible
        llama.availability = .deviceNotEligible

        #expect(service.config()?.state == .unsupported)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The debug override picks the engine and never removes the model", .timeLimit(.minutes(1)))
    func overridePicksTheEngine() {
        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))
        engineOverride = .appleIntelligence
        overrideUpdates.send()

        #expect(service.activeEngineKind == .appleIntelligence)
        #expect(service.config()?.model == apple.model)

        engineOverride = .llama
        overrideUpdates.send()

        #expect(service.config()?.state == .ready)
        #expect(installer.userCalls.isEmpty)
    }

    // MARK: - States

    @available(iOS 16, macOS 13, *)
    @Test("Install states map to what Duck.ai sees", .timeLimit(.minutes(1)))
    func installStatesMapToDuckAIStates() {
        apple.availability = .deviceNotEligible

        installer.state = .downloading(receivedBytes: 10, totalBytes: 100)
        #expect(service.config()?.state == .downloading)

        installer.state = .failed(.diskFull)
        #expect(service.config()?.state == .notSetUp)
        #expect(service.setupError == .diskFull)

        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))
        #expect(service.config()?.state == .ready)
        #expect(service.setupError == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pages hear about the download, and why it failed", .timeLimit(.minutes(1)))
    func pagesHearAboutTheDownload() {
        apple.availability = .deviceNotEligible
        _ = service

        installer.state = .downloading(receivedBytes: 10, totalBytes: 100)
        installer.state = .failed(.network)

        #expect(page.updates == [AIChatLocalModelStateUpdate(state: .downloading),
                                 AIChatLocalModelStateUpdate(state: .notSetUp, errorCode: .network)])
    }

    // MARK: - Access

    @available(iOS 16, macOS 13, *)
    @Test("Install in the prompt starts the download and tells Duck.ai to use the cloud for now", .timeLimit(.minutes(1)))
    func installStartsTheDownload() async throws {
        apple.availability = .deviceNotEligible
        var asked: AIChatLocalModelAccessRequest?

        let result = try await service.requestAccess { request in
            asked = request
            return .allowed
        }

        #expect(asked == .install(llama.model, bytes: installer.spec.bytes))
        #expect(result == .installing)
        #expect(installer.userCalls == [.install])
        #expect(page.updates.last == AIChatLocalModelStateUpdate(state: .downloading))
    }

    @available(iOS 16, macOS 13, *)
    @Test("No Thanks starts nothing", .timeLimit(.minutes(1)))
    func noThanksStartsNothing() async throws {
        apple.availability = .deviceNotEligible

        let result = try await service.requestAccess { _ in .declined }

        #expect(result == .declined)
        #expect(installer.userCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nobody is asked while the model downloads or once it's installed", .timeLimit(.minutes(1)))
    func nobodyIsAskedTwice() async throws {
        apple.availability = .deviceNotEligible
        installer.state = .downloading(receivedBytes: 1, totalBytes: 100)
        var asked = false

        #expect(try await service.requestAccess { _ in asked = true; return .allowed } == .installing)

        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))
        #expect(try await service.requestAccess { _ in asked = true; return .allowed } == .allowed)
        #expect(!asked)
    }

    // MARK: - Runs

    @available(iOS 16, macOS 13, *)
    @Test("Runs go to the active engine and reply with its model", .timeLimit(.minutes(1)))
    func runsGoToTheActiveEngine() async throws {
        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))

        let reply = try service.startRun(request(), for: page)
        await waitUntil { !llama.runRequests.isEmpty }

        #expect(reply.model == llama.model)
        #expect(llama.runRequests == [request()])
        #expect(apple.runRequests.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Switching engines ends a run that already started", .timeLimit(.minutes(1)))
    func switchingEnginesEndsRuns() async throws {
        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))
        storage.pageSummariesModel = .appleIntelligence
        llama.keepsRunning = true
        _ = try service.startRun(request(), for: page)
        await waitUntil { !llama.runRequests.isEmpty }

        engineOverride = .appleIntelligence
        overrideUpdates.send()
        await waitUntil { page.chunks.last?.done == true }

        #expect(page.chunks.last?.status == .cancelled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Uninstall ends runs, frees the model and deletes it", .timeLimit(.minutes(1)))
    func uninstallFreesAndDeletes() {
        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))

        service.uninstallDownloadableModel()

        #expect(llama.unloadCount == 1)
        #expect(installer.userCalls == [.uninstall])
        #expect(service.config()?.state == .notSetUp)
    }

    // MARK: - Flag

    @available(iOS 16, macOS 13, *)
    @Test("The flag pauses a download, and turning it back on continues it", .timeLimit(.minutes(1)))
    func flagPausesAndResumes() async {
        _ = service
        installer.calls = []

        isFlagOn = false
        flagUpdates.send()
        await waitUntil { installer.calls.contains(.pause) }
        isFlagOn = true
        flagUpdates.send()
        await waitUntil { installer.calls.contains(.resumeIfNeeded) }

        #expect(installer.calls.first == .pause)
        #expect(installer.calls.contains(.resumeIfNeeded))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

// MARK: - Fakes

private final class SettableEngine: AIChatLocalModelEngine, AIChatLocalModelUnloading {
    let model: AIChatLocalModelInfo
    var availability: AIChatLocalModelAvailability = .available
    var keepsRunning = false
    private(set) var runRequests: [AIChatLocalRunRequest] = []
    private(set) var unloadCount = 0

    init(model: AIChatLocalModelInfo) {
        self.model = model
    }

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        runRequests.append(request)
        let (stream, continuation) = AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>.makeStream()
        continuation.yield(.text("Summary"))
        if !keepsRunning {
            continuation.finish()
        }
        return stream
    }

    func unloadModel() {
        unloadCount += 1
    }
}

@MainActor
private final class FakeInstaller: AIChatLocalModelInstalling {
    enum Call: Equatable {
        case install, cancel, uninstall, pause, resumeIfNeeded
    }

    let spec = AIChatLocalModelSpec.granite
    private let subject = CurrentValueSubject<AIChatLocalModelInstallState, Never>(.notInstalled)
    var calls: [Call] = []

    /// What the user did, without the pauses and resumes the service makes on every refresh.
    var userCalls: [Call] {
        calls.filter { $0 != .pause && $0 != .resumeIfNeeded }
    }

    var state: AIChatLocalModelInstallState {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var statePublisher: AnyPublisher<AIChatLocalModelInstallState, Never> {
        subject.eraseToAnyPublisher()
    }

    func install() {
        calls.append(.install)
        state = .downloading(receivedBytes: 0, totalBytes: spec.bytes)
    }

    func cancel() {
        calls.append(.cancel)
        state = .notInstalled
    }

    func uninstall() {
        calls.append(.uninstall)
        state = .notInstalled
    }

    func pause() {
        calls.append(.pause)
    }

    func resumeIfNeeded() {
        calls.append(.resumeIfNeeded)
    }
}

private final class SummariesModelStore: AIChatPageSummariesModelStoring {
    private let subject = CurrentValueSubject<AIChatPageSummariesModel, Never>(.duckAI)

    var pageSummariesModel: AIChatPageSummariesModel {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var pageSummariesModelPublisher: AnyPublisher<AIChatPageSummariesModel, Never> {
        subject.eraseToAnyPublisher()
    }
}

@MainActor
private final class StatePage: AIChatLocalModelPushing {
    private(set) var updates: [AIChatLocalModelStateUpdate] = []
    private(set) var chunks: [AIChatLocalRunChunk] = []

    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate) {
        updates.append(update)
    }

    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk) {
        chunks.append(chunk)
    }
}

private final class PixelRecorder: AIChatLocalModelInstrumentation {
    private(set) var fired: [AIChatLocalModelPixel] = []

    func fire(_ pixel: AIChatLocalModelPixel) {
        fired.append(pixel)
    }
}
