//
//  NewTabLongPressMenu.swift
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

import UIKit
import Core
import DesignResourcesKitIcons
import PixelKit

/// Long-press menu shared by every new-tab button: the toolbar tab switcher button, the iPad tabs bar
/// and the tab switcher's plus button.
enum NewTabLongPressMenu {

    enum Source: String {
        case toolbar
        case tabSwitcher = "tab_switcher"
        case tabsBar = "tabs_bar"
    }

    struct Actions {
        var onNewFireTab: () -> Void
        var onNewTab: () -> Void
        var onNewChat: () -> Void
        /// Read on every presentation, so changing the Duck.ai setting applies without rebuilding the menu.
        var isNewChatAvailable: () -> Bool
    }

    static func make(source: Source, actions: Actions, pixelFiring: PixelFiring? = PixelKit.shared) -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { completion in
                PixelKit.fire(Pixel.Event.tabLongPressMenuDisplayed, options: .parameters([
                    PixelParameters.source: source.rawValue
                ]))
                completion(items(source: source, actions: actions, pixelFiring: pixelFiring))
            }
        ])
    }

    static func items(source: Source, actions: Actions, pixelFiring: PixelFiring?) -> [UIAction] {
        let parameters = [PixelParameters.source: source.rawValue]
        var items = [
            UIAction(title: UserText.actionNewFireTab, image: DesignSystemImages.Glyphs.Size16.fireWindow) { _ in
                PixelKit.fire(Pixel.Event.tabLongPressMenuNewFireTab, options: .parameters(parameters))
                actions.onNewFireTab()
            },
            UIAction(title: UserText.actionNewTab, image: DesignSystemImages.Glyphs.Size16.add) { _ in
                PixelKit.fire(Pixel.Event.tabLongPressMenuNewNormalTab, options: .parameters(parameters))
                actions.onNewTab()
            }
        ]
        if actions.isNewChatAvailable() {
            items.append(UIAction(title: UserText.actionNewAIChat, image: DesignSystemImages.Glyphs.Size16.aiChat) { _ in
                pixelFiring?.fire(NewTabLongPressMenuPixel.newChat(source: source))
                actions.onNewChat()
            })
        }
        return items
    }
}

enum NewTabLongPressMenuPixel: PixelKit.Event {

    case newChat(source: NewTabLongPressMenu.Source)

    var name: String {
        switch self {
        case .newChat: return "tab_long_press_menu_new_chat"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .newChat(let source): return [PixelParameters.source: source.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
