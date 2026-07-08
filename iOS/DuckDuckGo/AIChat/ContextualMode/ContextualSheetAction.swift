//
//  ContextualSheetAction.swift
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

import AIChat
import DesignResourcesKitIcons
import UIKit

/// Adapter that lets the contextual sheet stack render both static quick actions and
/// dynamic suggestions through the same `AIChatQuickActionChipView`.
enum ContextualSheetAction: AIChatQuickActionType {
    case quickAction(AIChatContextualQuickAction)
    case suggestion(ContextualSuggestedPrompt)

    var id: String {
        switch self {
        case .quickAction(let action): return action.id
        case .suggestion(let suggestion): return suggestion.id
        }
    }

    var title: String {
        switch self {
        case .quickAction(let action): return action.title
        case .suggestion(let suggestion): return suggestion.label
        }
    }

    var prompt: String {
        switch self {
        case .quickAction(let action): return action.prompt
        case .suggestion(let suggestion): return suggestion.prompt
        }
    }

    var icon: UIImage? {
        switch self {
        case .quickAction(let action): return action.icon
        case .suggestion(let suggestion): return Self.glyph(for: suggestion.icon)
        }
    }

    private static func glyph(for identifier: String?) -> UIImage? {
        switch identifier {
        case "summary": return DesignSystemImages.Glyphs.Size16.summary
        case "translate": return DesignSystemImages.Glyphs.Size16.translate
        case "note": return DesignSystemImages.Glyphs.Size16.note
        default: return DesignSystemImages.Glyphs.Size16.idea
        }
    }
}
