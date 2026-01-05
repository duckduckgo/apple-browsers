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
    case summarize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize:
            return UserText.aiChatQuickActionSummarize
        }
    }

    var prompt: String {
        switch self {
        case .summarize:
            return "summarize this page"
        }
    }

    var icon: UIImage? {
        switch self {
        case .summarize:
            return DesignSystemImages.Glyphs.Size16.arrowDownRight
        }
    }
}
