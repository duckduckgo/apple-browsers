//
//  DuckAIAddressBarMenuFactory.swift
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

import DesignResourcesKitIcons
import FeatureFlags_iOS
import PrivacyConfig
import UIKit

/// Builds the address-bar Duck.ai menu for new chats, page questions, and chat history.
enum DuckAIAddressBarMenuFactory {

    static func isChatHistoryAvailable(featureFlagger: FeatureFlagger, userInterfaceIdiom: UIUserInterfaceIdiom) -> Bool {
        userInterfaceIdiom != .pad
            && featureFlagger.isFeatureOn(.aiChatNativeChatHistory)
            && featureFlagger.isFeatureOn(.aiChatAddressBarRecentChats)
    }

    /// Groups New Chat and, on web tabs, Ask About Page above a separator, with Chats below.
    static func makeActions(featureFlagger: FeatureFlagger,
                            userInterfaceIdiom: UIUserInterfaceIdiom,
                            isHomeTab: Bool,
                            onNewChat: @escaping () -> Void,
                            onAskAboutPage: @escaping () -> Void,
                            onRecentChats: @escaping () -> Void) -> [UIMenuElement] {
        var chatActions: [UIMenuElement] = [
            UIAction(title: UserText.duckAiAddressBarMenuNewChat,
                     image: DesignSystemImages.Glyphs.Size16.compose) { _ in
                onNewChat()
            }
        ]
        if !isHomeTab {
            chatActions.append(UIAction(title: UserText.aiChatAttachmentOptionAskAboutPage,
                                        image: DesignSystemImages.Glyphs.Size16.chevronCircleDown) { _ in
                onAskAboutPage()
            })
        }
        var groups: [UIMenuElement] = [UIMenu(title: "", options: .displayInline, children: chatActions)]
        // iPhone opens the native chat history, so it needs that flag too; iPad falls back to the
        // duck.ai chats sidebar and only needs the kill switch.
        let showsRecentChats = featureFlagger.isFeatureOn(.aiChatAddressBarRecentChats)
            && (userInterfaceIdiom == .pad || featureFlagger.isFeatureOn(.aiChatNativeChatHistory))
        if showsRecentChats {
            groups.append(UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: UserText.actionChats,
                         image: DesignSystemImages.Glyphs.Size16.chats) { _ in
                    onRecentChats()
                }
            ]))
        }
        return groups
    }
}
