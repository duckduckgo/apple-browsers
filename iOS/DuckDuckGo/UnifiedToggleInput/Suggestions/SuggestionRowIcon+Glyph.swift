//
//  SuggestionRowIcon+Glyph.swift
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

extension SuggestionRowIcon {
    /// The 24pt design-system glyph for this semantic icon.
    var glyph: UIImage {
        switch self {
        case .globe: return DesignSystemImages.Glyphs.Size24.globe
        case .bookmark: return DesignSystemImages.Glyphs.Size24.bookmark
        case .favorite: return DesignSystemImages.Glyphs.Size24.bookmarkFavorite
        case .history: return DesignSystemImages.Glyphs.Size24.history
        case .openTab: return DesignSystemImages.Glyphs.Size24.tabsMobile
        case .search: return DesignSystemImages.Glyphs.Size24.findSearchSmall
        case .aiChat: return DesignSystemImages.Glyphs.Size24.chat
        case .aiChatPinned: return DesignSystemImages.Glyphs.Size24.chatPinned
        case .pin: return DesignSystemImages.Glyphs.Size24.pin
        case .chats: return DesignSystemImages.Glyphs.Size24.chats
        }
    }
}
