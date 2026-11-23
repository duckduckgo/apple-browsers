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

/// The model and effort new chats start on, resolved from its inputs and cached until one of them changes.
public final class AIChatNewChatDefaultSource {

    /// `nil` until `models` holds a model the user can use.
    public private(set) var selection: AIChatNewChatSelection?

    /// Emits after web writes a different over-limit default, so open inputs can refresh.
    public var overLimitDefaultChanges: AnyPublisher<Void, Never> {
        overLimitDefaultChangesSubject.eraseToAnyPublisher()
    }

    public var models: [AIChatModel] = [] {
        didSet { resolveSelection() }
    }

    public var userTier: AIChatUserTier = .free {
        didSet { resolveSelection() }
    }

    /// The default `/models` sends.
    public var serverDefault: AIChatNewChatDefault = .unavailable {
        didSet { resolveSelection() }
    }

    /// The default the usage-limits snapshot sends while the user is over their limit; it wins over `serverDefault`.
    public var overLimitDefault: AIChatNewChatDefault = .unavailable {
        didSet { resolveSelection() }
    }

    private let overLimitDefaultChangesSubject = PassthroughSubject<Void, Never>()
    private var overLimitDefaultsCancellable: AnyCancellable?

    public init() {}

    /// Takes everything a `/models` response decides at once.
    public func update(models: [AIChatModel], userTier: AIChatUserTier, serverDefault: AIChatNewChatDefault) {
        self.models = models
        self.userTier = userTier
        self.serverDefault = serverDefault
    }

    /// Before `/models` loads, the local tier default stands in for the selection.
    public var selectionOrLocalDefaultBeforeModelsLoad: AIChatNewChatSelection? {
        models.isEmpty ? AIChatNewChatDefaultResolver.resolveBeforeModelsLoad(userTier: userTier) : selection
    }

    /// Follows `defaults` instead of any earlier one. Its first value applies quietly, as the state the input opens with.
    public func observeOverLimitDefaults(_ defaults: AnyPublisher<AIChatNewChatDefault, Never>) {
        var isFirstValue = true
        overLimitDefaultsCancellable = defaults.sink { [weak self] newDefault in
            self?.applyOverLimitDefault(newDefault, announcesChange: !isFirstValue)
            isFirstValue = false
        }
    }

    private func applyOverLimitDefault(_ newDefault: AIChatNewChatDefault, announcesChange: Bool) {
        guard newDefault != overLimitDefault else { return }
        overLimitDefault = newDefault
        if announcesChange {
            overLimitDefaultChangesSubject.send()
        }
    }

    private func resolveSelection() {
        let candidates = [AIChatNewChatDefaultResolver.Candidate(overLimitDefault, origin: .server),
                          AIChatNewChatDefaultResolver.Candidate(serverDefault, origin: .server)]
        selection = AIChatNewChatDefaultResolver.resolve(candidates, models: models, userTier: userTier)
    }
}
