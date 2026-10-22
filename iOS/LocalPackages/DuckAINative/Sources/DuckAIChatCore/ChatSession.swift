//
//  ChatSession.swift
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

import Foundation
import Observation

/// The thin shell. Feeds actions to `ChatState.apply` and performs the effects it returns. No chat rules live here.
@MainActor
@Observable
public final class ChatSession {
    public private(set) var state: ChatState
    public var descriptor: ProviderDescriptor { provider.descriptor }

    @ObservationIgnored private let provider: any ChatProvider
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var stopSignals: [MessageID: StopSignal] = [:]
    @ObservationIgnored private var availabilityTask: Task<Void, Never>?

    public init(context: ChatContext, provider: any ChatProvider, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.now = now
        self.state = ChatState(conversation: ConversationID(),
                               context: context,
                               budget: PromptBudget(provider.descriptor),
                               availability: provider.availability)
    }

    /// Call when the surface appears. Safe to call again.
    public func open() {
        if availabilityTask == nil {
            let updates = provider.availabilityUpdates()
            availabilityTask = Task { [weak self] in
                for await availability in updates {
                    self?.dispatch(.availabilityChanged(availability))
                }
            }
        }
        if state.messages.isEmpty {
            do { try descriptor.capabilities.validate(attachments: state.context.attachments) } catch {
                reject(error as? ChatError ?? .unknown(error.localizedDescription))
                return
            }
        }
        dispatch(.opened(at: now()))
    }

    public func reject(_ error: ChatError) {
        guard state.canSend else { return }
        dispatch(.rejected(error))
    }

    public func validateAttachments(_ attachments: [Attachment]) throws {
        let retained = state.messages.reduce(0) { total, message in
            if case .user(let user) = message { return total + user.attachments.reduce(0) { $0 + $1.data.count } }
            return total
        }
        try descriptor.capabilities.validate(attachments: attachments, retainedBytes: retained)
    }

    public func send(_ text: String, attachments: [Attachment] = []) {
        do {
            try validateAttachments(attachments)
            dispatch(.send(text, attachments: attachments, at: now()))
        } catch {
            reject(error as? ChatError ?? .unknown(error.localizedDescription))
        }
    }

    public func stop() {
        dispatch(.stop(at: now()))
    }

    public func redo() {
        dispatch(.redo(at: now()))
    }

    public func download() {
        Task { [provider] in try? await provider.download() }
    }

    /// Surface closing. Never cancels a provider stream: a draining MLX reply ends on its own.
    /// Leaves the model loaded for the next chat; the app unloads it under memory pressure.
    public func close() {
        dispatch(.stop(at: now()))
        availabilityTask?.cancel()
        availabilityTask = nil
    }

    private func dispatch(_ action: ChatAction) {
        for effect in state.apply(action) {
            perform(effect)
        }
    }

    private func perform(_ effect: ChatEffect) {
        switch effect {
        case .prepareProvider:
            Task { [provider] in await provider.prepare() }
        case .requestStop(let id):
            stopSignals[id]?.raise()
        case .startReply(let id, let turn):
            let stop = StopSignal()
            stopSignals[id] = stop
            let events = provider.reply(to: turn, stop: stop)
            Task { [weak self] in
                do {
                    for try await event in events {
                        self?.receive(.provider(id, event, at: .now))
                    }
                } catch {
                    self?.receive(.providerFailed(id, error as? ChatError ?? .unknown(String(describing: error)), at: .now))
                }
                self?.receive(.providerEnded(id, at: .now))
            }
        }
    }

    private func receive(_ action: ChatAction) {
        if case .providerEnded(let id, _) = action {
            stopSignals[id] = nil
        }
        dispatch(action)
    }
}
