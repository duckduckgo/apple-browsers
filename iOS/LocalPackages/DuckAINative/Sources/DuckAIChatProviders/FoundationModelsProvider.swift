//
//  FoundationModelsProvider.swift
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
import DuckAIChatCore
import Foundation
import FoundationModels

@available(iOS 26, macOS 26, *)
public final class FoundationModelsProvider: ChatProvider, Sendable {
    public let descriptor = ProviderDescriptor(id: ProviderID(rawValue: "foundation-models"),
                                               displayName: "Apple Foundation Models", modelName: "System",
                                               supportsReasoning: false, supportsImages: false, contextWindowTokens: 4_096)

    public init() {}

    public var availability: ProviderAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(let reason): return .unsupported(reason: String(describing: reason))
        }
    }

    public func availabilityUpdates() -> AsyncStream<ProviderAvailability> {
        AsyncStream { continuation in
            let initial = availability
            let task = Task {
                var previous = initial
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { break }
                    let current = availability
                    if current != previous {
                        continuation.yield(current)
                        previous = current
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func download() async throws {}
    public func prepare() async {}
    public func unload() {}

    public func reply(to turn: ProviderTurn, stop: StopSignal) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let terminal = try await withThrowingTaskGroup(of: ProviderEvent.self) { group in
                        group.addTask {
                            if stop.isRaised { return .finished(nil) }
                            let session = LanguageModelSession(instructions: turn.instructions)
                            let history = turn.history.map { message in
                                "\(message.role == .user ? "User" : "Assistant"): \(message.text)"
                            }
                            let prompt = (history + ["User: " + turn.input]).joined(separator: "\n\n")
                            continuation.yield(.stage(.readingInput(estimatedTokens: turn.estimatedInputTokens, fraction: nil)))
                            var emitted = ""
                            do {
                                for try await snapshot in session.streamResponse(
                                    to: prompt, options: GenerationOptions(maximumResponseTokens: turn.maxOutputTokens)) {
                                    if stop.isRaised { return .finished(nil) }
                                    try Task.checkCancellation()
                                    let content = snapshot.content
                                    guard content.hasPrefix(emitted) else {
                                        throw ChatError.unknown("Foundation Models revised previously streamed text.")
                                    }
                                    let delta = String(content.dropFirst(emitted.count))
                                    if !delta.isEmpty { continuation.yield(.textDelta(delta)) }
                                    emitted = content
                                }
                                return .finished(nil)
                            } catch {
                                if stop.isRaised { return .finished(nil) }
                                if Self.isRefusal(error) { return .refusal(Refusal(detectedBy: "guardrail")) }
                                throw Self.map(error)
                            }
                        }
                        group.addTask {
                            while !stop.isRaised { try await Task.sleep(for: .milliseconds(10)) }
                            return .finished(nil)
                        }
                        defer { group.cancelAll() }
                        return try await group.next() ?? .finished(nil)
                    }
                    continuation.yield(terminal)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func isRefusal(_ error: Error) -> Bool {
        if #available(iOS 27, macOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        return false
    }

    private static func map(_ error: Error) -> ChatError {
        if let error = error as? ChatError { return error }
        if #available(iOS 27, macOS 27, *), let error = error as? LanguageModelError,
           case .contextSizeExceeded(let details) = error {
            return .inputTooLong(tokens: details.tokenCount, limit: details.contextSize)
        }
        if let error = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = error {
            return .inputTooLong(tokens: nil, limit: 4_096)
        }
        return .unknown(error.localizedDescription)
    }
}
#endif
