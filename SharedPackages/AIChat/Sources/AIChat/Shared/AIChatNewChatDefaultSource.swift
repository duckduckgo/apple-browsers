//
//  AIChatNewChatDefaultSource.swift
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

/// The model and effort new chats start on, resolved from its inputs on each read.
public final class AIChatNewChatDefaultSource {

    /// `nil` until `models` holds a model the user can use.
    public var selection: AIChatNewChatSelection? {
        AIChatNewChatDefaultResolver.resolve(candidates(), models: models, userTier: userTier)
    }

    /// Emits after web writes a different over-limit or user default, so open inputs can refresh.
    public var defaultChanges: AnyPublisher<Void, Never> {
        defaultChangesSubject.eraseToAnyPublisher()
    }

    public var models: [AIChatModel] = []
    /// `nil` until the subscription lookup answers; no local tier default stands in until then.
    public var userTier: AIChatUserTier?
    /// The default `/models` sends.
    public var serverDefault: AIChatNewChatDefault = .unavailable
    /// Wins over `serverDefault` until the limit resets.
    public var overLimitDefault: AIChatOverLimitNewChatDefault = .notOverLimit

    private let now: () -> Date
    private let defaultChangesSubject = PassthroughSubject<Void, Never>()
    private var overLimitDefaultsCancellable: AnyCancellable?
    private var userDefaultModel: AIChatUserDefaultModelProviding?
    private var userDefaultModelChangesCancellable: AnyCancellable?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Takes everything a `/models` response decides at once.
    public func update(models: [AIChatModel], serverDefault: AIChatNewChatDefault) {
        self.models = models
        self.serverDefault = serverDefault
    }

    /// Before `/models` loads, only the local tier default is known to be usable, so a user default applies only when it's that model.
    public var selectionOrLocalDefaultBeforeModelsLoad: AIChatNewChatSelection? {
        guard models.isEmpty else { return selection }
        guard let userTier else { return nil }
        let localDefault = AIChatNewChatDefaultResolver.resolveBeforeModelsLoad(userTier: userTier)
        guard case let .model(id, _)? = userDefault(followedBy: serverDefaults()), id == localDefault.modelId else { return localDefault }
        return AIChatNewChatSelection(modelId: id, reasoningEffort: localDefault.reasoningEffort, origin: .user)
    }

    /// Follows `defaults` instead of any earlier one. Its first value applies quietly, as the state the input opens with.
    public func observeOverLimitDefaults(_ defaults: AnyPublisher<AIChatOverLimitNewChatDefault, Never>) {
        var isFirstValue = true
        overLimitDefaultsCancellable = defaults.sink { [weak self] newDefault in
            self?.applyOverLimitDefault(newDefault, announcesChange: !isFirstValue)
            isFirstValue = false
        }
    }

    private func applyOverLimitDefault(_ newDefault: AIChatOverLimitNewChatDefault, announcesChange: Bool) {
        guard newDefault != overLimitDefault else { return }
        overLimitDefault = newDefault
        if announcesChange {
            defaultChangesSubject.send()
        }
    }

    /// Follows `userDefaultModel` instead of any earlier one, announcing its changes on `scheduler`; `nil` stops using a user default.
    public func observeUserDefaultModel<S: Scheduler>(_ userDefaultModel: AIChatUserDefaultModelProviding?, receivingUpdatesOn scheduler: S) {
        self.userDefaultModel = userDefaultModel
        userDefaultModelChangesCancellable = userDefaultModel?.changes
            .receive(on: scheduler)
            .sink { [weak self] in self?.defaultChangesSubject.send() }
    }

    /// Follows the user default `storage` holds; fire storage reads it through from normal storage.
    public func observeUserDefaultModel<S: Scheduler>(in storage: DuckAiNativeStorageHandling?, receivingUpdatesOn scheduler: S) {
        observeUserDefaultModel(storage.map(DuckAiUserDefaultModelStore.init(storage:)), receivingUpdatesOn: scheduler)
    }

    /// The user default, then the over-limit default, then the `/models` default.
    private func candidates() -> [AIChatNewChatDefaultResolver.Candidate] {
        let serverDefaults = serverDefaults()
        let serverCandidates = serverDefaults.map { AIChatNewChatDefaultResolver.Candidate($0, origin: .server) }
        guard let userDefault = userDefault(followedBy: serverDefaults) else { return serverCandidates }
        return [AIChatNewChatDefaultResolver.Candidate(userDefault, origin: .user)] + serverCandidates
    }

    private func serverDefaults() -> [AIChatNewChatDefault] {
        [overLimitDefault.newChatDefault(at: now()), serverDefault]
    }

    /// `nil` when not set. On a server default's model it takes that default's effort.
    private func userDefault(followedBy serverDefaults: [AIChatNewChatDefault]) -> AIChatNewChatDefault? {
        guard let modelId = userDefaultModel?.modelId else { return nil }
        guard isAllowedByUsageLimit(modelId: modelId) else { return .unavailable }
        return .model(id: modelId, reasoningEffort: Self.reasoningEffort(forModelId: modelId, in: serverDefaults))
    }

    /// Over the limit only the model the limit names is known to be allowed.
    private func isAllowedByUsageLimit(modelId: String) -> Bool {
        let now = now()
        guard overLimitDefault.isOverLimit(at: now) else { return true }
        return overLimitDefault.newChatDefault(at: now).modelId == modelId
    }

    private static func reasoningEffort(forModelId modelId: String, in defaults: [AIChatNewChatDefault]) -> AIChatReasoningEffort? {
        for case let .model(id, reasoningEffort) in defaults where id == modelId {
            return reasoningEffort
        }
        return nil
    }
}
