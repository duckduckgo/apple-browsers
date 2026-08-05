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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askAboutPage:
            return UserText.aiChatQuickActionAskAboutPage
        case .summarize:
            return UserText.aiChatQuickActionSummarize
        case .summarizePage:
            return UserText.aiChatQuickActionSummarizePage
        }
    }

    var prompt: String {
        switch self {
        case .askAboutPage:
            return ""
        case .summarize, .summarizePage:
            return UserText.aiChatQuickActionSummarize
        }
    }

    var icon: UIImage? {
        switch self {
        case .askAboutPage:
            return DesignSystemImages.Glyphs.Size16.pageContentAttach
        case .summarize:
            return DesignSystemImages.Glyphs.Size16.arrowDownRight
        case .summarizePage:
            return DesignSystemImages.Glyphs.Size16.summary
        }
    }
}
