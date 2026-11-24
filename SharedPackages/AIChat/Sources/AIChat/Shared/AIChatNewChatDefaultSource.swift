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
        let candidates = [AIChatNewChatDefaultResolver.Candidate(overLimitDefault.newChatDefault(at: now()), origin: .server),
                          AIChatNewChatDefaultResolver.Candidate(serverDefault, origin: .server)]
        return AIChatNewChatDefaultResolver.resolve(candidates, models: models, userTier: userTier)
    }

    /// Emits after web writes a different over-limit default, so open inputs can refresh.
    public var overLimitDefaultChanges: AnyPublisher<Void, Never> {
        overLimitDefaultChangesSubject.eraseToAnyPublisher()
    }

    public var models: [AIChatModel] = []
    /// `nil` until the subscription lookup answers; no local tier default stands in until then.
    public var userTier: AIChatUserTier?
    /// The default `/models` sends.
    public var serverDefault: AIChatNewChatDefault = .unavailable
    /// Wins over `serverDefault` until the limit resets.
    public var overLimitDefault: AIChatOverLimitNewChatDefault = .notOverLimit

    private let now: () -> Date
    private let overLimitDefaultChangesSubject = PassthroughSubject<Void, Never>()
    private var overLimitDefaultsCancellable: AnyCancellable?

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
            overLimitDefaultChangesSubject.send()
        }
    }
}
