//
//  LlamaChatFormat.swift
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

/// Chat formats written out here because the llama.cpp release the app ships doesn't know them.
enum LlamaChatFormat {

    /// Gemma 4's template, stored in its model file, marks each turn with `<|turn>` and `<turn|>`.
    static func isGemma4(template: String) -> Bool {
        template.contains("<|turn>")
    }

    /// What Gemma 4's own template renders with thinking off. The tokenizer adds BOS.
    static func gemma4(_ messages: [LlamaChatMessage], addAssistantStart: Bool) -> String {
        var prompt = messages.map { message in
            let role = message.role == "assistant" ? "model" : message.role
            return "<|turn>\(role)\n\(message.content)<turn|>\n"
        }.joined()
        if addAssistantStart {
            prompt += "<|turn>model\n"
        }
        return prompt
    }
}
