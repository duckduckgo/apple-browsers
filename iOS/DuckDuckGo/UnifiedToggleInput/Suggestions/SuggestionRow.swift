//
//  SuggestionRow.swift
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

import Foundation

/// Semantic icon for a suggestion row. The view resolves each case to a concrete
/// `DesignSystemImages.Glyphs.Size24` glyph; keeping the model glyph-free makes
/// `SuggestionRow` fully value-`Equatable` (so section diffing / `removeDuplicates`
/// is correct) and decouples it from the design system.
enum SuggestionRowIcon: Equatable {
    case globe
    case bookmark
    case favorite
    case history
    case openTab
    case search
    case aiChat
    case aiChatPinned
    case pin
    /// Double speech-bubble glyph for the "View all chats" row.
    case chats
}

/// One row in the unified UTI suggestions list. Pure data — carries no actions.
/// Selection and tap handling are dispatched by `id` to the active view model.
struct SuggestionRow: Identifiable, Equatable {

    enum Accessory: Equatable {
        case none
        case tapAhead
        case delete
        /// 🔥 button on a recent-chat row that opens the delete-confirmation sheet.
        case fire
    }

    let id: String
    let icon: SuggestionRowIcon
    let title: String
    /// When set, the matched prefix of `title` is rendered bold.
    let query: String?
    let subtitle: String?
    let accessory: Accessory
    let accessibilityID: String

    init(id: String,
         icon: SuggestionRowIcon,
         title: String,
         query: String? = nil,
         subtitle: String? = nil,
         accessory: Accessory = .none,
         accessibilityID: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.query = query
        self.subtitle = subtitle
        self.accessory = accessory
        self.accessibilityID = accessibilityID
    }
}

/// A titled group of rows. Sections with no rows are omitted by producers.
struct SuggestionSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let rows: [SuggestionRow]

    init(id: String, title: String? = nil, rows: [SuggestionRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}
