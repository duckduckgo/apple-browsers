//
//  AIChatDeepLinkHandler.swift
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

import Foundation
import Core
import AIChat
import PixelKit

protocol AIChatDeepLinkPresenting: UIViewController {
    func openAIVoiceChatFromDeepLink(source: AIChatEntryPointSource)
    func openAIChat(
        source: AIChatEntryPointSource,
        _ query: String?,
        autoSend: Bool,
        payload: Any?,
        flowType: AIChatOnboardingFlowType,
        tools: [AIChatRAGTool]?,
        modelId: String?,
        reasoningEffort: AIChatReasoningEffort?,
        images: [AIChatNativePrompt.NativePromptImage]?,
        files: [AIChatNativePrompt.NativePromptFile]?,
        reportsNewTab: Bool?,
        fromDeepLink: Bool
    )
}

extension AIChatDeepLinkPresenting {

    func openAIChat(fromDeepLink: Bool, source: AIChatEntryPointSource = .deepLinkOther) {
        openAIChat(
            source: source,
            nil,
            autoSend: false,
            payload: nil,
            flowType: .default,
            tools: nil,
            modelId: nil,
            reasoningEffort: nil,
            images: nil,
            files: nil,
            reportsNewTab: nil,
            fromDeepLink: fromDeepLink
        )
    }
    
}

struct AIChatDeepLinkHandler {

    /// Handles AI Chat deep links (text and voice), dismissing any presented modal first.
    func handleDeepLink(_ url: URL, on mainViewController: AIChatDeepLinkPresenting, voiceMode: Bool = false) {
        if voiceMode {
            fireAIVoiceChatPixel(url)
        } else {
            firePixel(url)
        }

        // Widget, Control Center and lock-screen entries carry their own source, so they land on
        // `m_aichat_entry_point` as themselves rather than collapsing into `deep_link_other`.
        let source = AIChatEntryPointSource.forDeepLink(url)
        mainViewController.dismiss(animated: true) {
            if voiceMode {
                mainViewController.openAIVoiceChatFromDeepLink(source: source)
            } else {
                mainViewController.openAIChat(fromDeepLink: true, source: source)
            }
        }
    }

    private func fireAIVoiceChatPixel(_ url: URL) {
        if let source = url.getParameter(named: WidgetSourceType.sourceKey) {
            PixelKit.fire(Pixel.Event.voiceEntryPointTapped, options: .parameters([PixelParameters.source: source]))
        }
    }

    func firePixel(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let queryItems = components.queryItems
        if let sourceItem = queryItems?.first(where: { $0.name == WidgetSourceType.sourceKey }) {
            switch sourceItem.value {
            case WidgetSourceType.quickActions.rawValue:
                PixelKit.fire(Pixel.Event.openAIChatFromWidgetQuickAction, frequency: .dailyAndCount)
            case WidgetSourceType.favorite.rawValue:
                PixelKit.fire(Pixel.Event.openAIChatFromWidgetFavorite, frequency: .dailyAndCount)
            case WidgetSourceType.lockscreenComplication.rawValue:
                PixelKit.fire(Pixel.Event.openAIChatFromWidgetLockScreenComplication, frequency: .dailyAndCount)
            case WidgetSourceType.controlCenter.rawValue:
                PixelKit.fire(Pixel.Event.openAIChatFromWidgetControlCenter, frequency: .dailyAndCount)
            default:
                break
            }
        }
    }
}
