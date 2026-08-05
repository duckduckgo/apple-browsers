//
//  AIChatContextualQuickAction.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AIChat
import DesignResourcesKitIcons
import UIKit

/// Predefined quick actions for the contextual AI chat sheet.
enum AIChatContextualQuickAction: String, CaseIterable, AIChatQuickActionType {
    case askAboutPage
    case summarize
    case summarizePage
    /// Selection-scoped actions, offered when the sheet was opened from the text-selection menu.
    /// These act on the attached selection rather than the page.
    case summarizeSelection
    case translateSelection
    case askAboutSelection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askAboutPage:
            return UserText.aiChatQuickActionAskAboutPage
        case .summarize:
            return UserText.aiChatQuickActionSummarize
        case .summarizePage:
            return UserText.aiChatQuickActionSummarizePage
        case .summarizeSelection:
            return UserText.aiChatQuickActionSummarizeSelection
        case .translateSelection:
            return UserText.aiChatQuickActionTranslateSelection
        case .askAboutSelection:
            return UserText.aiChatQuickActionAskAboutSelection
        }
    }

    var prompt: String {
        switch self {
        case .askAboutPage, .askAboutSelection:
            return ""
        case .summarize, .summarizePage:
            return UserText.aiChatQuickActionSummarize
        // Selection summarize/translate carry an `AIChatNativePrompt` tool rather than prompt text,
        // so the frontend renders them the way macOS does.
        case .summarizeSelection, .translateSelection:
            return ""
        }
    }

    /// True for actions that operate on an attached text selection rather than the page.
    var isSelectionScoped: Bool {
        switch self {
        case .summarizeSelection, .translateSelection, .askAboutSelection:
            return true
        case .askAboutPage, .summarize, .summarizePage:
            return false
        }
    }

    var icon: UIImage? {
        switch self {
        case .askAboutPage:
            return DesignSystemImages.Glyphs.Size16.pageContentAttach
        case .summarize:
            return DesignSystemImages.Glyphs.Size16.arrowDownRight
        case .summarizePage, .summarizeSelection:
            return DesignSystemImages.Glyphs.Size16.summary
        case .translateSelection:
            return DesignSystemImages.Glyphs.Size16.translate
        case .askAboutSelection:
            return DesignSystemImages.Glyphs.Size16.idea
        }
    }
}
