//
//  AIChatReasoningEffort.swift
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

import AppKit
import AIChat
import DesignResourcesKitIcons

extension AIChatReasoningEffort {
    /// Label shown on the picker chip and as the menu item's primary text.
    var title: String {
        switch self {
        case .none, .minimal: return UserText.aiChatReasoningEffortFastTitle
        case .low: return UserText.aiChatReasoningEffortLowTitle
        case .medium, .high: return UserText.aiChatReasoningEffortMediumTitle
        }
    }

    /// Secondary menu text describing what the effort does.
    var subtitle: String {
        switch self {
        case .none, .minimal: return UserText.aiChatReasoningEffortFastSubtitle
        case .low: return UserText.aiChatReasoningEffortLowSubtitle
        case .medium, .high: return UserText.aiChatReasoningEffortMediumSubtitle
        }
    }

    /// Icon used on the picker chip and in the menu.
    var icon: NSImage {
        switch self {
        case .none, .minimal: return DesignSystemImages.Glyphs.Size16.thunderbolt
        case .low: return DesignSystemImages.Glyphs.Size16.thinking
        case .medium, .high: return DesignSystemImages.Glyphs.Size16.timer
        }
    }
}
