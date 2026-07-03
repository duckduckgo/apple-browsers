//
//  AIChatReasoningMode+UnifiedToggleInput.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

extension AIChatReasoningMode {
    private var unifiedToggleInputIconImage: UIImage? {
        switch self {
        case .fast:
            return DesignSystemImages.Glyphs.Size24.lightning
        case .reasoning:
            return DesignSystemImages.Glyphs.Size24.thinking
        case .extendedReasoning:
            return DesignSystemImages.Glyphs.Size24.timer
        }
    }

    var unifiedToggleInputTitle: String {
        switch self {
        case .fast:
            return UserText.aiChatReasoningModeFastTitle
        case .reasoning:
            return UserText.aiChatReasoningModeReasoningTitle
        case .extendedReasoning:
            return UserText.aiChatReasoningModeExtendedTitle
        }
    }

    var unifiedToggleInputSubtitle: String {
        switch self {
        case .fast:
            return UserText.aiChatReasoningModeFastSubtitle
        case .reasoning:
            return UserText.aiChatReasoningModeReasoningSubtitle
        case .extendedReasoning:
            return UserText.aiChatReasoningModeExtendedSubtitle
        }
    }

    var unifiedToggleInputMenuImage: UIImage? {
        unifiedToggleInputIconImage?.withTintColor(UIColor(designSystemColor: .iconsSecondary), renderingMode: .alwaysOriginal)
    }

    var unifiedToggleInputButtonImage: UIImage? {
        unifiedToggleInputIconImage
    }

    var unifiedToggleInputButtonTintColor: UIColor {
        UIColor(designSystemColor: .iconsSecondary)
    }
}
