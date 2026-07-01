//
//  AIChatUserScriptMessages.swift
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

// swiftlint:disable inclusive_language
public enum AIChatUserScriptMessages: String, CaseIterable {
    case openAIChatSettings
    case getAIChatNativeConfigValues
    case closeAIChat
    case getAIChatNativePrompt
    case openAIChat
    case getAIChatNativeHandoffData
    case submitAIChatNativePrompt
    case responseState
    case showChatInput
    case hideChatInput
    case reportMetric
    case recordChat
    case restoreChat
    case removeChat
    case openSummarizationSourceLink
    case openTranslationSourceLink
    case openAIChatLink
    case responseReceived

    case getAIChatPageContext
    case submitAIChatPageContext
    /// Pushed (native→FE) to append one user text selection to the duck.ai selection-context list.
    /// Independent of the single page-context slot; the FE owns the resulting list of selections.
    case submitAIChatSelectionContext
    /// Pulled (FE→native) on chat init to fetch selections attached before the FE was ready to
    /// receive pushes — mirrors `getAIChatPageContext`. Returns the current selection list.
    case getAIChatSelectionContext
    case togglePageContextTelemetry
    case getAIChatOpenTabs
    case getAIChatTabContent
    case openKeyboard
    case storeMigrationData
    case getMigrationDataByIndex
    case getMigrationInfo
    case clearMigrationData

    case voiceSessionStarted
    case voiceSessionEnded

    /// Posted by the FE when the user creates a new chat — e.g. taps "Start new chat" in the
    /// duck.ai sidebar, or any other FE entry point. Native uses this as the single source of
    /// truth to reset host UI state (unified input, attachments) for the new chat.
    case newChatStarted
    /// Posted by the FE when `getUserMedia` rejects while attempting to start a Duck.ai
    /// voice session. Native uses this to decide whether to surface a system-permission
    /// remediation prompt (e.g. when the OS has denied microphone access to the app).
    case voiceChatStartFailed

    /// Posted by the FE when `getUserMedia` rejects while attempting to start Duck.ai
    /// dictation. Mirrors `voiceChatStartFailed` but drives dictation-specific remediation
    /// copy on the system-permission prompt.
    case dictationStartFailed

    /// Posted by the FE when a new chat is created in image-generation mode (e.g. the user
    /// tapped the sidebar's "New Image" entry). Native uses this to mirror the FE's active
    /// tool state in the Unified Input toolbar.
    case newImageGenerationChatStarted

    /// Posted by the FE when the user taps "Switch Model" on the subscription recovery card
    /// shown for an unsupported model. Native surfaces its model picker for the active chat
    /// (expands the input, reveals the model chip).
    case showModelPicker

    /// Posted by the FE while the subscription recovery card is showing for the active chat.
    case disableChatInput

    /// Posted by the FE when the subscription recovery card is dismissed for the active chat.
    case enableChatInput

    /// Posted by the FE to request focus on the native address bar (UTI).
    /// Native honors this only when the Unified Toggle Input feature is enabled.
    case focusChatInput

    // Sync
    case getSyncStatus
    case getScopedSyncAuthToken
    case encryptWithSyncMasterKey
    case decryptWithSyncMasterKey
    case sendToSyncSettings
    case sendToSetupSync
    case setAIChatHistoryEnabled
    case submitSyncStatusChanged

    /// Pushed to the duck.ai page to open the Duck.ai Settings modal.
    case submitOpenSettingsAction
}
// swiftlint:enable inclusive_language
