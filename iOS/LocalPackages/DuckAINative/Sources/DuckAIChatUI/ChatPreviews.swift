//
//  ChatPreviews.swift
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
import SwiftUI

#Preview("Chat · Light") {
    ChatPreview().preferredColorScheme(.light)
}

#Preview("Chat · Dark") {
    ChatPreview().preferredColorScheme(.dark)
}

@MainActor
private struct ChatPreview: View {
    @State private var session = makeSession()

    var body: some View {
        ChatView(session: session, surface: .contextualSheet,
                 actions: ChatActions(close: {}, continueInWeb: { _ in }), showsComposer: false)
            .frame(width: 402, height: 860)
            .task {
                session.open()
                while session.state.liveReply != nil { await Task.yield() }
                guard session.state.messages.count == 2 else { return }
                session.send("What happens when a reply is interrupted?")
            }
    }

    private static func makeSession() -> ChatSession {
        let page = PageContext(title: "A guide to native chat", url: URL(string: "https://duck.ai"), content: "A short guide to native chat.")
        guard let context = try? ChatContext(page: page, selections: [], opening: .prompt("Summarize this page with examples.")) else {
            preconditionFailure("Invalid preview context")
        }
        return ChatSession(context: context, provider: PreviewChatProvider(), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }
}

private final class PreviewChatProvider: ChatProvider {
    let descriptor = ProviderDescriptor(id: ProviderID(rawValue: "preview"), displayName: "Preview provider", modelName: "Preview model",
                                        supportsReasoning: true, supportsImages: false, contextWindowTokens: 8_192)
    var availability: ProviderAvailability { .ready }

    func availabilityUpdates() -> AsyncStream<ProviderAvailability> { AsyncStream { $0.finish() } }
    func download() async throws { }
    func prepare() async { }
    func unload() { }

    func reply(to turn: ProviderTurn, stop: StopSignal) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.reasoningDelta("I’ll identify the main ideas and show a small example."))
            if turn.history.isEmpty {
                continuation.yield(.textDelta(Self.reply))
                continuation.yield(.finished(nil))
                continuation.finish()
            } else {
                continuation.yield(.textDelta("A partial reply remains visible if the connection is interrupted."))
                continuation.finish(throwing: ChatError.network)
            }
        }
    }

    private static let reply = """
    # A more useful chat

    Read a page and ask questions using **natural language**. Try `summarize(page)` to get started.

    ## Key ideas

    - Keep the page in context.
    - Ask a focused follow-up question.

    ### A small example

    ```swift
    let summary = "A concise overview of the page, ready to discuss."
    print(summary)
    ```

    | Feature | Benefit |
    | --- | --- |
    | Page context | Relevant answers |
    | Follow-up | More detail |

    > Your questions stay connected to the page.

    #### Next steps

    Visit [Duck.ai](https://duck.ai) to continue exploring.
    """
}
