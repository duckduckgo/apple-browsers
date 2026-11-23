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
        let userDefaultModelId = userDefaultModel?.modelId
        let selection = AIChatNewChatDefaultResolver.resolve(candidates(userDefaultModelId: userDefaultModelId), models: models, userTier: userTier)
        guard userDefaultModelId != nil, selection?.origin != .user else { return selection }
        return selection?.markingUserDefaultUnavailable()
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

    /// Before `/models` loads, the local tier default stands in for the selection, once the tier is known.
    public var selectionOrLocalDefaultBeforeModelsLoad: AIChatNewChatSelection? {
        guard models.isEmpty else { return selection }
        return userTier.map(AIChatNewChatDefaultResolver.resolveBeforeModelsLoad(userTier:))
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

    /// Follows `userDefaultModel` instead of any earlier one; `nil` stops using a user default.
    public func observeUserDefaultModel(_ userDefaultModel: AIChatUserDefaultModelProviding?) {
        self.userDefaultModel = userDefaultModel
        userDefaultModelChangesCancellable = userDefaultModel?.changes.sink { [weak self] in
            self?.defaultChangesSubject.send()
        }
    }

    /// The user default, then the over-limit default, then the `/models` default.
    private func candidates(userDefaultModelId: String?) -> [AIChatNewChatDefaultResolver.Candidate] {
        let overLimitDefault = overLimitDefault.newChatDefault(at: now())
        return [Self.userDefaultCandidate(userDefaultModelId, allowedBy: overLimitDefault),
                AIChatNewChatDefaultResolver.Candidate(overLimitDefault, origin: .server),
                AIChatNewChatDefaultResolver.Candidate(serverDefault, origin: .server)].compactMap { $0 }
    }

    /// Over the limit, the over-limit default is the only model native knows is allowed, so the user default must match it.
    private static func userDefaultCandidate(_ modelId: String?,
                                             allowedBy overLimitDefault: AIChatNewChatDefault) -> AIChatNewChatDefaultResolver.Candidate? {
        guard let modelId, overLimitDefault.allows(modelId) else { return nil }
        return AIChatNewChatDefaultResolver.Candidate(.model(id: modelId, reasoningEffort: nil), origin: .user)
    }
}

private extension AIChatNewChatDefault {

    /// Whether an over-limit default leaves `modelId` usable; no over-limit default allows every model.
    func allows(_ modelId: String) -> Bool {
        guard case let .model(id, _) = self else { return true }
        return id == modelId
    }
}
