//
//  UnifiedToggleInputAttachMenuPixel.swift
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

/// An item in the attach (+) menu, sent as the `item` param of the item-selected pixel.
enum UnifiedToggleInputAttachMenuItem: String, CaseIterable {
    case camera
    case photoLibrary = "photo_library"
    case filePicker = "file_picker"
    case page
    case recentTab = "recent_tab"
    case tabPicker = "tab_picker"
    /// The tool rows the simplified prompt box folds into the menu.
    case webSearch = "web_search"
    case createImage = "create_image"
}

extension UnifiedToggleInputAttachMenuItem {
    /// The attach-menu item for a tool row; Customize Responses has no row there.
    init?(tool: UTIToolsMenu.Item.Identifier) {
        switch tool {
        case .webSearch: self = .webSearch
        case .imageGeneration: self = .createImage
        case .customizeResponses: return nil
        }
    }
}

enum UnifiedToggleInputAttachMenuPixel: PixelKit.Event {
    case shown(surface: UnifiedToggleInputPixelSurface, simplifiedPromptBox: Bool)
    case itemSelected(UnifiedToggleInputAttachMenuItem, surface: UnifiedToggleInputPixelSurface, simplifiedPromptBox: Bool)

    var name: String {
        switch self {
        case .shown: "m_aichat_unified_input_attach_menu_shown"
        case .itemSelected: "m_aichat_unified_input_attach_menu_item_selected"
        }
    }

    var parameters: [String: String]? {
        typealias Keys = UnifiedToggleInputCoordinatorPixelHelper
        var parameters: [String: String]
        let simplifiedPromptBox: Bool
        switch self {
        case .shown(let surface, let isSimplified):
            parameters = ["surface": surface.rawValue]
            simplifiedPromptBox = isSimplified
        case .itemSelected(let item, let surface, let isSimplified):
            parameters = ["surface": surface.rawValue, "item": item.rawValue]
            simplifiedPromptBox = isSimplified
        }
        parameters[Keys.simplifiedPromptBoxKey] = Keys.simplifiedPromptBoxValue(simplifiedPromptBox)
        return parameters
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
