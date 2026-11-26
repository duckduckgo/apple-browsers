//
//  AIChatVoiceInChatPixel.swift
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

import AIChat
import PixelKit

/// Continuing a Duck.ai chat by voice from the chat input.
enum AIChatVoiceInChatPixel: PixelKit.Event {

    /// The voice button was tapped while the page says voice can't continue this chat.
    case unavailableTapped(reason: AIChatVoiceInChatAvailability.Reason)

    var name: String {
        switch self {
        case .unavailableTapped: return "aichat_voice_in_chat_unavailable_tapped"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .unavailableTapped(let reason): return ["reason": reason.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
