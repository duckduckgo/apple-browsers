//
//  AIChatNewChatDefaultTests.swift
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
import AIChat

@Suite("New chat default: /models decoding")
struct AIChatNewChatDefaultDecodingTests {

    private func decode(_ newChatDefaultJSON: String?) throws -> AIChatModelsResponse {
        let field = newChatDefaultJSON.map { #", "newChatDefault": \#($0)"# } ?? ""
        let json = #"{"models": []\#(field)}"#
        return try JSONDecoder().decode(AIChatModelsResponse.self, from: Data(json.utf8))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Absent field means the server doesn't send a default yet", .timeLimit(.minutes(1)))
    func absentFieldIsUnavailable() throws {
        #expect(try decode(nil).newChatDefault == .unavailable)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Null means the server deliberately has no default", .timeLimit(.minutes(1)))
    func nullIsNoDefault() throws {
        #expect(try decode("null").newChatDefault == .noDefault)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Model and effort are decoded", .timeLimit(.minutes(1)))
    func modelAndEffort() throws {
        let response = try decode(#"{"modelId": "gpt-6-luna", "reasoningEffort": "none"}"#)
        #expect(response.newChatDefault == .model(id: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Missing effort keeps the model", .timeLimit(.minutes(1)))
    func missingEffort() throws {
        let response = try decode(#"{"modelId": "gpt-6-luna"}"#)
        #expect(response.newChatDefault == .model(id: "gpt-6-luna", reasoningEffort: nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown effort keeps the model and doesn't fail the response", .timeLimit(.minutes(1)))
    func unknownEffort() throws {
        let response = try decode(#"{"modelId": "gpt-5.6-terra", "reasoningEffort": "xhigh"}"#)
        #expect(response.newChatDefault == .model(id: "gpt-5.6-terra", reasoningEffort: nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed default is unavailable and doesn't fail the response", .timeLimit(.minutes(1)),
          arguments: [#"{"reasoningEffort": "none"}"#, #""gpt-6-luna""#, "42", #"{"modelId": 7}"#])
    func malformed(json: String) throws {
        #expect(try decode(json).newChatDefault == .unavailable)
    }
}

@Suite("New chat default: resolution")
struct AIChatNewChatDefaultResolverTests {

    private static func model(_ id: String, access: Bool = true, efforts: [AIChatReasoningEffort] = [.none, .low, .medium]) -> AIChatModel {
        AIChatModel(id: id, name: id, provider: .openAI, supportsImageUpload: false,
                    entityHasAccess: access, supportedReasoningEffort: efforts)
    }

    private let models = [
        model("gpt-6-luna"),
        model("gpt-5.6-terra"),
        model("claude-plus", access: false)
    ]

    private func resolve(_ newChatDefault: AIChatNewChatDefault,
                         overLimit: AIChatNewChatDefault = .unavailable,
                         models: [AIChatModel]? = nil,
                         tier: AIChatUserTier? = .free) -> AIChatNewChatSelection? {
        AIChatNewChatDefaultResolver.resolve([.init(overLimit, origin: .server), .init(newChatDefault, origin: .server)],
                                             models: models ?? self.models,
                                             userTier: tier)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over-limit default wins over the /models default", .timeLimit(.minutes(1)))
    func overLimitDefaultWins() {
        let selection = resolve(.model(id: "gpt-5.6-terra", reasoningEffort: .low),
                                overLimit: .model(id: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none))
        #expect(selection == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none, origin: .server))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unusable over-limit default falls back to the /models default", .timeLimit(.minutes(1)))
    func unusableOverLimitDefault() {
        let selection = resolve(.model(id: "gpt-5.6-terra", reasoningEffort: .low),
                                overLimit: .model(id: "claude-plus", reasoningEffort: nil))
        #expect(selection?.modelId == "gpt-5.6-terra")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Server default is used", .timeLimit(.minutes(1)))
    func serverDefault() {
        let selection = resolve(.model(id: "gpt-5.6-terra", reasoningEffort: .low))
        #expect(selection == AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: .low, origin: .server))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Server default without effort leaves effort to the model", .timeLimit(.minutes(1)))
    func serverDefaultWithoutEffort() {
        let selection = resolve(.model(id: "gpt-5.6-terra", reasoningEffort: nil))
        #expect(selection == AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: nil, origin: .server))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Effort the model doesn't support is dropped", .timeLimit(.minutes(1)))
    func unsupportedEffort() {
        let models = [Self.model("gpt-6-luna", efforts: [])]
        let selection = resolve(.model(id: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none), models: models)
        #expect(selection == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: nil, origin: .server))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown tier skips the local mapping for the first accessible model", .timeLimit(.minutes(1)))
    func unknownTierSkipsLocalMapping() {
        let models = [Self.model("llama"), Self.model("gpt-6-luna"), Self.model("gpt-5.6-terra")]
        let selection = resolve(.unavailable, models: models, tier: nil)
        #expect(selection == AIChatNewChatSelection(modelId: "llama", reasoningEffort: nil, origin: .fallback))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Null default starts on the first accessible model, never the local mapping", .timeLimit(.minutes(1)))
    func noDefault() {
        let models = [Self.model("claude-plus", access: false), Self.model("llama"), Self.model("gpt-5.6-terra")]
        let selection = resolve(.noDefault, models: models, tier: .plus)
        #expect(selection == AIChatNewChatSelection(modelId: "llama", reasoningEffort: nil, origin: .fallback))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unavailable default uses the local mapping for the tier", .timeLimit(.minutes(1)),
          arguments: [(AIChatUserTier.free, "gpt-6-luna"), (.plus, "gpt-5.6-terra"), (.pro, "gpt-5.6-terra"), (.internal, "gpt-5.6-terra")])
    func localMapping(tier: AIChatUserTier, expectedModelId: String) {
        let selection = resolve(.unavailable, tier: tier)
        #expect(selection == AIChatNewChatSelection(modelId: expectedModelId, reasoningEffort: AIChatReasoningEffort.none, origin: .fallback))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Server default not in the list falls back to the local mapping", .timeLimit(.minutes(1)))
    func serverDefaultNotInList() {
        let selection = resolve(.model(id: "gone-model", reasoningEffort: .low), tier: .plus)
        #expect(selection == AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: AIChatReasoningEffort.none, origin: .fallback))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Server default without access falls back to the local mapping", .timeLimit(.minutes(1)))
    func serverDefaultWithoutAccess() {
        let selection = resolve(.model(id: "claude-plus", reasoningEffort: nil))
        #expect(selection == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none, origin: .fallback))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Local mapping model missing falls back to the first accessible model", .timeLimit(.minutes(1)))
    func localMappingMissing() {
        let models = [Self.model("claude-plus", access: false), Self.model("llama")]
        let selection = resolve(.unavailable, models: models)
        #expect(selection == AIChatNewChatSelection(modelId: "llama", reasoningEffort: nil, origin: .fallback))
    }

    @available(iOS 16, macOS 13, *)
    @Test("No accessible model resolves to nothing", .timeLimit(.minutes(1)))
    func nothingAccessible() {
        #expect(resolve(.noDefault, models: [Self.model("claude-plus", access: false)]) == nil)
        #expect(resolve(.unavailable, models: []) == nil)
    }
}

@Suite("New chat default: usage-limits snapshot")
struct AIChatOverLimitNewChatDefaultSnapshotTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(notice: Bool, newChatDefault: String) -> DuckAiUsageSnapshot {
        let noticeJSON = notice
            ? #""notice": {"id": "weeklyReachedDegraded", "window": "weekly", "resetsAt": "2030-01-01T00:00:00Z"}, "#
            : ""
        return DuckAiUsageSnapshot.make(entryValue: "{\(noticeJSON)\"newChatDefault\": \(newChatDefault)}", now: now)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over-limit default is read next to a live notice", .timeLimit(.minutes(1)))
    func readWithNotice() {
        let value = snapshot(notice: true, newChatDefault: #"{"modelId": "gpt-6-luna", "reasoningEffort": "none"}"#)
        #expect(value.overLimitNewChatDefault.newChatDefault(at: now) == .model(id: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over-limit default lapses when the notice's limit resets", .timeLimit(.minutes(1)))
    func lapsesAtNoticeReset() {
        let value = snapshot(notice: true, newChatDefault: #"{"modelId": "gpt-6-luna"}"#)
        let resetsAt = ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z")!

        #expect(value.overLimitNewChatDefault.newChatDefault(at: resetsAt.addingTimeInterval(-1)) == .model(id: "gpt-6-luna", reasoningEffort: nil))
        #expect(value.overLimitNewChatDefault.newChatDefault(at: resetsAt) == .unavailable)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over-limit default is ignored without a live notice", .timeLimit(.minutes(1)))
    func ignoredWithoutNotice() {
        let value = snapshot(notice: false, newChatDefault: #"{"modelId": "gpt-6-luna"}"#)
        #expect(value.overLimitNewChatDefault.newChatDefault(at: now) == .unavailable)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Null over-limit default leaves the regular default", .timeLimit(.minutes(1)))
    func nullLeavesRegularDefault() {
        let value = snapshot(notice: true, newChatDefault: "null")
        #expect(value.overLimitNewChatDefault.newChatDefault(at: now) == .unavailable)
    }
}
