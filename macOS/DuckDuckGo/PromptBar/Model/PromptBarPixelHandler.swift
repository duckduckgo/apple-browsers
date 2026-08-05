//
//  PromptBarPixelHandler.swift
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
import PixelKit

/// Reports the shared prompt events under the Prompt Bar's own names, so its numbers stay separable
/// from the address bar's rather than folding into them.
struct PromptBarPixelHandler: DuckAIPromptPixelFiring {

    func fire(_ event: DuckAIPromptPixelEvent) {
        guard let pixel = Self.promptBarPixel(for: event) else { return }

        switch pixel {
        case .newVoiceChat:
            // The frequency its address bar counterpart uses.
            PixelKit.fire(pixel, frequency: .dailyAndStandard, includeAppVersionParameter: true)
        default:
            PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
        }
    }

    /// `nil` for events this surface can't produce, per `DuckAIPromptSurface`: page context (tab and
    /// `@`-mention attachments), Customize Responses and the subscription upsell are all off on the
    /// Prompt Bar, so counting them would define a pixel that never fires.
    static func promptBarPixel(for event: DuckAIPromptPixelEvent) -> PromptBarPixel? {
        switch event {
        case .promptSubmitted: .submitPrompt
        case .urlSubmitted: .submitURL
        case .imageGenerationSubmitted: .imageGenerationSubmitted
        case .webSearchSubmitted: .webSearchSubmitted
        case .submittedWithImages(let count): .submitWithImage(imageCount: count)
        case .submittedWithFiles(let count): .submitWithFiles(fileCount: count)
        case .imageGenerationActivated: .imageGenerationActivated
        case .imageGenerationDeactivated: .imageGenerationDeactivated
        case .webSearchActivated: .webSearchActivated
        case .webSearchDeactivated: .webSearchDeactivated
        case .imageAttached: .imageAttached
        case .imageRemoved: .imageRemoved
        case .fileAttached: .fileAttached
        case .fileRemoved: .fileRemoved
        case .fileValidationFailed(let reason): .fileValidationFailed(reason: reason)
        case .modelSelected: .modelSelected
        case .reasoningEffortSelected: .reasoningEffortSelected
        case .modelPickerShown: .modelPickerShown(origin: SubscriptionFunnelOrigin.promptBarModelPicker.rawValue)
        case .reasoningPickerShown: .reasoningPickerShown(origin: SubscriptionFunnelOrigin.promptBarReasoningDropdown.rawValue)
        case .voiceChatOpened: .newVoiceChat
        case .submittedWithTabs,
                .tabAttachmentRemoved,
                .tabPickerShown,
                .tabChosen,
                .tabPickerCanceled,
                .customizeResponsesOpened,
                .subscriptionUpsellTriggered:
            nil
        }
    }
}
