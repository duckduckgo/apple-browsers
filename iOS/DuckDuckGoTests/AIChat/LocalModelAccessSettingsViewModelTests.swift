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

    private lazy var service = AIChatLocalModelService(isFeatureFlagOn: { [unowned self] in self.isFlagOn },
                                                       featureFlagUpdates: flagUpdates.eraseToAnyPublisher(),
                                                       storage: storage,
                                                       engine: engine,
                                                       notificationCenter: notificationCenter)

    private func makeViewModel() -> LocalModelAccessSettingsViewModel {
        LocalModelAccessSettingsViewModel(service: service)
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

    @available(iOS 16, macOS 13, *)
    @Test("The prompt answers No Thanks when there's no window to show it in", .timeLimit(.minutes(1)))
    func promptWithoutWindowDeclines() async {
        let prompt = LocalModelAccessPrompt()

        let answer = await prompt.ask(in: nil, modelName: "Apple Intelligence")

        #expect(answer == .declined)
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
