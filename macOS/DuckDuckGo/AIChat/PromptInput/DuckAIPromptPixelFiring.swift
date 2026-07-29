//
//  DuckAIPromptPixelFiring.swift
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

/// Named after the action rather than the pixel, so each surface can report it under its own name.
enum DuckAIPromptPixelEvent: Equatable {
    case promptSubmitted
    case urlSubmitted
    case imageGenerationSubmitted
    case webSearchSubmitted
    case submittedWithImages(count: Int)
    case submittedWithFiles(count: Int)
    case submittedWithTabs(count: Int)
    case imageGenerationActivated
    case imageGenerationDeactivated
    case webSearchActivated
    case webSearchDeactivated
    case customizeResponsesOpened
    case imageAttached
    case imageRemoved
    case fileAttached
    case fileRemoved
    case fileValidationFailed(reason: String)
    case tabAttachmentRemoved
    case tabPickerShown
    case tabChosen
    case tabPickerCanceled
    case modelSelected
    case reasoningEffortSelected
    case subscriptionUpsellTriggered(currentTier: String, requiredTier: String, flowType: String)
    case voiceChatOpened
}

protocol DuckAIPromptPixelFiring {
    func fire(_ event: DuckAIPromptPixelEvent)
}

struct AddressBarPromptPixelHandler: DuckAIPromptPixelFiring {

    func fire(_ event: DuckAIPromptPixelEvent) {
        switch event {
        case .voiceChatOpened:
            PixelKit.fire(AIChatPixel.aiChatNewVoiceChatOmnibarNative, frequency: .dailyAndStandard, includeAppVersionParameter: true)
        default:
            guard let pixel = Self.addressBarPixel(for: event) else { return }
            PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
        }
    }

    static func addressBarPixel(for event: DuckAIPromptPixelEvent) -> AIChatPixel? {
        switch event {
        case .promptSubmitted: .aiChatAddressBarAIChatSubmitPrompt
        case .urlSubmitted: .aiChatAddressBarAIChatSubmitURL
        case .imageGenerationSubmitted: .aiChatAddressBarImageGenerationSubmitted
        case .webSearchSubmitted: .aiChatAddressBarWebSearchSubmitted
        case .submittedWithImages(let count): .aiChatAddressBarSubmitWithImage(imageCount: count)
        case .submittedWithFiles(let count): .aiChatAddressBarSubmitWithFiles(fileCount: count)
        case .submittedWithTabs(let count): .aiChatAddressBarSubmitWithTabs(tabCount: count)
        case .imageGenerationActivated: .aiChatAddressBarImageGenerationActivated
        case .imageGenerationDeactivated: .aiChatAddressBarImageGenerationDeactivated
        case .webSearchActivated: .aiChatAddressBarWebSearchActivated
        case .webSearchDeactivated: .aiChatAddressBarWebSearchDeactivated
        case .customizeResponsesOpened: .aiChatAddressBarCustomizeResponsesOpened
        case .imageAttached: .aiChatAddressBarImageAttached
        case .imageRemoved: .aiChatAddressBarImageRemoved
        case .fileAttached: .aiChatAddressBarFileAttached
        case .fileRemoved: .aiChatAddressBarFileRemoved
        case .fileValidationFailed(let reason): .aiChatAddressBarFileValidationFailed(reason: reason)
        case .tabAttachmentRemoved: .aiChatAddressBarAttachTabRemoved
        case .tabPickerShown: .aiChatAddressBarAttachTabsPickerShown
        case .tabChosen: .aiChatAddressBarAttachTabChosen
        case .tabPickerCanceled: .aiChatAddressBarAttachPickerCanceled
        case .modelSelected: .aiChatAddressBarModelSelected
        case .reasoningEffortSelected: .aiChatAddressBarReasoningEffortSelected
        case .subscriptionUpsellTriggered(let currentTier, let requiredTier, let flowType):
            .aiChatAddressBarSubscriptionUpsellTriggered(currentTier: currentTier, requiredTier: requiredTier, flowType: flowType)
        case .voiceChatOpened: nil
        }
    }
}
