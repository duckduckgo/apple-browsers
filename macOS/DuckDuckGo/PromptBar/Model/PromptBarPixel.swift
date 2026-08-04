//
//  PromptBarPixel.swift
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

/// Pixels for the Prompt Bar surface.
///
/// Every name is prefixed `aichat_promptbar_`, so the whole surface is one
/// `LIKE 'm_mac_aichat_promptbar%'`. The mirrored cases keep the tail of their `aichat_addressbar_*`
/// counterpart, so the two surfaces compare token for token — see `PromptBarPixelHandler` for the
/// mapping and the events the Prompt Bar deliberately can't produce.
enum PromptBarPixel: PixelKitEvent {

    // MARK: - Mirrored from the address bar

    /// Event Trigger: User submits a prompt from the Prompt Bar
    case submitPrompt

    /// Event Trigger: User submits a URL from the Prompt Bar
    case submitURL

    /// Event Trigger: User submits a prompt that includes one or more image attachments
    case submitWithImage(imageCount: Int)

    /// Event Trigger: User submits a prompt that includes one or more file attachments
    case submitWithFiles(fileCount: Int)

    /// Event Trigger: User attaches an image via the file picker
    case imageAttached

    /// Event Trigger: User removes an attached image
    case imageRemoved

    /// Event Trigger: User attaches a file (PDF etc.) via the file picker
    case fileAttached

    /// Event Trigger: User removes an attached file (PDF etc.) by clicking the × on the carousel card
    case fileRemoved

    /// Event Trigger: A file the user picked failed validation and was rejected
    case fileValidationFailed(reason: String)

    /// Event Trigger: User activates image generation mode via the Tools menu
    case imageGenerationActivated

    /// Event Trigger: User dismisses the image generation chip (× button)
    case imageGenerationDeactivated

    /// Event Trigger: User submits a prompt while image generation mode is active
    case imageGenerationSubmitted

    /// Event Trigger: User activates web search mode via the Tools menu
    case webSearchActivated

    /// Event Trigger: User dismisses the web search chip (× button)
    case webSearchDeactivated

    /// Event Trigger: User submits a prompt while web search mode is active
    case webSearchSubmitted

    /// Event Trigger: User selects a model from the model picker menu
    case modelSelected

    /// Event Trigger: User selects a reasoning effort from the picker
    case reasoningEffortSelected

    /// Event Trigger: User opens a new voice Duck.ai chat from the Prompt Bar
    case newVoiceChat

    // MARK: - Prompt Bar only

    /// Event Trigger: The Prompt Bar is presented by the global keyboard shortcut
    case shownFromShortcut

    /// Event Trigger: The Prompt Bar is presented by clicking the menu bar icon
    case shownFromMenuBarIcon

    /// Event Trigger: The Prompt Bar closes without a prompt, URL or voice session being handed off.
    /// `hadText` tells an abandoned prompt from an exploratory open.
    case dismissedWithoutSubmission(reason: PromptBarCancellationReason, hadText: Bool)

    /// Event Trigger: The Prompt Bar keyboard shortcut setting is turned on
    case settingsShortcutTurnedOn

    /// Event Trigger: The Prompt Bar keyboard shortcut setting is turned off
    case settingsShortcutTurnedOff

    /// Event Trigger: The Prompt Bar menu bar icon setting is turned on
    case settingsMenuBarIconTurnedOn

    /// Event Trigger: The Prompt Bar menu bar icon setting is turned off
    case settingsMenuBarIconTurnedOff

    /// Event Trigger: The recorded key combination changes, including a reset to the default.
    /// Never carries the combination itself.
    case settingsShortcutChanged

    /// Event Trigger: Fires daily when the app becomes active, reporting both Prompt Bar settings.
    /// The on/off pixels only cover users who touch a setting; this one sizes the enabled base.
    case state(shortcutEnabled: Bool, menuBarIconEnabled: Bool)

    // MARK: -

    var name: String {
        switch self {
        case .submitPrompt:
            return "aichat_promptbar_submit_prompt"
        case .submitURL:
            return "aichat_promptbar_submit_url"
        case .submitWithImage:
            return "aichat_promptbar_submit_with_image"
        case .submitWithFiles:
            return "aichat_promptbar_submit_with_files"
        case .imageAttached:
            return "aichat_promptbar_image_attached"
        case .imageRemoved:
            return "aichat_promptbar_image_removed"
        case .fileAttached:
            return "aichat_promptbar_file_attached"
        case .fileRemoved:
            return "aichat_promptbar_file_removed"
        case .fileValidationFailed:
            return "aichat_promptbar_file_validation_failed"
        case .imageGenerationActivated:
            return "aichat_promptbar_image_generation_activated"
        case .imageGenerationDeactivated:
            return "aichat_promptbar_image_generation_deactivated"
        case .imageGenerationSubmitted:
            return "aichat_promptbar_image_generation_submitted"
        case .webSearchActivated:
            return "aichat_promptbar_web_search_activated"
        case .webSearchDeactivated:
            return "aichat_promptbar_web_search_deactivated"
        case .webSearchSubmitted:
            return "aichat_promptbar_web_search_submitted"
        case .modelSelected:
            return "aichat_promptbar_model_selected"
        case .reasoningEffortSelected:
            return "aichat_promptbar_reasoning_effort_selected"
        case .newVoiceChat:
            return "aichat_promptbar_new_voice_chat"
        case .shownFromShortcut:
            return "aichat_promptbar_shown_shortcut"
        case .shownFromMenuBarIcon:
            return "aichat_promptbar_shown_menu_bar_icon"
        case .dismissedWithoutSubmission:
            return "aichat_promptbar_dismissed_without_submission"
        case .settingsShortcutTurnedOn:
            return "aichat_promptbar_settings_shortcut_on"
        case .settingsShortcutTurnedOff:
            return "aichat_promptbar_settings_shortcut_off"
        case .settingsMenuBarIconTurnedOn:
            return "aichat_promptbar_settings_menu_bar_icon_on"
        case .settingsMenuBarIconTurnedOff:
            return "aichat_promptbar_settings_menu_bar_icon_off"
        case .settingsShortcutChanged:
            return "aichat_promptbar_settings_shortcut_changed"
        case .state:
            return "aichat_promptbar_state"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .submitPrompt,
                .submitURL,
                .imageAttached,
                .imageRemoved,
                .fileAttached,
                .fileRemoved,
                .imageGenerationActivated,
                .imageGenerationDeactivated,
                .imageGenerationSubmitted,
                .webSearchActivated,
                .webSearchDeactivated,
                .webSearchSubmitted,
                .modelSelected,
                .reasoningEffortSelected,
                .newVoiceChat,
                .shownFromShortcut,
                .shownFromMenuBarIcon,
                .settingsShortcutTurnedOn,
                .settingsShortcutTurnedOff,
                .settingsMenuBarIconTurnedOn,
                .settingsMenuBarIconTurnedOff,
                .settingsShortcutChanged:
            return nil
        case .submitWithImage(let imageCount):
            return ["imageCount": String(imageCount)]
        case .submitWithFiles(let fileCount):
            return ["fileCount": String(fileCount)]
        case .fileValidationFailed(let reason):
            return ["reason": reason]
        case .dismissedWithoutSubmission(let reason, let hadText):
            return ["reason": reason.rawValue, "had_text": String(hadText)]
        case .state(let shortcutEnabled, let menuBarIconEnabled):
            return ["shortcut_enabled": String(shortcutEnabled),
                    "menu_bar_icon_enabled": String(menuBarIconEnabled)]
        }
    }

    /// Matches the address bar pixels, so a surface breakdown stays comparable.
    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}

/// The `reason` parameter on `aichat_promptbar_dismissed_without_submission`.
enum PromptBarCancellationReason: String, Equatable, CaseIterable {
    case escape
    case clickOutside = "click_outside"
    case shortcutToggle = "shortcut_toggle"
    case menuBarIcon = "menu_bar_icon"
}
