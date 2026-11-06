//
//  MainMenuDuckAISection.swift
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

import Combine
import DesignResourcesKitIcons
import UIKit

/// The Duck.ai menu, shown only while Duck.ai is enabled.
struct DuckAIMenuSection: MainMenuSection {
    static let identifier = UIMenu.Identifier("com.duckduckgo.duckai")
    static let recentChatsIdentifier = UIMenu.Identifier("com.duckduckgo.duckai.history")

    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        guard context.aiChatEnabled else { return nil }
        return MainMenuSpec.Menu(identifier: Self.identifier, items: [], placement: .insert(sibling: .view, position: .after), submenus: [
            MainMenuSpec.group("duckai.open", [MainMenuSpec.item(.openDuckAI, UserText.menuOpenDuckAI)]),
            MainMenuSpec.group("duckai.new", [
                MainMenuSpec.item(.newChat, UserText.menuNewChat, "n", [.alternate, .command]),
                MainMenuSpec.item(.newVoiceChat, UserText.menuNewVoiceChat, "v", [.alternate, .command]),
                MainMenuSpec.item(.newImageChat, UserText.menuNewImageChat, "g", [.alternate, .command])
            ]),
            MainMenuSpec.Menu(identifier: Self.recentChatsIdentifier, items: [], deferredContent: Self.recentChatsIdentifier)
        ], title: UserText.menuDuckAI)
    }
}

/// Recent Chats and Delete All Chats, loaded each time the Duck.ai menu opens.
struct DuckAIRecentChatsMenuContent: MainMenuDeferredContent {
    struct Chat {
        let title: String
        let url: URL
    }

    struct Chats {
        let recentChats: [Chat]
        let totalChatCount: Int
    }

    let loadChats: @MainActor () async -> Chats

    /// Uncached, so chats load each time the menu opens. Key equivalents inside deferred elements never fire, so its items have none.
    func makeElement() -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { [loadChats] completion in
            Task { @MainActor in
                completion(Self.elements(for: await loadChats()))
            }
        }
    }

    /// Recent Chats, newest first, followed by Delete All Chats, which stays visible and is disabled without chats.
    static func elements(for chats: Chats) -> [UIMenuElement] {
        let builder = MainMenuBuilder()
        let recentChatCommands = chats.recentChats.map {
            builder.makeCommand(for: .init(command: .openRecentChat, title: $0.title, shortcut: nil, requirement: nil,
                                           argument: $0.url.absoluteString, image: DesignSystemImages.Glyphs.Size16.chat))
        }
        let deleteAllChats = builder.makeCommand(for: .init(command: .deleteAllChats, title: UserText.menuDeleteAllChats, shortcut: nil,
                                                            requirement: nil, argument: String(chats.totalChatCount),
                                                            image: DesignSystemImages.Glyphs.Size16.fire))
        var elements: [UIMenuElement] = []
        if !recentChatCommands.isEmpty {
            elements.append(UIMenu(title: UserText.menuRecentChats, identifier: UIMenu.Identifier("com.duckduckgo.duckai.recent"),
                                   options: .displayInline, children: recentChatCommands))
        }
        elements.append(UIMenu(title: "", identifier: UIMenu.Identifier("com.duckduckgo.duckai.delete"),
                               options: .displayInline, children: [deleteAllChats]))
        return elements
    }
}

extension Publisher {

    /// The first value sent within `timeout`, or `nil` when the publisher fails, finishes or sends nothing by then.
    func firstValue(within timeout: DispatchQueue.SchedulerTimeType.Stride) async -> Output? {
        try? await self.timeout(timeout, scheduler: DispatchQueue.main).values.first { _ in true }
    }

}
