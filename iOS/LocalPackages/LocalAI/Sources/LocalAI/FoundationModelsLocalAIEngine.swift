//
//  FoundationModelsLocalAIEngine.swift
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

#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple's on-device model: the comparator with no download. Runs outside our process.
@available(iOS 26.0, macOS 26.0, *)
public final class FoundationModelsLocalAIEngine: LocalAIEngine {

    public let kind = LocalAIEngineKind.foundationModels
    public let modelName = "Apple Foundation Models (system)"

    public init() {}

    public var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): String(describing: reason)
        }
    }

    public func generate(_ prompt: LocalAIPrompt) -> AsyncThrowingStream<LocalAIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.checkContextBudget(for: prompt)
                    let session = LanguageModelSession(instructions: prompt.instructions)
                    let options = GenerationOptions(maximumResponseTokens: prompt.maxTokens)
                    var emitted = ""
                    for try await snapshot in session.streamResponse(to: prompt.message, options: options) {
                        let content = snapshot.content
                        if content.hasPrefix(emitted) {
                            continuation.yield(.text(String(content.dropFirst(emitted.count))))
                        }
                        emitted = content
                    }
                    continuation.yield(.finished(nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func unload() {}

    /// iOS 26 shares 4,096 tokens between prompt and reply, so long translations can't fit. Say so up
    /// front instead of failing mid-stream. Counting tokens needs 26.4; earlier, generation decides.
    private static func checkContextBudget(for prompt: LocalAIPrompt) async throws {
        guard #available(iOS 26.4, macOS 26.4, *) else { return }
        let model = SystemLanguageModel.default
        let promptTokens = try await model.tokenCount(for: prompt.instructions + "\n" + prompt.message)
        let needed = promptTokens + prompt.maxTokens
        if needed > model.contextSize {
            throw LocalAIEngineError.contextTooLong(tokens: needed, limit: model.contextSize)
        }
    }

    private static func map(_ error: Error) -> Error {
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded(let details):
                return LocalAIEngineError.contextTooLong(tokens: details.tokenCount, limit: details.contextSize)
            case .guardrailViolation, .refusal:
                return LocalAIEngineError.refused(error.localizedDescription)
            default:
                return error
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                return LocalAIEngineError.contextTooLong(tokens: 0, limit: SystemLanguageModel.default.contextSize)
            case .guardrailViolation, .refusal:
                return LocalAIEngineError.refused(error.localizedDescription)
            default:
                return error
            }
        }
        return error
    }
}
#endif
