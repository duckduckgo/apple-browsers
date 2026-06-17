//
//  UnifiedToggleInputCoordinatorPixelHelper.swift
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
import Core
import Foundation

private enum UnifiedPromptSubmittedSelectedToolPixelValue: String {
    case webSearch = "web_search"
    case imageGeneration = "image_generation"
    case none

    init(selectedTool: AIChatRAGTool?) {
        guard let selectedTool else {
            self = .none
            return
        }

        guard let identifier = UTIToolsMenu.Item.Identifier(tool: selectedTool) else {
            self = .none
            return
        }

        self = Self(identifier: identifier)
    }

    private init(identifier: UTIToolsMenu.Item.Identifier) {
        switch identifier {
        case .webSearch:
            self = .webSearch
        case .imageGeneration:
            self = .imageGeneration
        case .customizeResponses:
            // Not a model tool — never produced from a selected tool, so it never reports as one.
            self = .none
        }
    }
}

extension UTIToolsMenu.Item.Identifier {
    init?(tool: AIChatRAGTool) {
        switch tool {
        case .webSearch:
            self = .webSearch
        case .imageGeneration:
            self = .imageGeneration
        case .newsSearch, .videosSearch, .localSearch, .relatedSearchTerms, .weatherForecast:
            assertionFailure("Unsupported UTI selected tool: \(tool.rawValue)")
            return nil
        }
    }

    /// Whether activating this tool hides the reasoning picker in the UTI UI.
    var hidesReasoningPicker: Bool {
        switch self {
        case .imageGeneration: return true
        case .webSearch: return false
        case .customizeResponses: return false
        }
    }
}

final class UnifiedToggleInputCoordinatorPixelHelper {
    private init() {}

    static func fireAttachmentRemovedPixel(for attachment: UnifiedToggleInputAttachment) {
        switch attachment {
        case .image:
            DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputImageRemoved)
        case .file, .invalidFile:
            DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputFileRemoved)
        }
    }

    static func fireSubscriptionUpsellTriggeredPixel(
        source: SubscriptionFlowSource,
        currentTier: AIChatUserTier,
        requiredTier: AIChatModelPublicAccessTier,
        flowType: UpsellFlowType
    ) {
        Pixel.fire(pixel: .unifiedToggleInputSubscriptionUpsellTriggered,
                   withAdditionalParameters: [
                    "source": source == .modelPicker ? "model_picker" : "reasoning_picker",
                    "current_tier": currentTier.rawValue,
                    "required_tier": requiredTier == .pro ? "pro" : "plus",
                    "flow_type": flowType.rawValue
                   ]
        )
    }

    static func fireToolSelectedPixel(for tool: AIChatRAGTool) {
        switch tool {
        case .imageGeneration:
            DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputImageGenerationSelected)
        case .webSearch:
            DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputWebSearchSelected)
        default:
            break
        }
    }

    static func fireToolDeselectedPixel(for tool: AIChatRAGTool) {
        switch tool {
        case .imageGeneration:
            DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputImageGenerationDeselected)
        case .webSearch:
            DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputWebSearchDeselected)
        default:
            break
        }
    }

    static func fireCustomizeResponsesSelectedPixel() {
        DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputCustomizeResponsesSelected)
    }

    static func fireUnifiedPromptSubmittedPixel(
        text: String,
        selectedTool: AIChatRAGTool?,
        attachments: [UnifiedToggleInputAttachment],
        reasoningMode: AIChatReasoningMode?,
        modelId: String?
    ) {
        let selectedToolValue = UnifiedPromptSubmittedSelectedToolPixelValue(selectedTool: selectedTool).rawValue
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let reasoningEffort = reasoningMode?.rawValue ?? "none"
        let modelId = modelId ?? ""

        DailyPixel.fireDailyAndCount(
            pixel: .unifiedToggleInputPromptSubmitted,
            withAdditionalParameters: [
                "selected_tool": selectedToolValue,
                "model_id": modelId,
                "reasoning_effort": reasoningEffort,
                "has_image_attachment": hasImageAttachment(in: attachments) ? "true" : "false",
                "has_file_attachment": hasFileAttachment(in: attachments) ? "true" : "false",
                "has_text": hasText ? "true" : "false"
            ]
        )
    }

    static func fireToolSubmittedPixelIfNeeded(selectedTool: AIChatRAGTool?, attachments: [UnifiedToggleInputAttachment]) {
        guard let selectedTool else { return }
        switch selectedTool {
        case .imageGeneration:
            DailyPixel.fireDailyAndCount(
                pixel: .unifiedToggleInputImageGenerationSubmitted,
                withAdditionalParameters: ["has_reference_image": hasImageAttachment(in: attachments) ? "true" : "false"]
            )
        case .webSearch:
            DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputWebSearchSubmitted)
        default:
            break
        }
    }

    private static func hasImageAttachment(in attachments: [UnifiedToggleInputAttachment]) -> Bool {
        attachments.contains { attachment in
            if case .image = attachment { return true }
            return false
        }
    }

    private static func hasFileAttachment(in attachments: [UnifiedToggleInputAttachment]) -> Bool {
        attachments.contains { attachment in
            switch attachment {
            case .file, .invalidFile: return true
            case .image: return false
            }
        }
    }
}
