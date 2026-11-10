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
import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

/// The service's behavior is tested in the AIChat package. These cover the macOS flag wiring.
@MainActor
@Suite("Local model service on macOS")
final class LocalModelServiceTests {

    private let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLocalModels.rawValue: true])
    private let page = RecordingLocalModelPage()

    private lazy var service = AIChatLocalModelService(featureFlagger: featureFlagger,
                                                       storage: MockAIChatPreferencesStorage(),
                                                       engine: StubLocalModelEngine(),
                                                       notificationCenter: NotificationCenter())

    @available(iOS 16, macOS 13, *)
    @Test("The local-models flag turns the feature on and off", .timeLimit(.minutes(1)))
    func flagGatesTheFeature() {
        #expect(service.config()?.state == .notSetUp)

        featureFlagger.featuresStub = [:]

        #expect(service.config() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A flag update reaches open Duck.ai pages", .timeLimit(.minutes(1)))
    func flagUpdateIsPushed() async {
        service.register(page)

        featureFlagger.featuresStub = [:]
        featureFlagger.triggerUpdate()
        for _ in 0..<500 where page.states.isEmpty {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        #expect(page.states == [.unsupported])
    }
}

/// Reports whatever availability the test sets and never produces text.
final class StubLocalModelEngine: AIChatLocalModelEngine {

    let model = AIChatLocalModelInfo(id: "stub-model", name: "Stub Model")
    var availability: AIChatLocalModelAvailability = .available

    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
private final class RecordingLocalModelPage: AIChatLocalModelPushing {

    private(set) var states: [AIChatLocalModelState] = []

    func pushLocalModelState(_ update: AIChatLocalModelStateUpdate) {
        states.append(update.state)
    }

    func pushLocalRunChunk(_ chunk: AIChatLocalRunChunk) {}
}
