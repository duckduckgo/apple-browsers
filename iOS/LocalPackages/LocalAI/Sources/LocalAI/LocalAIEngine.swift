//
//  LocalAIEngine.swift
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

public enum LocalAIEngineKind: String, Codable, CaseIterable, Sendable {
    case mlx
    case foundationModels
    case stub

    public var displayName: String {
        switch self {
        case .mlx: "MLX (downloaded model)"
        case .foundationModels: "Apple Foundation Models"
        case .stub: "Stub (canned text)"
        }
    }
}

/// Token counts and timings an engine reports when it finishes, when it knows them.
public struct LocalAIGenerationInfo: Codable, Equatable, Sendable {
    public let promptTokens: Int?
    public let generatedTokens: Int
    public let promptTime: TimeInterval?
    public let generateTime: TimeInterval?
    /// Time spent waiting for the model to load before this reply could start, if it wasn't loaded yet.
    public let loadTime: TimeInterval?

    public init(promptTokens: Int?, generatedTokens: Int, promptTime: TimeInterval?, generateTime: TimeInterval?, loadTime: TimeInterval? = nil) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.promptTime = promptTime
        self.generateTime = generateTime
        self.loadTime = loadTime
    }
}

/// What an engine is doing before its first words, so the UI can say so instead of showing dots.
public enum LocalAIStatus: Equatable, Sendable {
    case loadingModel
    /// About to read `estimatedTokens` of input (the prefill) before it can write.
    case readingInput(estimatedTokens: Int)
}

public enum LocalAIEvent: Sendable {
    case status(LocalAIStatus)
    case text(String)
    case finished(LocalAIGenerationInfo?)
}

public extension LocalAIStatus {
    /// Roughly three and a half characters per token for the languages we test; only used for progress.
    static func reading(_ message: String) -> LocalAIStatus {
        .readingInput(estimatedTokens: max(1, Int(Double(message.count) / 3.5)))
    }
}

public enum LocalAIEngineError: LocalizedError, Equatable {
    case modelNotDownloaded
    case unavailable(String)
    case contextTooLong(tokens: Int, limit: Int)
    case refused(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: "No local model is downloaded."
        case .unavailable(let reason): "The on-device model is unavailable: \(reason)"
        case .contextTooLong(let tokens, let limit): "Too long for the on-device model (\(tokens) of \(limit) tokens)."
        case .refused(let reason): "The on-device model declined: \(reason)"
        }
    }

    /// Outcomes the benchmark reports as results rather than failures.
    public var isExpectedOutcome: Bool {
        switch self {
        case .contextTooLong, .refused: true
        case .modelNotDownloaded, .unavailable: false
        }
    }
}

public protocol LocalAIEngine: AnyObject {
    var kind: LocalAIEngineKind { get }
    /// `nil` when ready to generate.
    @MainActor var unavailableReason: String? { get }
    /// Model identity for reports, e.g. the Hugging Face id.
    @MainActor var modelName: String { get }
    /// A chat that keeps its history (and the model's cache) between messages.
    func makeConversation(instructions: String) -> LocalAIConversation
    /// Starts loading (and warming up) the model in the background, so the first reply doesn't wait for it.
    func preload()
    /// Frees the model's memory. The next generation loads it again.
    func unload()
}

public protocol LocalAIConversation: AnyObject {
    /// Sends the next user message. One at a time: wait for a stream to end before sending again.
    func send(_ message: String, maxTokens: Int) -> AsyncThrowingStream<LocalAIEvent, Error>
}

public extension LocalAIEngine {
    func preload() {}

    /// A one-off generation: a fresh conversation with a single message.
    func generate(_ prompt: LocalAIPrompt) -> AsyncThrowingStream<LocalAIEvent, Error> {
        makeConversation(instructions: prompt.instructions).send(prompt.message, maxTokens: prompt.maxTokens)
    }
}

/// Streams canned text so the sheet UI can be exercised without a model, e.g. on the simulator.
public final class StubLocalAIEngine: LocalAIEngine {

    public let kind = LocalAIEngineKind.stub
    public let modelName = "stub"
    public var unavailableReason: String? { nil }

    private let tokensPerSecond: Double
    private let firstTokenDelay: TimeInterval

    public init(tokensPerSecond: Double = 30, firstTokenDelay: TimeInterval = 0.5) {
        self.tokensPerSecond = tokensPerSecond
        self.firstTokenDelay = firstTokenDelay
    }

    public func makeConversation(instructions: String) -> LocalAIConversation {
        StubConversation(tokensPerSecond: tokensPerSecond, firstTokenDelay: firstTokenDelay)
    }

    public func unload() {}

    static func cannedResponse(to message: String, turn: Int, maxTokens: Int) -> String {
        """
        This is a **stub** answer (turn \(turn)), streamed word by word so the chat can be tested without a model.

        - The real engines run on a device: MLX with a downloaded model, or Apple Foundation Models.
        - You said: \(message.prefix(80).replacingOccurrences(of: "\n", with: " "))
        - The reply would be capped at \(maxTokens) tokens.
        """
    }
}

private final class StubConversation: LocalAIConversation {
    private let tokensPerSecond: Double
    private let firstTokenDelay: TimeInterval
    private var turn = 0

    init(tokensPerSecond: Double, firstTokenDelay: TimeInterval) {
        self.tokensPerSecond = tokensPerSecond
        self.firstTokenDelay = firstTokenDelay
    }

    func send(_ message: String, maxTokens: Int) -> AsyncThrowingStream<LocalAIEvent, Error> {
        turn += 1
        let words = StubLocalAIEngine.cannedResponse(to: message, turn: turn, maxTokens: maxTokens)
            .split(separator: " ", omittingEmptySubsequences: false)
        let delay = UInt64(1_000_000_000 / tokensPerSecond)
        let firstDelay = UInt64(firstTokenDelay * 1_000_000_000)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.status(.reading(message)))
                    try await Task.sleep(nanoseconds: firstDelay)
                    for (index, word) in words.enumerated() {
                        try Task.checkCancellation()
                        continuation.yield(.text(index == 0 ? String(word) : " " + word))
                        try await Task.sleep(nanoseconds: delay)
                    }
                    continuation.yield(.finished(LocalAIGenerationInfo(promptTokens: nil, generatedTokens: words.count, promptTime: nil, generateTime: nil)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
