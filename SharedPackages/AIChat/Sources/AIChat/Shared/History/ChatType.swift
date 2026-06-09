//
//  ChatType.swift
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

/// Coarse classification of a Duck.ai chat used to pick an icon and an export format.
/// Mirrors the Android `ChatType` enum so chat exports are interchangeable across platforms.
public enum ChatType: Equatable {
    case discussion
    case voice
    case imageGeneration
}

public extension DuckAiChat {

    /// Derives the chat type from the stored `model` string. Voice and image-generation chats
    /// are identified by their canonical mode tokens; everything else is a regular discussion.
    var chatType: ChatType {
        switch AIChatSuggestion.kind(forModel: model) {
        case .voice: return .voice
        case .image: return .imageGeneration
        case .text: return .discussion
        }
    }
}
