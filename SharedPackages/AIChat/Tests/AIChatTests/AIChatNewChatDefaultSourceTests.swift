//
//  AIChatNewChatDefaultSourceTests.swift
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
import AIChat

@Suite("New chat default: source")
struct AIChatNewChatDefaultSourceTests {

    private static let models = ["gpt-6-luna", "gpt-5.6-terra"].map {
        AIChatModel(id: $0, name: $0, provider: .openAI, supportsImageUpload: false,
                    entityHasAccess: true, supportedReasoningEffort: [.none, .low])
    }

    private func makeSource() -> AIChatNewChatDefaultSource {
        let source = AIChatNewChatDefaultSource()
        source.models = Self.models
        source.serverDefault = .model(id: "gpt-5.6-terra", reasoningEffort: .low)
        return source
    }

    @available(iOS 16, macOS 13, *)
    @Test("Selection follows its inputs", .timeLimit(.minutes(1)))
    func selectionFollowsInputs() {
        let source = makeSource()
        #expect(source.selection == AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: .low, origin: .server))

        source.overLimitDefault = AIChatOverLimitNewChatDefault(.model(id: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none),
                                                                resetsAt: .distantFuture)
        #expect(source.selection?.modelId == "gpt-6-luna")

        source.models = []
        #expect(source.selection == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over-limit default lapses once its limit resets", .timeLimit(.minutes(1)))
    func overLimitDefaultLapsesAtReset() {
        var now = Date(timeIntervalSince1970: 1_000)
        let source = AIChatNewChatDefaultSource(now: { now })
        source.models = Self.models
        source.serverDefault = .model(id: "gpt-5.6-terra", reasoningEffort: .low)
        source.overLimitDefault = AIChatOverLimitNewChatDefault(.model(id: "gpt-6-luna", reasoningEffort: nil),
                                                                resetsAt: Date(timeIntervalSince1970: 2_000))
        #expect(source.selection?.modelId == "gpt-6-luna")

        now = Date(timeIntervalSince1970: 2_000)

        #expect(source.selection?.modelId == "gpt-5.6-terra")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Local tier default stands in before models load", .timeLimit(.minutes(1)))
    func localDefaultBeforeModelsLoad() {
        let source = AIChatNewChatDefaultSource()
        source.userTier = .plus

        #expect(source.selectionOrLocalDefaultBeforeModelsLoad?.modelId == "gpt-5.6-terra")
        source.models = Self.models
        source.serverDefault = .model(id: "gpt-6-luna", reasoningEffort: nil)
        #expect(source.selectionOrLocalDefaultBeforeModelsLoad?.modelId == "gpt-6-luna")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nothing stands in before models load while the tier is unknown", .timeLimit(.minutes(1)))
    func noLocalDefaultWhileTierIsUnknown() {
        let source = AIChatNewChatDefaultSource()

        #expect(source.selectionOrLocalDefaultBeforeModelsLoad == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Observed over-limit default applies quietly first, then announces each change", .timeLimit(.minutes(1)))
    func observedOverLimitDefault() {
        let source = makeSource()
        let overLimit = AIChatOverLimitNewChatDefault(.model(id: "gpt-6-luna", reasoningEffort: nil), resetsAt: .distantFuture)
        let defaults = CurrentValueSubject<AIChatOverLimitNewChatDefault, Never>(overLimit)
        var changeCount = 0
        let cancellable = source.overLimitDefaultChanges.sink { changeCount += 1 }

        source.observeOverLimitDefaults(defaults.eraseToAnyPublisher())
        #expect(source.selection?.modelId == "gpt-6-luna")
        #expect(changeCount == 0)

        defaults.send(.notOverLimit)
        defaults.send(.notOverLimit)
        #expect(source.selection?.modelId == "gpt-5.6-terra")
        #expect(changeCount == 1)
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Default effort applies only on the default model", .timeLimit(.minutes(1)))
    func defaultEffortOnDefaultModelOnly() {
        let selection = AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: .low, origin: .server)

        #expect(selection.reasoningEffort(onModelId: "gpt-5.6-terra") == .low)
        #expect(selection.reasoningEffort(onModelId: "gpt-6-luna") == nil)
    }
}
