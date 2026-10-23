//
//  ChatState.swift
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

/// Everything the chat UI renders. `apply(_:)` in `ChatReducer.swift` is the only writer.
public struct ChatState: Equatable, Sendable {
    public let conversation: ConversationID
    public let context: ChatContext
    public let budget: PromptBudget

    public internal(set) var messages: [Message] = []
    public internal(set) var phase: Phase = .idle
    public internal(set) var availability: ProviderAvailability
    /// The provider stream that has started and not yet ended, including one that was stopped and is draining.
    /// The single fact behind "one reply at a time".
    public internal(set) var streamInFlight: MessageID?
    var lastID = 0

    public init(conversation: ConversationID, context: ChatContext, budget: PromptBudget, availability: ProviderAvailability) {
        self.conversation = conversation
        self.context = context
        self.budget = budget
        self.availability = availability
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case responding(LiveReply)
        /// Cleared by the next send or redo.
        case failed(ChatError)
    }

    public var status: ChatStatus {
        switch phase {
        case .idle:
            if case .unsupported(let reason) = availability {
                .error(.modelUnavailable(reason: reason))
            } else {
                .ready
            }
        case .failed(let error): .error(error)
        case .responding(let live): live.parts.isEmpty ? .loading(live.stage) : .streaming
        }
    }

    public var liveReply: LiveReply? {
        guard case .responding(let live) = phase else { return nil }
        return live
    }

    public var canSend: Bool {
        if case .unsupported = availability { return false }
        return liveReply == nil
    }

    public var canStop: Bool {
        liveReply != nil
    }

    /// Not responding, and there is a user message to answer again.
    public var canRedo: Bool {
        guard liveReply == nil else { return false }
        if case .failed(let error) = phase, !error.allowsRedo { return false }
        return messages.contains { if case .user = $0 { true } else { false } }
    }
}

/// The reply being generated. Joins `messages` with the same id when it ends with content; dropped when empty.
public struct LiveReply: Equatable, Sendable {
    public let id: MessageID
    public let startedAt: Date
    /// Built when the reply was requested, so a queued reply starts without rebuilding.
    public let turn: ProviderTurn
    public internal(set) var stage: LoadingStage
    public internal(set) var parts: [AssistantPart]

    public init(id: MessageID, startedAt: Date, turn: ProviderTurn, stage: LoadingStage, parts: [AssistantPart] = []) {
        self.id = id
        self.startedAt = startedAt
        self.turn = turn
        self.stage = stage
        self.parts = parts
    }
}

public enum LoadingStage: Equatable, Sendable {
    /// The provider needs a download. Starts when it turns `.ready`.
    case waitingForModel
    /// A stopped reply is still draining. Starts when its stream ends.
    case queued
    /// Handed to the provider, no stage reported yet.
    case starting
    case provider(ProviderStage)
}

/// The frontend's ready, loading, streaming, error. Derived from `ChatState.phase`.
public enum ChatStatus: Equatable, Sendable {
    case ready
    case loading(LoadingStage)
    case streaming
    case error(ChatError)
}

/// Every input to the chat. Time arrives on the action so the reducer stays pure.
public enum ChatAction: Equatable, Sendable {
    /// Surface opened. Prepares the provider and sends `context.opening` once. Idempotent.
    case opened(at: Date)
    case send(String, attachments: [Attachment] = [], context: [ContextPart]? = nil, at: Date)
    case rejected(ChatError)
    case stop(at: Date)
    case redo(at: Date)
    case availabilityChanged(ProviderAvailability)
    /// Events for any id other than the live reply's are dropped.
    case provider(MessageID, ProviderEvent, at: Date)
    case providerFailed(MessageID, ChatError, at: Date)
    /// The provider stream for this id has ended, for any reason. Frees the lane.
    case providerEnded(MessageID, at: Date)
}

/// What the reducer asks the session to do.
public enum ChatEffect: Equatable, Sendable {
    case prepareProvider
    case startReply(MessageID, ProviderTurn)
    case requestStop(MessageID)
}
