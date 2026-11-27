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
        let cancellable = source.defaultChanges.sink { changeCount += 1 }

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

@Suite("New chat default: user default model")
struct AIChatNewChatUserDefaultSourceTests {

    private final class StubUserDefaultModel: AIChatUserDefaultModelProviding {
        var modelId: String?
        let changesSubject = PassthroughSubject<Void, Never>()
        var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

        init(_ modelId: String?) {
            self.modelId = modelId
        }
    }

    private static func model(_ id: String, access: Bool = true) -> AIChatModel {
        AIChatModel(id: id, name: id, provider: .openAI, supportsImageUpload: false,
                    entityHasAccess: access, supportedReasoningEffort: [.none, .low, .medium])
    }

    private static let overLimit = AIChatOverLimitNewChatDefault(.model(id: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none),
                                                                 resetsAt: Date(timeIntervalSince1970: 2_000))

    private func makeSource(userDefault: StubUserDefaultModel?,
                            serverDefault: AIChatNewChatDefault = .model(id: "gpt-5.6-terra", reasoningEffort: .low),
                            overLimit: AIChatOverLimitNewChatDefault = .notOverLimit,
                            now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }) -> AIChatNewChatDefaultSource {
        let source = AIChatNewChatDefaultSource(now: now)
        source.update(models: [Self.model("gpt-6-luna"), Self.model("gpt-5.6-terra"), Self.model("claude-haiku"), Self.model("claude-pro", access: false)],
                      serverDefault: serverDefault)
        source.userTier = .free
        source.overLimitDefault = overLimit
        source.observeUserDefaultModel(userDefault, receivingUpdatesOn: ImmediateScheduler.shared)
        return source
    }

    private static let overLimitWithoutModel = AIChatOverLimitNewChatDefault(.unavailable, resetsAt: Date(timeIntervalSince1970: 2_000))

    @available(iOS 16, macOS 13, *)
    @Test("User default wins over the /models default, on the model's own effort", .timeLimit(.minutes(1)))
    func userDefaultWins() {
        let source = makeSource(userDefault: StubUserDefaultModel("claude-haiku"))
        #expect(source.selection == AIChatNewChatSelection(modelId: "claude-haiku", reasoningEffort: nil, origin: .user))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each resolve reads the user default afresh", .timeLimit(.minutes(1)))
    func userDefaultReadLive() {
        let userDefault = StubUserDefaultModel(nil)
        let source = makeSource(userDefault: userDefault)
        #expect(source.selection?.modelId == "gpt-5.6-terra")

        userDefault.modelId = "claude-haiku"

        #expect(source.selection?.modelId == "claude-haiku")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A user default the user can't use falls through to the /models default", .timeLimit(.minutes(1)),
          arguments: ["claude-pro", "gone-model"])
    func unusableUserDefault(userDefault: String) {
        let source = makeSource(userDefault: StubUserDefaultModel(userDefault))
        #expect(source.selection == AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: .low, origin: .userDefaultUnavailable))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unusable user default without a /models default falls through to the local tier default", .timeLimit(.minutes(1)))
    func unusableUserDefaultLocalDefault() {
        let source = makeSource(userDefault: StubUserDefaultModel("claude-pro"), serverDefault: .unavailable)
        #expect(source.selection == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none,
                                                           origin: .userDefaultUnavailable))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over the limit, the over-limit default wins over a user default it doesn't allow", .timeLimit(.minutes(1)))
    func overLimitBeatsUserDefault() {
        let source = makeSource(userDefault: StubUserDefaultModel("claude-haiku"), overLimit: Self.overLimit)
        #expect(source.selection == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none,
                                                           origin: .userDefaultUnavailable))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over the limit, a user default the limit allows is kept, on the limit's effort", .timeLimit(.minutes(1)))
    func overLimitKeepsAllowedUserDefault() {
        let source = makeSource(userDefault: StubUserDefaultModel("gpt-6-luna"), overLimit: Self.overLimit)
        #expect(source.selection == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none, origin: .user))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A user default on the /models default's model takes its effort", .timeLimit(.minutes(1)))
    func userDefaultTakesServerEffort() {
        let source = makeSource(userDefault: StubUserDefaultModel("gpt-5.6-terra"))
        #expect(source.selection == AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: .low, origin: .user))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Over the limit without a named model, the user default is passed over", .timeLimit(.minutes(1)))
    func overLimitWithoutModelPassesOverUserDefault() {
        let source = makeSource(userDefault: StubUserDefaultModel("claude-haiku"), overLimit: Self.overLimitWithoutModel)
        #expect(source.selection == AIChatNewChatSelection(modelId: "gpt-5.6-terra", reasoningEffort: .low, origin: .userDefaultUnavailable))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before models load, a user default the tier may not include leaves the local tier default", .timeLimit(.minutes(1)))
    func unverifiedUserDefaultBeforeModelsLoad() {
        let source = AIChatNewChatDefaultSource()
        source.userTier = .free
        source.observeUserDefaultModel(StubUserDefaultModel("gpt-5.6-terra"), receivingUpdatesOn: ImmediateScheduler.shared)

        #expect(source.selectionOrLocalDefaultBeforeModelsLoad == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none, origin: .fallback))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before models load, a user default that is the local tier default applies as the user default", .timeLimit(.minutes(1)))
    func tierDefaultUserDefaultBeforeModelsLoad() {
        let source = AIChatNewChatDefaultSource()
        source.userTier = .free
        source.observeUserDefaultModel(StubUserDefaultModel("gpt-6-luna"), receivingUpdatesOn: ImmediateScheduler.shared)

        #expect(source.selectionOrLocalDefaultBeforeModelsLoad == AIChatNewChatSelection(modelId: "gpt-6-luna", reasoningEffort: AIChatReasoningEffort.none, origin: .user))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before models load and while the tier is unknown, a user default doesn't pick a model", .timeLimit(.minutes(1)))
    func userDefaultBeforeTierAndModelsLoad() {
        let source = AIChatNewChatDefaultSource()
        source.observeUserDefaultModel(StubUserDefaultModel("claude-haiku"), receivingUpdatesOn: ImmediateScheduler.shared)

        #expect(source.selectionOrLocalDefaultBeforeModelsLoad == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before models load, a user default the limit passes over leaves the local tier default", .timeLimit(.minutes(1)))
    func passedOverUserDefaultBeforeModelsLoad() {
        let source = AIChatNewChatDefaultSource(now: { Date(timeIntervalSince1970: 1_000) })
        source.userTier = .free
        source.overLimitDefault = Self.overLimitWithoutModel
        source.observeUserDefaultModel(StubUserDefaultModel("claude-haiku"), receivingUpdatesOn: ImmediateScheduler.shared)

        #expect(source.selectionOrLocalDefaultBeforeModelsLoad?.modelId == "gpt-6-luna")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once the limit resets, the user default applies again", .timeLimit(.minutes(1)))
    func userDefaultAfterLimitResets() {
        let source = makeSource(userDefault: StubUserDefaultModel("claude-haiku"), overLimit: Self.overLimit,
                                now: { Date(timeIntervalSince1970: 2_000) })
        #expect(source.selection?.origin == .user)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without a user default nothing is reported unavailable", .timeLimit(.minutes(1)))
    func noUserDefault() {
        #expect(makeSource(userDefault: StubUserDefaultModel(nil)).selection?.origin == .server)
        #expect(makeSource(userDefault: nil).selection?.origin == .server)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A changed user default is announced", .timeLimit(.minutes(1)))
    func announcesUserDefaultChanges() {
        let userDefault = StubUserDefaultModel(nil)
        let source = makeSource(userDefault: userDefault)
        var changeCount = 0
        let cancellable = source.defaultChanges.sink { changeCount += 1 }

        userDefault.changesSubject.send()

        #expect(changeCount == 1)
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("User default changes are announced on the given scheduler", .timeLimit(.minutes(1)))
    func announcesOnScheduler() async {
        let queue = DispatchQueue(label: "user-default-announcements")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())
        let userDefault = StubUserDefaultModel(nil)
        let source = AIChatNewChatDefaultSource()
        source.observeUserDefaultModel(userDefault, receivingUpdatesOn: queue)
        var cancellable: AnyCancellable?

        let isOnQueue = await withCheckedContinuation { continuation in
            cancellable = source.defaultChanges.first().sink { continuation.resume(returning: DispatchQueue.getSpecific(key: queueKey) != nil) }
            userDefault.changesSubject.send()
        }

        #expect(isOnQueue)
        cancellable?.cancel()
    }
}
