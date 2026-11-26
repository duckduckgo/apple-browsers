//
//  LocalModelAccessSettingsViewModelTests.swift
//  DuckDuckGo
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
import Combine
import Foundation
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Local Model Access setting")
final class LocalModelAccessSettingsViewModelTests {

    private let engine = StubLocalModelEngine()
    private let storage = InMemoryPageSummariesModelStore()
    private let flagUpdates = PassthroughSubject<Void, Never>()
    private let notificationCenter = NotificationCenter()
    private var isFlagOn = true
    private let pixelFiring = PixelKitMock()

    private lazy var service = AIChatLocalModelService(isFeatureFlagOn: { [unowned self] in self.isFlagOn },
                                                       featureFlagUpdates: flagUpdates.eraseToAnyPublisher(),
                                                       storage: storage,
                                                       engine: engine,
                                                       notificationCenter: notificationCenter,
                                                       instrumentation: LocalModelPixelInstrumentation(pixelFiring: pixelFiring))

    private func makeViewModel() -> LocalModelAccessSettingsViewModel {
        LocalModelAccessSettingsViewModel(service: service)
    }

    private let llama = UnloadableStubEngine()
    private let installer = RecordingInstaller()

    private lazy var serviceWithDownloadableModel = AIChatLocalModelService(isFeatureFlagOn: { true },
                                                                           featureFlagUpdates: flagUpdates.eraseToAnyPublisher(),
                                                                           storage: storage,
                                                                           engine: engine,
                                                                           downloadableModel: AIChatDownloadableLocalModel(engine: llama, installer: installer),
                                                                           notificationCenter: notificationCenter)

    private func selectedInSettings(_ model: AIChatPageSummariesModel) -> ExpectedFireCall {
        ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: .selected(model, source: .settings)), frequency: .standard)
    }

    /// The service also sends its daily state, which these tests don't look at.
    private var selectedPixels: [ExpectedFireCall] {
        pixelFiring.actualFireCalls.filter { $0.pixel.name == "aichat_local_model_selected" }
    }

    @available(iOS 16, macOS 13, *)
    @Test("The section shows only with the flag on, and follows the flag while Settings is open", .timeLimit(.minutes(1)))
    func flagDecidesVisibility() async {
        isFlagOn = false
        let viewModel = makeViewModel()
        #expect(!viewModel.isAvailable)

        isFlagOn = true
        flagUpdates.send()
        await waitUntil { viewModel.isAvailable }
        #expect(viewModel.isAvailable)

        isFlagOn = false
        flagUpdates.send()
        await waitUntil { !viewModel.isAvailable }
        #expect(!viewModel.isAvailable)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("The section shows only where Apple Intelligence is ready",
          .timeLimit(.minutes(1)),
          arguments: [AIChatLocalModelAvailability.appleIntelligenceNotEnabled, .modelNotReady, .deviceNotEligible, .unsupportedOS])
    func hiddenUnlessReady(availability: AIChatLocalModelAvailability) {
        engine.availability = availability

        #expect(!makeViewModel().isAvailable)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The section appears when Apple Intelligence is turned on while Settings is open", .timeLimit(.minutes(1)))
    func followsAvailability() {
        engine.availability = .appleIntelligenceNotEnabled
        let viewModel = makeViewModel()
        #expect(!viewModel.isAvailable)

        engine.availability = .available
        viewModel.refresh()

        #expect(viewModel.isAvailable)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Switching on asks first, then turns the model on", .timeLimit(.minutes(1)))
    func switchingOnAsksFirst() {
        let viewModel = makeViewModel()

        viewModel.isOnBinding.wrappedValue = true
        #expect(viewModel.isConfirmingTurnOn)
        #expect(storage.pageSummariesModel == .duckAI)

        viewModel.confirmTurnOn()
        #expect(storage.pageSummariesModel == .appleIntelligence)
        #expect(!viewModel.isConfirmingTurnOn)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancel leaves the model off and flips the switch back", .timeLimit(.minutes(1)))
    func cancelLeavesItOff() {
        let viewModel = makeViewModel()

        viewModel.isOnBinding.wrappedValue = true
        #expect(viewModel.isOnBinding.wrappedValue)
        viewModel.cancelTurnOn()

        #expect(storage.pageSummariesModel == .duckAI)
        #expect(!viewModel.isOnBinding.wrappedValue)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Switching off turns the model off without asking", .timeLimit(.minutes(1)))
    func switchingOffDoesNotAsk() {
        storage.pageSummariesModel = .appleIntelligence
        let viewModel = makeViewModel()
        #expect(viewModel.isOn)

        viewModel.isOnBinding.wrappedValue = false

        #expect(storage.pageSummariesModel == .duckAI)
        #expect(!viewModel.isConfirmingTurnOn)
    }

    // MARK: - Downloadable model

    @available(iOS 16, macOS 13, *)
    @Test("Without Apple Intelligence, the section shows the downloadable model", .timeLimit(.minutes(1)))
    func showsTheDownloadableModelWithoutAppleIntelligence() {
        engine.availability = .deviceNotEligible

        let viewModel = LocalModelAccessSettingsViewModel(service: serviceWithDownloadableModel)

        #expect(viewModel.isAvailable)
        #expect(viewModel.downloadableModelState == .notInstalled)
        #expect(viewModel.modelName == llama.model.name)
        #expect(viewModel.downloadableModelBytes == installer.spec.bytes)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Where Apple Intelligence is ready, the section shows its switch", .timeLimit(.minutes(1)))
    func showsTheSwitchWithAppleIntelligence() {
        engine.availability = .available

        let viewModel = LocalModelAccessSettingsViewModel(service: serviceWithDownloadableModel)

        #expect(viewModel.isAvailable)
        #expect(viewModel.downloadableModelState == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Install, Cancel and Uninstall reach the installer, and Uninstall frees the model", .timeLimit(.minutes(1)))
    func rowActionsReachTheInstaller() {
        engine.availability = .deviceNotEligible
        let viewModel = LocalModelAccessSettingsViewModel(service: serviceWithDownloadableModel)

        viewModel.installDownloadableModel()
        viewModel.cancelDownloadableModelInstall()
        viewModel.uninstallDownloadableModel()

        #expect(installer.userCalls == ["install", "cancel", "uninstall"])
        #expect(llama.unloadCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Download progress reaches the row", .timeLimit(.minutes(1)))
    func progressReachesTheRow() async {
        engine.availability = .deviceNotEligible
        let viewModel = LocalModelAccessSettingsViewModel(service: serviceWithDownloadableModel)

        installer.state = .downloading(receivedBytes: 500, totalBytes: 1_000)

        await waitUntil { viewModel.downloadableModelState == .downloading(receivedBytes: 500, totalBytes: 1_000) }
        #expect(viewModel.downloadableModelState == .downloading(receivedBytes: 500, totalBytes: 1_000))
    }

    // MARK: - Prompt

    @available(iOS 16, macOS 13, *)
    @Test("The prompt answers No Thanks when there's no window to show it in, and counts no offer", .timeLimit(.minutes(1)))
    func promptWithoutWindowDeclines() async {
        let prompt = LocalModelAccessPrompt(instrumentation: LocalModelPixelInstrumentation(pixelFiring: pixelFiring))

        let answer = await prompt.ask(in: nil, request: .connect(AIChatLocalModelInfo(id: "apple", name: "Apple Intelligence")))

        #expect(answer == .declined)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - Pixels

    @available(iOS 16, macOS 13, *)
    @Test("Turning it on and off in Settings sends selected with the settings source", .timeLimit(.minutes(1)))
    func settingsSendsSelected() {
        let viewModel = makeViewModel()

        viewModel.isOnBinding.wrappedValue = true
        viewModel.confirmTurnOn()
        viewModel.isOnBinding.wrappedValue = false

        #expect(selectedPixels == [selectedInSettings(.appleIntelligence), selectedInSettings(.duckAI)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancel in the confirmation sends nothing", .timeLimit(.minutes(1)))
    func cancelSendsNothing() {
        let viewModel = makeViewModel()

        viewModel.isOnBinding.wrappedValue = true
        viewModel.cancelTurnOn()

        #expect(selectedPixels.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each local-model pixel goes out under AIChat's name, parameters and frequency", .timeLimit(.minutes(1)))
    func instrumentationUsesTheSharedDefinition() {
        let instrumentation = LocalModelPixelInstrumentation(pixelFiring: pixelFiring)
        let pixels: [AIChatLocalModelPixel] = [
            .state(selected: .appleIntelligence, state: .ready, availability: .available),
            .promoShown,
            .promoClosed,
            .selected(.appleIntelligence, source: .duckAIPromo),
            .runStarted(engine: .appleIntelligence, task: .summarize)
        ]

        pixels.forEach(instrumentation.fire)

        #expect(pixelFiring.actualFireCalls == [
            ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: pixels[0]), frequency: .daily),
            ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: pixels[1]), frequency: .dailyAndCount),
            ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: pixels[2]), frequency: .dailyAndCount),
            ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: pixels[3]), frequency: .standard),
            ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: pixels[4]), frequency: .daily)
        ])
        #expect(pixelFiring.actualFireCalls.map(\.pixel.name) == [
            "aichat_local_model_state",
            "aichat_local_model_promo_shown",
            "aichat_local_model_promo_closed",
            "aichat_local_model_selected",
            "aichat_local_model_run_started"
        ])
    }
}

private final class StubLocalModelEngine: AIChatLocalModelEngine {
    let model = AIChatLocalModelInfo(id: "stub", name: "Stub")
    var availability: AIChatLocalModelAvailability = .available

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Publishes during the write, like the real store.
private final class InMemoryPageSummariesModelStore: AIChatPageSummariesModelStoring {
    private let subject = CurrentValueSubject<AIChatPageSummariesModel, Never>(.duckAI)

    var pageSummariesModel: AIChatPageSummariesModel {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var pageSummariesModelPublisher: AnyPublisher<AIChatPageSummariesModel, Never> {
        subject.eraseToAnyPublisher()
    }
}

private final class UnloadableStubEngine: AIChatLocalModelEngine, AIChatLocalModelUnloading {
    let model = AIChatLocalModelSpec.gemma4E2B.info
    var availability: AIChatLocalModelAvailability = .available
    private(set) var unloadCount = 0

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func unloadModel() {
        unloadCount += 1
    }
}

private final class RecordingInstaller: AIChatLocalModelInstalling {
    let spec = AIChatLocalModelSpec.gemma4E2B
    let isActive = false
    private let subject = CurrentValueSubject<AIChatLocalModelInstallState, Never>(.notInstalled)
    private(set) var userCalls: [String] = []

    var state: AIChatLocalModelInstallState {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var statePublisher: AnyPublisher<AIChatLocalModelInstallState, Never> {
        subject.eraseToAnyPublisher()
    }

    func install() {
        userCalls.append("install")
        state = .downloading(receivedBytes: 0, totalBytes: spec.bytes)
    }

    func cancel() {
        userCalls.append("cancel")
        state = .notInstalled
    }

    func uninstall() {
        userCalls.append("uninstall")
        state = .notInstalled
    }

    func pause() {}
    func resumeIfNeeded() {}
}
