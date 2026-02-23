//
//  NewTabPageOmnibarAiChatsProvider.swift
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

import NewTabPage

final class NewTabPageOmnibarAiChatsProvider: NewTabPageOmnibarAiChatsProviding {

    func aiChats() async -> NewTabPageDataModel.AiChatsData {
        return NewTabPageDataModel.AiChatsData(chats: [
            NewTabPageDataModel.AiChat(chatId: "1", title: "What is the meaning of life?", pinned: true, lastEdit: "2026-02-23T10:00:00Z"),
            NewTabPageDataModel.AiChat(chatId: "2", title: "How do black holes form?", pinned: false, lastEdit: "2026-02-22T15:30:00Z"),
            NewTabPageDataModel.AiChat(chatId: "3", title: "Best practices for Swift concurrency", pinned: false, lastEdit: "2026-02-21T09:15:00Z"),
        ])
    }

}
