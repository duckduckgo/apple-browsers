//
//  DuckAISwipeNewChatPixel.swift
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

import PixelKit

/// The swipe itself reports as `m_aichat_entry_point` with source `swipe_up_new_chat`.
enum DuckAISwipeNewChatPixel: PixelKit.Event {

    case undo

    var name: String {
        switch self {
        case .undo: return "aichat_swipe-new-chat_undo"
        }
    }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
