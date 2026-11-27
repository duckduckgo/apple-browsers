//
//  LlamaChatFormatTests.swift
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

import Testing
@testable import LlamaRuntime

@Suite("Chat formats llama.cpp doesn't know")
struct LlamaChatFormatTests {

    private let messages = [
        LlamaChatMessage(role: "system", content: "Summarize pages."),
        LlamaChatMessage(role: "user", content: "Summarize this page.\n\n<page>\nText\n</page>"),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Gemma 4 turns are written the way its own template renders them with thinking off", .timeLimit(.minutes(1)))
    func gemma4MatchesItsTemplate() {
        let prompt = LlamaChatFormat.gemma4(messages, addAssistantStart: true)

        #expect(prompt == """
            <|turn>system
            Summarize pages.<turn|>
            <|turn>user
            Summarize this page.

            <page>
            Text
            </page><turn|>
            <|turn>model

            """)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without the answer's start, Gemma 4's prompt ends after the last turn", .timeLimit(.minutes(1)))
    func gemma4WithoutAssistantStart() {
        let prompt = LlamaChatFormat.gemma4([LlamaChatMessage(role: "assistant", content: "Hi")], addAssistantStart: false)

        #expect(prompt == "<|turn>model\nHi<turn|>\n")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Gemma 4 is recognized by its turn markers, and other templates aren't", .timeLimit(.minutes(1)))
    func recognizesGemma4() {
        #expect(LlamaChatFormat.isGemma4(template: "{{ bos_token }}<|turn>{{ message['role'] }}"))
        #expect(!LlamaChatFormat.isGemma4(template: "<|start_of_role|>{{ message['role'] }}<|end_of_role|>"))
    }
}
