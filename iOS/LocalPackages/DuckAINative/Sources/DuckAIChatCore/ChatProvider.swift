//
//  ChatProvider.swift
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

/// The seam every model sits behind: Stub, Apple Foundation Models, MLX, and later a remote API.
///
/// Stateless from Core's view: each reply carries the whole conversation. A provider that keeps a cache keys it by
/// `ProviderTurn.conversation` and reuses it only when `history` extends what it last saw.
public protocol ChatProvider: AnyObject, Sendable {
    var descriptor: ProviderDescriptor { get }

    /// Current availability, read synchronously so the first reduction does not guess.
    var availability: ProviderAvailability { get }

    /// Every availability change after `availability`. Ends when the consumer cancels.
    func availabilityUpdates() -> AsyncStream<ProviderAvailability>

    /// Starts the opt-in download behind `.needsDownload`. Progress arrives through `availabilityUpdates()`.
    func download() async throws

    /// Loads and warms the model. Idempotent; a reply that starts during a prepare waits on the same load.
    func prepare() async

    /// Frees model memory. Safe while a stopped reply drains: the provider unloads after the stream ends.
    func unload()

    /// Streams one reply.
    /// - Emits zero or more `.stage`, then deltas, then one terminal `.finished` or `.refusal`, or throws `ChatError`.
    /// - Core never cancels the consuming task. When `stop` is raised the provider ends the stream at its next safe
    ///   point. For MLX that is the first token after reading the input, because cancelling then corrupts the cache.
    /// - The stream must end after a stop. Core keeps the next reply queued until it does.
    /// - May be called for different conversations at once; a provider that cannot run two serializes them itself.
    func reply(to turn: ProviderTurn, stop: StopSignal) -> AsyncThrowingStream<ProviderEvent, Error>
}

public struct ProviderID: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ProviderDescriptor: Equatable, Sendable {
    public let id: ProviderID
    public let displayName: String
    public let modelName: String
    public let supportsReasoning: Bool
    public let supportsImages: Bool
    public let contextWindowTokens: Int

    public init(id: ProviderID, displayName: String, modelName: String, supportsReasoning: Bool, supportsImages: Bool, contextWindowTokens: Int) {
        self.id = id
        self.displayName = displayName
        self.modelName = modelName
        self.supportsReasoning = supportsReasoning
        self.supportsImages = supportsImages
        self.contextWindowTokens = contextWindowTokens
    }
}

public enum ProviderAvailability: Equatable, Sendable {
    case ready
    case needsDownload(bytes: Int64)
    case downloading(fraction: Double)
    case unsupported(reason: String)
}

public enum ProviderEvent: Equatable, Sendable {
    case stage(ProviderStage)
    case textDelta(String)
    case reasoningDelta(String)
    /// Terminal.
    case refusal(Refusal)
    /// Terminal. Also how a stopped stream ends.
    case finished(GenerationStats?)
}

/// Why the first word has not arrived yet.
public enum ProviderStage: Equatable, Sendable {
    case loadingModel(fraction: Double?)
    case readingInput(estimatedTokens: Int, fraction: Double?)
}

public struct ConversationID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// One reply's request, rendered and budgeted by `PromptBuilder`.
public struct ProviderTurn: Equatable, Sendable {
    public let conversation: ConversationID
    public let instructions: String
    /// Prior exchanges, oldest first.
    public let history: [ProviderMessage]
    /// The new user input, rendered with its context.
    public let input: String
    public let maxOutputTokens: Int
    /// Lets the UI show "reading ~N tokens" for providers that cannot measure.
    public let estimatedInputTokens: Int

    public init(conversation: ConversationID, instructions: String, history: [ProviderMessage], input: String, maxOutputTokens: Int, estimatedInputTokens: Int) {
        self.conversation = conversation
        self.instructions = instructions
        self.history = history
        self.input = input
        self.maxOutputTokens = maxOutputTokens
        self.estimatedInputTokens = estimatedInputTokens
    }
}

public struct ProviderMessage: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// A one-shot stop request handed to each reply. Created before the provider is called, so a stop is never lost.
public final class StopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    public init() {}

    public var isRaised: Bool {
        lock.withLock { raised }
    }

    public func raise() {
        lock.withLock { raised = true }
    }
}

/// The frontend's error kinds a local or remote provider can produce. Providers throw these directly.
public enum ChatError: Error, Equatable, Sendable {
    case modelNotDownloaded
    case modelUnavailable(reason: String)
    case inputTooLong(tokens: Int?, limit: Int?)
    case conversationTooLong
    case emptyResponse
    case network
    case rateLimited
    case unknown(String)

    public var allowsRedo: Bool {
        switch self {
        case .modelUnavailable, .conversationTooLong: false
        default: true
        }
    }
}
