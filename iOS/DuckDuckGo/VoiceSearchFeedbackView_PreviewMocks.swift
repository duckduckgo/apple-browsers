//
//  VoiceSearchFeedbackView_PreviewMocks.swift
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

import SwiftUI
import DesignResourcesKitIcons
import UIComponents
import AIChat


#if DEBUG
extension VoiceSearchFeedbackViewModel {

    static func preview(preferredTarget: VoiceSearchTarget = .AIChat) -> VoiceSearchFeedbackViewModel {
        VoiceSearchFeedbackViewModel(
            speechRecognizer: PreviewMockSpeechRecognizer(),
            aiChatSettings: PreviewAIChatSettingsProvider(),
            preferredTarget: preferredTarget
        )
    }
}

private struct PreviewMockSpeechRecognizer: SpeechRecognizerProtocol {
    var isAvailable: Bool = false

    static func requestMicAccess(withHandler handler: @escaping (Bool) -> Void) { }

    func getVolumeLevel(from channelData: UnsafeMutablePointer<Float>) -> Float { 10 }

    func startRecording(resultHandler: @escaping (String?, Error?, Bool) -> Void, volumeCallback: @escaping (Float) -> Void) { }

    func stopRecording() { }
}

private final class PreviewAIChatSettingsProvider: AIChatSettingsProvider {
    let aiChatURL = URL(string: "https://duck.ai")!
    let isAIChatEnabled = true
    let sessionTimerInMinutes = 60
    let isAIChatAddressBarUserSettingsEnabled = false
    let isAIChatSearchInputUserSettingsEnabled = false
    let isAIChatSearchInputUserSettingsDisabledByUser = false
    let isAIChatBrowsingMenuUserSettingsEnabled = false
    let isAIChatVoiceSearchUserSettingsEnabled = true
    let isAIChatTabSwitcherUserSettingsEnabled = false
    let isAIChatTabBarUserSettingsEnabled = false
    let isAIChatTabBarDuckAIButtonVisible = true
    let isAIChatTabBarContextualSheetButtonVisible = true
    let isAutomaticContextAttachmentEnabled = false
    let isChatSuggestionsEnabled = false
    let defaultOmnibarMode: DefaultOmnibarMode = .search

    func enableAIChat(enable: Bool) {}
    func enableAIChatBrowsingMenuUserSettings(enable: Bool) {}
    func enableAIChatAddressBarUserSettings(enable: Bool) {}
    func enableAIChatVoiceSearchUserSettings(enable: Bool) {}
    func enableAIChatTabSwitcherUserSettings(enable: Bool) {}
    func enableAIChatTabBarUserSettings(enable: Bool) {}
    func setAIChatTabBarDuckAIButtonVisible(_ visible: Bool) {}
    func setAIChatTabBarContextualSheetButtonVisible(_ visible: Bool) {}
    func enableAIChatSearchInputUserSettings(enable: Bool) {}
    func enableAutomaticContextAttachment(enable: Bool) {}
    func enableChatSuggestions(enable: Bool) {}
    func setDefaultOmnibarMode(_ mode: DefaultOmnibarMode) {}
}
#endif
