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
import UIKit

/// Builds the address-bar Duck.ai menu offering a fresh chat or a chat about the current page.
enum DuckAIAddressBarMenuFactory {

    static func makeMenu(pageFavicon: UIImage?,
                         onNewChat: @escaping () -> Void,
                         onAskAboutPage: @escaping () -> Void) -> UIMenu {
        UIMenu(title: UserText.duckAiFeatureName, children: makeActions(pageFavicon: pageFavicon,
                                                                       onNewChat: onNewChat,
                                                                       onAskAboutPage: onAskAboutPage))
    }

    /// Each action sits in its own inline group so UIKit draws a separator between them.
    static func makeActions(pageFavicon: UIImage?,
                            onNewChat: @escaping () -> Void,
                            onAskAboutPage: @escaping () -> Void) -> [UIMenuElement] {
        [
            UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: UserText.duckAiAddressBarMenuNewChat,
                         image: DesignSystemImages.Glyphs.Size16.compose) { _ in
                    onNewChat()
                }
            ]),
            UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: UserText.aiChatAttachmentOptionAskAboutPage,
                         image: pageFavicon ?? DesignSystemImages.Glyphs.Size16.tabContent) { _ in
                    onAskAboutPage()
                }
            ])
        ]
    }
}
