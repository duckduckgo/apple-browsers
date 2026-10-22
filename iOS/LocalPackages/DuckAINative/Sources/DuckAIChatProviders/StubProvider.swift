//
//  StubProvider.swift
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

import DuckAIChatCore
import Foundation

/// A provider with no model, for the simulator and tests. Streams `reply` word by word after fake load and read stages.
/// Honours a stop at once, as any provider without an uninterruptible read may.
public final class StubProvider: ChatProvider, @unchecked Sendable {

    public struct Configuration: Sendable {
        public var reply: String
        public var wordsPerSecond: Double
        public var unevenBursts: Bool
        public var loadTime: Duration
        public var readTime: Duration
        /// Thrown after the first half of `reply` has streamed.
        public var failure: ChatError?
        public var availability: ProviderAvailability

        public init(reply: String = StubProvider.sampleReply,
                    wordsPerSecond: Double = 25,
                    unevenBursts: Bool = false,
                    loadTime: Duration = .milliseconds(600),
                    readTime: Duration = .milliseconds(400),
                    failure: ChatError? = nil,
                    availability: ProviderAvailability = .ready) {
            self.reply = reply
            self.wordsPerSecond = wordsPerSecond
            self.unevenBursts = unevenBursts
            self.loadTime = loadTime
            self.readTime = readTime
            self.failure = failure
            self.availability = availability
        }
    }

    /// Exercises every Markdown block the chat UI renders.
    public static let sampleReply = """
    ## Ducks at a glance

    Ducks are **waterfowl** in the family *Anatidae*. They live on fresh and salt water.

    - Dabbling ducks feed at the surface.
    - Diving ducks swim under water.

    1. Mallard
    2. Teal

    > A duck's feathers are waterproof.

    ```swift
    let duck = Duck(name: "Mallard")
    ```

    | Duck | Habitat |
    | --- | --- |
    | Mallard | Ponds |
    | Eider | Coasts |

    ---

    That is the short version.
    """

    public let descriptor = ProviderDescriptor(id: ProviderID(rawValue: "stub"),
                                               displayName: "Stub",
                                               modelName: "stub",
                                               supportsReasoning: false,
                                               supportsImages: false,
                                               contextWindowTokens: 8_192)

    private let configuration: Configuration
    private let lock = NSLock()
    private var currentAvailability: ProviderAvailability
    private var isLoaded = false
    private var subscribers: [UUID: AsyncStream<ProviderAvailability>.Continuation] = [:]

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        currentAvailability = configuration.availability
    }

    public var availability: ProviderAvailability {
        lock.withLock { currentAvailability }
    }

    public func availabilityUpdates() -> AsyncStream<ProviderAvailability> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { subscribers[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.subscribers[id] = nil }
            }
        }
    }

    public func download() async throws {
        for step in 0...4 {
            publish(.downloading(fraction: Double(step) / 4))
            try await Task.sleep(for: .milliseconds(10))
        }
        publish(.ready)
    }

    public func prepare() async {
        await load()
    }

    public func unload() {
        lock.withLock { isLoaded = false }
    }

    /// Loads once, like a real model, until `unload()`.
    private func load() async {
        guard !lock.withLock({ isLoaded }) else { return }
        try? await Task.sleep(for: configuration.loadTime)
        lock.withLock { isLoaded = true }
    }

    public func reply(to turn: ProviderTurn, stop: StopSignal) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var emitted = 0
                do {
                    let needsLoad = !self.lock.withLock { self.isLoaded }
                    if needsLoad, !stop.isRaised {
                        continuation.yield(.stage(.loadingModel(fraction: nil)))
                        await self.load()
                    }
                    if !stop.isRaised {
                        try await Task.sleep(for: configuration.readTime)
                        continuation.yield(.stage(.readingInput(estimatedTokens: turn.estimatedInputTokens, fraction: nil)))
                    }
                    let words = try configuration.reply.ranges(of: Regex("\\s*\\S+\\s*|\\s+")).map { String(configuration.reply[$0]) }
                    let started = ContinuousClock.now
                    for (index, word) in words.enumerated() {
                        guard !stop.isRaised else { break }
                        if let failure = configuration.failure, emitted >= words.count / 2 {
                            throw failure
                        }
                        let rate = configuration.wordsPerSecond > 0 ? configuration.wordsPerSecond : 25
                        let delay = configuration.unevenBursts ? (index % 12 == 0 ? 0.65 : index % 5 == 0 ? 0.18 : 0.005) : 1 / rate
                        try await Task.sleep(for: .seconds(delay))
                        guard !stop.isRaised else { break }
                        continuation.yield(.textDelta(word))
                        if word.contains(where: { !$0.isWhitespace }) { emitted += 1 }
                    }
                    if !stop.isRaised, let failure = configuration.failure { throw failure }
                    continuation.yield(.finished(GenerationStats(promptTokens: nil, generatedTokens: emitted,
                                                                 loadTime: needsLoad ? configuration.loadTime : nil, promptTime: configuration.readTime,
                                                                 generateTime: started.duration(to: .now))))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func publish(_ availability: ProviderAvailability) {
        lock.withLock {
            currentAvailability = availability
            for subscriber in subscribers.values { subscriber.yield(availability) }
        }
    }
}
