//
//  LocalModelAccessPreferencesTests.swift
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
import FeatureFlags_macOS
import Foundation
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Local Model Access setting")
final class LocalModelAccessPreferencesTests {

    private let engine = StubLocalModelEngine()
    private let storage = MockAIChatPreferencesStorage()
    private let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLocalModels.rawValue: true])
    private var confirms = true
    private var confirmations = 0
    private var redraws = 0
    private let pixelFiring = PixelKitMock()

    private lazy var service = AIChatLocalModelService(featureFlagger: featureFlagger,
                                                       storage: storage,
                                                       engine: engine,
                                                       notificationCenter: NotificationCenter(),
                                                       instrumentation: LocalModelPixelInstrumentation(pixelFiring: pixelFiring))

    private func makePreferences() -> AIChatPreferences {
        AIChatPreferences(storage: storage,
                          aiChatMenuConfiguration: MockAIChatConfig(),
                          windowControllersManager: WindowControllersManagerMock(),
                          featureFlagger: featureFlagger,
                          localModelService: service,
                          confirmLocalModelTurnOn: { [weak self] in
                              guard let self else { return false }
                              confirmations += 1
                              return confirms
                          })
    }

    private func selectedInSettings(_ model: AIChatPageSummariesModel) -> ExpectedFireCall {
        ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: .selected(model, source: .settings)), frequency: .standard)
    }

    /// The service also sends its daily state, which these tests don't look at.
    private var selectedPixels: [ExpectedFireCall] {
        pixelFiring.actualFireCalls.filter { $0.pixel.name == "aichat_local_model_selected_macos" }
    }

    @available(iOS 16, macOS 13, *)
    @Test("The section shows only with the flag on", .timeLimit(.minutes(1)))
    func visibleOnlyWithTheFlag() {
        let preferences = makePreferences()
        #expect(preferences.shouldShowLocalModelAccess)

        featureFlagger.featuresStub = [:]
        #expect(!preferences.shouldShowLocalModelAccess)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The section shows only where Apple Intelligence is ready",
          .timeLimit(.minutes(1)),
          arguments: [
            (AIChatLocalModelAvailability.available, true),
            (.appleIntelligenceNotEnabled, false),
            (.modelNotReady, false),
            (.deviceNotEligible, false),
            (.unsupportedOS, false)
          ])
    func visibleOnlyWhereAppleIntelligenceIsReady(availability: AIChatLocalModelAvailability, isShown: Bool) {
        engine.availability = availability

        #expect(makePreferences().shouldShowLocalModelAccess == isShown)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The pane redraws when Apple Intelligence is turned on in System Settings", .timeLimit(.minutes(1)))
    func redrawsOnAvailabilityChanges() async {
        engine.availability = .appleIntelligenceNotEnabled
        let preferences = makePreferences()
        preferences.observeLocalModelAvailability()
        #expect(!preferences.shouldShowLocalModelAccess)
        let cancellable = preferences.objectWillChange.sink { [weak self] in self?.redraws += 1 }

        engine.availability = .available
        service.refreshAvailability()
        await waitUntil { self.redraws > 0 }

        #expect(redraws > 0)
        #expect(preferences.shouldShowLocalModelAccess)
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turn On asks first, then turns the model on", .timeLimit(.minutes(1)))
    func turnOnAfterConfirming() async {
        let preferences = makePreferences()

        await preferences.turnOnLocalModel()

        #expect(confirmations == 1)
        #expect(preferences.isLocalModelOn)
        #expect(storage.pageSummariesModel == .appleIntelligence)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancel leaves the model off", .timeLimit(.minutes(1)))
    func cancelLeavesItOff() async {
        confirms = false
        let preferences = makePreferences()

        await preferences.turnOnLocalModel()

        #expect(!preferences.isLocalModelOn)
        #expect(storage.pageSummariesModel == .duckAI)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turn Off turns the model off without asking", .timeLimit(.minutes(1)))
    func turnOffWithoutAsking() {
        storage.pageSummariesModel = .appleIntelligence
        let preferences = makePreferences()
        #expect(preferences.isLocalModelOn)

        preferences.turnOffLocalModel()

        #expect(confirmations == 0)
        #expect(storage.pageSummariesModel == .duckAI)
    }

    // MARK: - Pixels

    @available(iOS 16, macOS 13, *)
    @Test("Turn On and Turn Off send selected with the settings source", .timeLimit(.minutes(1)))
    func settingsSendsSelected() async {
        let preferences = makePreferences()

        await preferences.turnOnLocalModel()
        preferences.turnOffLocalModel()

        #expect(selectedPixels == [selectedInSettings(.appleIntelligence), selectedInSettings(.duckAI)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancel, or Turn Off while already off, sends nothing", .timeLimit(.minutes(1)))
    func noChangeSendsNothing() async {
        confirms = false
        let preferences = makePreferences()

        await preferences.turnOnLocalModel()
        preferences.turnOffLocalModel()

        #expect(selectedPixels.isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

/// Settings on a Mac that gets the downloadable model.
@MainActor
@Suite("On-Device Models setting with a downloadable model")
final class DownloadableLocalModelPreferencesTests {

    private let apple = StubLocalModelEngine()
    private let llama = UnloadableStubEngine()
    private let installer = RecordingInstaller()
    private let storage = MockAIChatPreferencesStorage()
    private let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLocalModels.rawValue: true])

    private lazy var service = AIChatLocalModelService(featureFlagger: featureFlagger,
                                                       storage: storage,
                                                       engine: apple,
                                                       downloadableModel: AIChatDownloadableLocalModel(engine: llama, installer: installer),
                                                       engineOverride: LocalModelEngineOverridePersistor(keyValueStore: InMemoryKeyValueStore(),
                                                                                                         notificationCenter: NotificationCenter()),
                                                       notificationCenter: NotificationCenter())

    private func makePreferences() -> AIChatPreferences {
        AIChatPreferences(storage: storage,
                          aiChatMenuConfiguration: MockAIChatConfig(),
                          windowControllersManager: WindowControllersManagerMock(),
                          featureFlagger: featureFlagger,
                          localModelService: service)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without Apple Intelligence the section shows the downloadable model", .timeLimit(.minutes(1)))
    func withoutAppleIntelligenceShowsTheDownloadableModel() {
        apple.availability = .deviceNotEligible
        let preferences = makePreferences()

        #expect(preferences.shouldShowLocalModelAccess)
        #expect(preferences.downloadableModelState == .notInstalled)
        #expect(preferences.downloadableModelBytes == AIChatLocalModelSpec.granite.bytes)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With Apple Intelligence ready the section shows Apple Intelligence", .timeLimit(.minutes(1)))
    func withAppleIntelligenceShowsAppleIntelligence() {
        let preferences = makePreferences()

        #expect(preferences.shouldShowLocalModelAccess)
        #expect(preferences.downloadableModelState == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Install, Cancel and Uninstall reach the downloader", .timeLimit(.minutes(1)))
    func buttonsReachTheDownloader() {
        apple.availability = .deviceNotEligible
        let preferences = makePreferences()

        preferences.installDownloadableModel()
        #expect(preferences.downloadableModelState == .downloading(receivedBytes: 0, totalBytes: AIChatLocalModelSpec.granite.bytes))
        preferences.cancelDownloadableModelInstall()
        #expect(preferences.downloadableModelState == .notInstalled)
        installer.state = .installed(URL(fileURLWithPath: "/m.gguf"))
        preferences.uninstallDownloadableModel()

        #expect(installer.userCalls == ["install", "cancel", "uninstall"])
        #expect(llama.unloadCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The debug override keeps its choice and forgets Automatic", .timeLimit(.minutes(1)))
    func overrideIsStored() {
        let store = InMemoryKeyValueStore()
        let notificationCenter = NotificationCenter()
        let persistor = LocalModelEngineOverridePersistor(keyValueStore: store, notificationCenter: notificationCenter)
        var updates = 0
        let cancellable = persistor.updates.sink { updates += 1 }

        persistor.current = .llama
        #expect(persistor.current == .llama)
        #expect(persistor.current.engineKind == .llama)

        persistor.current = .automatic
        #expect(store.object(forKey: LocalModelEngineOverridePersistor.key) == nil)
        #expect(persistor.current.engineKind == nil)
        #expect(updates == 2)
        cancellable.cancel()
    }
}

private final class UnloadableStubEngine: AIChatLocalModelEngine, AIChatLocalModelUnloading {
    let model = AIChatLocalModelSpec.granite.info
    var availability: AIChatLocalModelAvailability = .available
    private(set) var unloadCount = 0

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func unloadModel() {
        unloadCount += 1
    }
}

@MainActor
private final class RecordingInstaller: AIChatLocalModelInstalling {
    let spec = AIChatLocalModelSpec.granite
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
