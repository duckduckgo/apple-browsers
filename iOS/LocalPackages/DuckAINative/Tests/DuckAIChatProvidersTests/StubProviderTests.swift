//
//  StubProviderTests.swift
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
import DuckAIChatProviders
import Foundation
import Testing

@Suite struct StubProviderTests {

    private let turn = ProviderTurn(conversation: ConversationID(), instructions: "Be helpful.", history: [],
                                    input: "Hi", maxOutputTokens: 64, estimatedInputTokens: 12)

    private func fast(_ reply: String = "One two three", failure: ChatError? = nil) -> StubProvider {
        StubProvider(configuration: .init(reply: reply, wordsPerSecond: 10_000, loadTime: .zero, readTime: .zero, failure: failure))
    }

    private func collect(_ stream: AsyncThrowingStream<ProviderEvent, Error>) async throws -> [ProviderEvent] {
        var events: [ProviderEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func streamsStagesThenTheWholeReplyThenFinishes() async throws {
        let events = try await collect(fast().reply(to: turn, stop: StopSignal()))

        let stages = events.prefix { if case .stage = $0 { true } else { false } }
        #expect(stages.first == .stage(.loadingModel(fraction: nil)))
        #expect(stages.contains(.stage(.readingInput(estimatedTokens: 12, fraction: nil))))
        let text = events.compactMap { if case .textDelta(let delta) = $0 { delta } else { nil } }.joined()
        #expect(text == "One two three")
        guard case .finished(let stats) = events.last else {
            Issue.record("last event \(String(describing: events.last)) is not .finished")
            return
        }
        #expect(stats?.generatedTokens == 3)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func theModelLoadsOnceUntilUnloaded() async throws {
        let provider = fast()
        let first = try await collect(provider.reply(to: turn, stop: StopSignal()))
        let second = try await collect(provider.reply(to: turn, stop: StopSignal()))
        provider.unload()
        let third = try await collect(provider.reply(to: turn, stop: StopSignal()))

        #expect(first.contains(.stage(.loadingModel(fraction: nil))))
        #expect(!second.contains(.stage(.loadingModel(fraction: nil))))
        #expect(third.contains(.stage(.loadingModel(fraction: nil))))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aRaisedStopEndsTheStreamWithFinished() async throws {
        let stop = StopSignal()
        stop.raise()
        let provider = StubProvider(configuration: .init(reply: String(repeating: "word ", count: 500), wordsPerSecond: 50))

        let events = try await collect(provider.reply(to: turn, stop: stop))

        let text = events.compactMap { if case .textDelta(let delta) = $0 { delta } else { nil } }.joined()
        #expect(text.count < 50)
        guard case .finished = events.last else {
            Issue.record("a stopped stream must still end with .finished")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aConfiguredFailureIsThrownAfterSomeText() async {
        var text = ""
        await #expect(throws: ChatError.network) {
            for try await event in fast("a b c d", failure: .network).reply(to: turn, stop: StopSignal()) {
                if case .textDelta(let delta) = event { text += delta }
            }
        }
        #expect(!text.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func reportsItsConfiguredAvailability() async {
        let provider = StubProvider(configuration: .init(availability: .needsDownload(bytes: 42)))

        #expect(provider.availability == .needsDownload(bytes: 42))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func downloadWalksProgressToReady() async throws {
        let provider = StubProvider(configuration: .init(loadTime: .zero, availability: .needsDownload(bytes: 42)))
        let updates = Task {
            var seen: [ProviderAvailability] = []
            for await availability in provider.availabilityUpdates() {
                seen.append(availability)
                if availability == .ready { break }
            }
            return seen
        }

        try await provider.download()

        let seen = await updates.value
        #expect(seen.last == .ready)
        #expect(seen.contains { if case .downloading = $0 { true } else { false } })
        #expect(provider.availability == .ready)
    }
}
