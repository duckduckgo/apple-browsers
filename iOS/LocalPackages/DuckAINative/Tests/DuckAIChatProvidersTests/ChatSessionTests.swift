//
//  ChatSessionTests.swift
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

@MainActor
@Suite struct ChatSessionTests {

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openingPromptStreamsAReplyIntoTheHistory() async throws {
        let provider = StubProvider(configuration: .init(reply: "Hello there", wordsPerSecond: 1_000, loadTime: .zero, readTime: .zero))
        let session = ChatSession(context: try ChatContext(page: nil, selections: [], opening: .prompt("Hi")), provider: provider)

        session.open()
        await waitUntil { session.state.messages.count == 2 && session.state.streamInFlight == nil }

        guard case .assistant(let reply) = session.state.messages.last else {
            Issue.record("expected an assistant reply, got \(session.state.messages)")
            return
        }
        #expect(reply.parts == [.text("Hello there")])
        #expect(session.state.status == .ready)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func theDefaultStubCompletesAReplyWhilePreparing() async throws {
        let provider = StubProvider(configuration: .init(reply: "Hello there", wordsPerSecond: 50))
        let session = ChatSession(context: try ChatContext(page: nil, selections: [], opening: .prompt("Hi")), provider: provider)

        session.open()
        await waitUntil { session.state.messages.count == 2 && session.state.streamInFlight == nil }

        #expect(session.state.status == .ready)
        #expect(session.state.messages.count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stopThenSendStartsTheNextReplyAfterTheFirstStreamEnds() async throws {
        let provider = StubProvider(configuration: .init(reply: String(repeating: "word ", count: 400), wordsPerSecond: 200,
                                                         loadTime: .zero, readTime: .zero))
        let session = ChatSession(context: try ChatContext(page: nil, selections: [], opening: .prompt("Hi")), provider: provider)
        session.open()
        await waitUntil { session.state.status == .streaming }

        session.stop()
        session.send("Again")
        await waitUntil { session.state.messages.count == 4 && session.state.streamInFlight == nil }

        let roles = session.state.messages.map { if case .user = $0 { "user" } else { "assistant" } }
        #expect(roles == ["user", "assistant", "user", "assistant"])
        guard case .assistant(let stopped) = session.state.messages[1] else { return }
        #expect(stopped.ending == .stopped)
    }
}
