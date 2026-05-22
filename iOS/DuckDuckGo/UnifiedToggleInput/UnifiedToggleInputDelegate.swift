//
//  UnifiedToggleInputDelegate.swift
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

@MainActor
protocol UnifiedToggleInputDelegate: AnyObject {
    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?, files: [AIChatNativePrompt.NativePromptFile]?)
    func unifiedToggleInputDidSubmitQuery(_ query: String)
    func unifiedToggleInputDidRequestVoiceSearch()
    func unifiedToggleInputDidRequestAIVoiceChat()
    func unifiedToggleInputDidRequestAIChat(prefilledText: String)
    func unifiedToggleInputDidChangeHeight()
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode)
    func unifiedToggleInputDidRequestFire()
    func unifiedToggleInputDidRequestDuckAIVoiceMode()
    /// Destination state the UTI should snap to at the start of an inline-dismiss animation.
    func unifiedToggleInputDismissSnapshot() -> UTIDismissSnapshot
    func unifiedToggleInputDidTapClearText()
    func unifiedToggleInputDidTapToActivate()
}

extension UnifiedToggleInputDelegate {
    func unifiedToggleInputDismissSnapshot() -> UTIDismissSnapshot { .empty }
    func unifiedToggleInputDidTapClearText() {}
    func unifiedToggleInputDidTapToActivate() {}
}
