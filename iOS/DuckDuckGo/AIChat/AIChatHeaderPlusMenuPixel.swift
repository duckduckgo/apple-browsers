//
//  AIChatHeaderPlusMenuPixel.swift
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

/// A pick from the + menu in the Duck.ai tab's chat header.
///
/// `m_aichat_entry_point` counts the new chat, voice chat and image items but not New Tab or New Search,
/// so this one pixel counts every item and guards against the prompt box's ⊕ drawing taps away from the header +.
enum AIChatHeaderPlusMenuPixel: PixelKit.Event {

    enum Item: String {
        case newChat = "new_chat"
        case newVoiceChat = "new_voice_chat"
        case newImage = "new_image"
        case newTab = "new_tab"
        case newSearch = "new_search"
        case newFireTab = "new_fire_tab"
    }

    case itemSelected(Item, simplifiedPromptBox: Bool)

    var name: String { "aichat_header_plus_menu_item_selected" }

    var parameters: [String: String]? {
        switch self {
        case .itemSelected(let item, let simplifiedPromptBox):
            typealias Keys = UnifiedToggleInputCoordinatorPixelHelper
            var parameters = ["item": item.rawValue]
            parameters[Keys.simplifiedPromptBoxKey] = Keys.simplifiedPromptBoxValue(simplifiedPromptBox)
            return parameters
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
