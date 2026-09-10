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

    /// Groups New Chat and Ask About Page above a separator, with All Chats below.
    static func makeActions(featureFlagger: FeatureFlagger,
                            userInterfaceIdiom: UIUserInterfaceIdiom,
                            type: DuckAIAddressBarMenuType,
                            onNewChat: @escaping () -> Void,
                            onAskAboutPage: @escaping () -> Void,
                            onRecentChats: @escaping () -> Void) -> [UIMenuElement] {
        let askAboutTitle: String = {
            switch type {
            case .webPage:
                UserText.aiChatAttachmentOptionAskAboutPage
            case .search:
                UserText.aiChatAttachmentOptionContinueInDuckAi
            case .document:
                UserText.aiChatAttachmentOptionAskAboutDocument
            }
        }()
        var groups: [UIMenuElement] = [
            UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: UserText.duckAiAddressBarMenuNewChat,
                         image: DesignSystemImages.Glyphs.Size16.compose) { _ in
                    onNewChat()
                },
                UIAction(title: askAboutTitle,
                         image: DesignSystemImages.Glyphs.Size16.chevronCircleDown) { _ in
                    onAskAboutPage()
                }
            ])
        ]
        if userInterfaceIdiom != .pad,
           featureFlagger.isFeatureOn(.aiChatNativeChatHistory),
           featureFlagger.isFeatureOn(.aiChatAddressBarRecentChats) {
            groups.append(UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: UserText.duckAiAddressBarMenuAllChats,
                         image: DesignSystemImages.Glyphs.Size16.chats) { _ in
                    onRecentChats()
                }
            ]))
        }
        return groups
    }
}


