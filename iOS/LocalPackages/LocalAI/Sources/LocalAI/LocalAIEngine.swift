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

    public init(promptTokens: Int?, generatedTokens: Int, promptTime: TimeInterval?, generateTime: TimeInterval?) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.promptTime = promptTime
        self.generateTime = generateTime
    }
}

public enum LocalAIEvent: Sendable {
    case text(String)
    case finished(LocalAIGenerationInfo?)
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
    func generate(_ prompt: LocalAIPrompt) -> AsyncThrowingStream<LocalAIEvent, Error>
    /// Frees the model's memory. The next generation loads it again.
    func unload()
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

    public func generate(_ prompt: LocalAIPrompt) -> AsyncThrowingStream<LocalAIEvent, Error> {
        let words = Self.cannedResponse(for: prompt).split(separator: " ", omittingEmptySubsequences: false)
        let delay = UInt64(1_000_000_000 / tokensPerSecond)
        let firstDelay = UInt64(firstTokenDelay * 1_000_000_000)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
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

    public func unload() {}

    static func cannedResponse(for prompt: LocalAIPrompt) -> String {
        """
        This is a **stub** answer, streamed word by word so the result screen can be tested without a model.

        - The real engines run on a device: MLX with a downloaded model, or Apple Foundation Models.
        - The prompt asked: \(prompt.message.prefix(80).replacingOccurrences(of: "\n", with: " "))…
        - The reply would be capped at \(prompt.maxTokens) tokens.
        """
    }
}
