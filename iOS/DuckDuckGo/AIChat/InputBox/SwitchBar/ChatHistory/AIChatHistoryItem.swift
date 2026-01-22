//
//  AIChatHistoryItem.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Represents a chat item in the AI Chat history
struct AIChatHistoryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let isPinned: Bool
    let lastUpdated: Date

    init(id: String = UUID().uuidString, title: String, isPinned: Bool, lastUpdated: Date = Date()) {
        self.id = id
        self.title = title
        self.isPinned = isPinned
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Mock Data

extension AIChatHistoryItem {
    /// Mock pinned chats for testing
    static let mockPinnedChats: [AIChatHistoryItem] = [
        AIChatHistoryItem(title: "Swift concurrency best practices", isPinned: true),
        AIChatHistoryItem(title: "Recipe for chocolate cake", isPinned: true),
        AIChatHistoryItem(title: "Travel planning for Japan", isPinned: true)
    ]

    /// Mock recent chats for testing
    static let mockRecentChats: [AIChatHistoryItem] = [
        AIChatHistoryItem(title: "How to fix memory leaks in iOS", isPinned: false),
        AIChatHistoryItem(title: "Explain quantum computing", isPinned: false),
        AIChatHistoryItem(title: "Best practices for SwiftUI animations", isPinned: false),
        AIChatHistoryItem(title: "What is the capital of France?", isPinned: false),
        AIChatHistoryItem(title: "Help me write a cover letter", isPinned: false),
        AIChatHistoryItem(title: "Debugging tips for Xcode", isPinned: false)
    ]
}
