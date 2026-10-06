//
//  DuckAIResponseCompletionDetector.swift
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

import AIChat

/// Spots a finished Duck.ai response in the chat saves the web app sends to native storage.
///
/// Duck.ai saves the chat when a prompt is sent (last message from the user) and again when the
/// response finishes (last message from the assistant). Other saves – title updates, chat
/// conversion on open, sync – also end with an assistant message, so a response only counts as
/// finished when this tab saw the prompt go out first.
struct DuckAIResponseCompletionDetector {

    private var promptMessageCountByChatID: [String: Int] = [:]

    mutating func isFinishedResponse(chatID: String, lastMessage: DuckAiChatLastMessage) -> Bool {
        guard lastMessage.isFromAssistant else {
            promptMessageCountByChatID[chatID] = lastMessage.messageCount
            return false
        }
        guard let promptMessageCount = promptMessageCountByChatID[chatID],
              lastMessage.messageCount > promptMessageCount else {
            return false
        }
        promptMessageCountByChatID[chatID] = nil
        return true
    }
}
