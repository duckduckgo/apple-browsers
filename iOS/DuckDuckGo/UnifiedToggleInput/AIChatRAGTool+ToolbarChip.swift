//
//  AIChatRAGTool+ToolbarChip.swift
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

/// Display attributes for the selected-tool chip/badge shown in the unified toggle input toolbar
/// (iPhone) and the iPad address-bar expanded input area. Only `.webSearch` and `.imageGeneration`
/// are surfaced in the omnibar tools menu; other cases are defensive fallbacks.
extension AIChatRAGTool {

    var toolbarChipIcon: DesignSystemImage? {
        switch self {
        case .webSearch:
            return DesignSystemImages.Glyphs.Size24.globe
        case .imageGeneration:
            return DesignSystemImages.Glyphs.Size24.images
        case .newsSearch, .videosSearch, .localSearch, .relatedSearchTerms, .weatherForecast:
            // Not surfaced in the unified-input tools menu — defensive fallback only.
            return nil
        }
    }

    /// Human-readable tool name shown as the badge label (iPad).
    var toolbarChipTitle: String? {
        switch self {
        case .webSearch:
            return UserText.aiChatToolbarWebSearchToolTitle
        case .imageGeneration:
            return UserText.aiChatToolbarImageGenerationToolTitle
        case .newsSearch, .videosSearch, .localSearch, .relatedSearchTerms, .weatherForecast:
            // Not surfaced in the unified-input tools menu — defensive fallback only.
            return nil
        }
    }

    var toolbarChipAccessibilityLabel: String? {
        switch self {
        case .webSearch:
            return UserText.aiChatToolbarWebSearchToolTitle
        case .imageGeneration:
            return UserText.aiChatToolbarImageGenerationToolTitle
        case .newsSearch, .videosSearch, .localSearch, .relatedSearchTerms, .weatherForecast:
            // Not surfaced in the unified-input tools menu — defensive fallback only.
            return nil
        }
    }
}
