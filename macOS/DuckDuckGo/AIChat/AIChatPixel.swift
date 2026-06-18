//
//  AIChatPixel.swift
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
import PixelKit

/// This enum keeps pixels related to AI Chat (duck.ai)
/// > Related links:
/// [Original Pixel Triage](https://app.asana.com/0/69071770703008/1208619053222285/f)
/// [Omnibar and Settings Pixel Triage](https://app.asana.com/0/1204167627774280/1209885580000745)
/// [Sidebar Pixel Triage](https://app.asana.com/1/137249556945/project/1209671977594486/task/1210676151750614)
/// [Summarization Pixel Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210636012460969?focus=true)

enum AIChatPixel: PixelKitEvent {

    /// Event Trigger: AI Chat is opened via the ... Menu -> New Duck.ai Chat
    case aichatApplicationMenuAppClicked

    /// Event Trigger: AI Chat is opened via File -> New Duck.ai Chat
    case aichatApplicationMenuFileClicked

    /// Event Trigger: Can't find privacy config settings for AI Chat
    /// Anomaly Investigation:
    /// - Check if this is not a widespread issue. Sometimes users can change config data manually on macOS which could cause this
    case aichatNoRemoteSettingsFound(AIChatRemoteSettings.SettingsValue)

    /// Event Trigger: Global toggle for all AI Chat features is turned on
    case aiChatSettingsGlobalToggleTurnedOn

    /// Event Trigger: Global toggle for all AI Chat features is turned off
    case aiChatSettingsGlobalToggleTurnedOff

    /// Event Trigger: New Tab Page shortcut for AI Chat is turned on
    case aiChatSettingsNewTabPageShortcutTurnedOn

    /// Event Trigger: New Tab Page shortcut for AI Chat is turned off
    case aiChatSettingsNewTabPageShortcutTurnedOff

    /// Event Trigger: Address bar shortcut for AI Chat is turned on
    case aiChatSettingsAddressBarShortcutTurnedOn

    /// Event Trigger: Address bar shortcut for AI Chat is turned off
    case aiChatSettingsAddressBarShortcutTurnedOff

    /// Event Trigger: Address bar typing shortcut for AI Chat is turned on
    case aiChatSettingsAddressBarTypingShortcutTurnedOn

    /// Event Trigger: Address bar typing shortcut for AI Chat is turned off
    case aiChatSettingsAddressBarTypingShortcutTurnedOff

    /// Event Trigger: Application menu shortcut for AI Chat is turned off
    case aiChatSettingsApplicationMenuShortcutTurnedOff

    /// Event Trigger: Application menu shortcut for AI Chat is turned on
    case aiChatSettingsApplicationMenuShortcutTurnedOn

    /// Event Trigger: Duck.ai settings panel is displayed
    ///
    /// - Note:
    /// This pixel is used in place of `SettingsPixel.settingsPaneOpened(.aiChat)`.
    /// Before removing it, verify that it's not needed for measuring settings interaction.
    case aiChatSettingsDisplayed

    /// Event Trigger: Data Clearing setting to auto-clear Duck.ai chat history is toggled.
    case aiChatAutoClearHistorySettingToggled(enabled: Bool)

    /// Event Trigger: User clicks in the Omnibar duck.ai button
    case aiChatAddressBarButtonClicked(action: AIChatAddressBarAction)

    // MARK: - Sidebar

    /// Event Trigger: User opens a tab sidebar
    case aiChatSidebarOpened(source: AIChatSidebarOpenSource, shouldAutomaticallySendPageContext: Bool?, minutesSinceSidebarHidden: Int?)

    /// Event Trigger: User closes a tab sidebar
    case aiChatSidebarClosed(source: AIChatSidebarCloseSource)

    /// Event Trigger: User expands the sidebar to a full-size tab
    case aiChatSidebarExpanded

    /// Event Trigger: User changes sidebar setting in AI Features settings
    /// This is a unique pixel (sent once per app installation)
    case aiChatSidebarSettingChanged

    /// Event Trigger: User finishes dragging the sidebar resize grip (after 500 ms debounce)
    case aiChatSidebarResized(width: Int)

    /// Event Trigger: User detaches the sidebar into a floating window.
    case aiChatSidebarDetached

    /// Event Trigger: User re-docks a floating window using the attach button.
    case aiChatSidebarAttached

    /// Event Trigger: User closes a floating window via its close button.
    case aiChatSidebarFloatingClosed

    /// Event Trigger: User clicks the floating title to activate associated tab.
    case aiChatSidebarFloatingTabActivated

    /// Event Trigger: User clicks the Duck.ai button in the tab bar to open a new chat tab.
    case aiChatTabbarButtonClicked

    // MARK: - Summarization

    /// Event Trigger: User triggers summarize action (either via keyboard shortcut or a context menu action)
    case aiChatSummarizeText(source: AIChatTextSummarizationRequest.Source)

    /// Event Trigger: User clicks the website link on a summarize prompt in Duck.ai tab or sidebar
    case aiChatSummarizeSourceLinkClicked

    /// Event Trigger: User triggers translate action
    case aiChatTranslateText

    /// Event Trigger: User clicks the website link on a translation prompt in Duck.ai tab or sidebar
    case aiChatTranslationSourceLinkClicked

    /// Event Trigger: User clicks the website link on a page context prompt in Duck.ai tab or sidebar
    case aiChatPageContextSourceLinkClicked

    /// Event Trigger: User adds page context to the prompt using a button in the input field
    case aiChatPageContextAdded(automaticEnabled: Bool)

    /// Event Trigger: User removes page context from the prompt using a button in the input field
    case aiChatPageContextRemoved(automaticEnabled: Bool)

    // MARK: - Deleting chat history

    /// Event Trigger: User requests to delete Duck.ai chat history from the fire button or history delete dialog
    case aiChatDeleteHistoryRequested

    /// Event Trigger: Duck.ai chat history is deleted successfully
    case aiChatDeleteHistorySuccessful

    /// Event Trigger: Duck.ai chat history fails to be deleted
    case aiChatDeleteHistoryFailed

    // MARK: - Address bar toggle pixels

    /// Event Trigger: User selects address bar and toggle settings is ON (duck.ai mode)
    case aiChatAddressBarActivatedToggleOn

    /// Event Trigger: User selects address bar and toggle settings is OFF (search mode)
    case aiChatAddressBarActivatedToggleOff

    /// Event Trigger: User changes toggle to duck.ai
    case aiChatAddressBarToggleChangedAIChat

    /// Event Trigger: User changes toggle to search
    case aiChatAddressBarToggleChangedSearch

    /// Event Trigger: User submits prompt from duck.ai panel
    case aiChatAddressBarAIChatSubmitPrompt

    /// Event Trigger: User submits URL from duck.ai panel
    case aiChatAddressBarAIChatSubmitURL

    /// Event Trigger: User submits a prompt from the suggestion for duck.ai by clicking with the mouse
    case aiChatSuggestionAIChatSubmittedMouse

    /// Event Trigger: User submits a prompt from the suggestion for duck.ai by pressing enter
    case aiChatSuggestionAIChatSubmittedKeyboard

    /// Event Trigger: User selects a pinned recent chat by clicking with the mouse
    case aiChatRecentChatSelectedPinnedMouse

    /// Event Trigger: User selects a pinned recent chat by pressing enter
    case aiChatRecentChatSelectedPinnedKeyboard

    /// Event Trigger: User selects a non-pinned recent chat by clicking with the mouse
    case aiChatRecentChatSelectedMouse

    /// Event Trigger: User selects a non-pinned recent chat by pressing enter
    case aiChatRecentChatSelectedKeyboard

    // MARK: - Recent chat deletion

    /// Event Trigger: User clicks the delete button on a recent chat suggestion in the address bar
    case aiChatRecentChatDeleteButtonClicked

    /// Event Trigger: User confirms deletion of a recent chat suggestion in the address bar
    case aiChatRecentChatDeleteConfirmed

    /// Event Trigger: User cancels deletion of a recent chat suggestion in the address bar
    case aiChatRecentChatDeleteCancelled

    case aiChatSyncScopedSyncTokenError(reason: String)
    case aiChatSyncEncryptionError(reason: String)
    case aiChatSyncDecryptionError(reason: String)
    case aiChatSyncHistoryEnabledError(reason: String)

    case aiChatTermsAcceptedDuplicateSyncOff
    case aiChatTermsAcceptedDuplicateSyncOn
    case aiChatReportMetricDecodeError(NSError?, failureReason: AIChatUserScriptErrorFailureReason)

    // MARK: - Image Attachments

    /// Event Trigger: User attaches an image via the file picker in the duck.ai omnibar
    case aiChatAddressBarImageAttached

    /// Event Trigger: User removes an attached image in the duck.ai omnibar
    case aiChatAddressBarImageRemoved

    /// Event Trigger: User submits a prompt that includes one or more image attachments
    case aiChatAddressBarSubmitWithImage(imageCount: Int)

    /// Event Trigger: User submits a prompt that includes one or more page-content tab
    /// attachments via the omnibar's Attach Page Content menu.
    case aiChatAddressBarSubmitWithTabs(tabCount: Int)

    /// Event Trigger: User attaches a file (PDF etc.) via the file picker in the duck.ai omnibar.
    case aiChatAddressBarFileAttached

    /// Event Trigger: User removes an attached file (PDF etc.) in the duck.ai omnibar by clicking
    /// the × on the carousel card.
    case aiChatAddressBarFileRemoved

    /// Event Trigger: A file the user picked for the duck.ai omnibar failed validation and was
    /// rejected (too large, too many pages, unsupported type, encrypted, or unreadable). `reason`
    /// mirrors the iOS `m_aichat_unified_input_file_validation_failed` reason values.
    case aiChatAddressBarFileValidationFailed(reason: String)

    /// Event Trigger: User submits a prompt that includes one or more file attachments.
    case aiChatAddressBarSubmitWithFiles(fileCount: Int)

    // MARK: - Tab Attachments

    /// Event Trigger: User opens the duck.ai omnibar attach menu's "Add Page Content" submenu.
    case aiChatAddressBarAttachTabsPickerShown

    /// Event Trigger: User toggles a tab ON inside the "Add Page Content" submenu, adding
    /// that tab's page content as an attachment.
    case aiChatAddressBarAttachTabChosen

    /// Event Trigger: User toggles a tab OFF inside the "Add Page Content" submenu, removing
    /// that tab's page content attachment.
    case aiChatAddressBarAttachTabRemoved

    /// Event Trigger: User dismisses the "Add Page Content" submenu without toggling any tab
    /// during that open session (no chosen / removed events fired between open and close).
    case aiChatAddressBarAttachPickerCanceled

    /// Event Trigger: The duck.ai omnibar's `@`-mention tab picker appears — user typed `@`
    /// and the picker transitioned from hidden to visible.
    case aiChatAddressBarMentionPickerShown

    /// Event Trigger: User picks a previously-unattached tab in the `@`-mention picker.
    case aiChatAddressBarMentionTabChosen

    /// Event Trigger: User picks an already-attached tab in the `@`-mention picker, removing
    /// that tab's page-content attachment.
    case aiChatAddressBarMentionTabRemoved

    /// Event Trigger: User dismisses the `@`-mention picker without accepting any row
    /// (Esc, click outside, caret leaves the `@`-token, etc.).
    case aiChatAddressBarMentionPickerCanceled

    // MARK: - Model Picker

    /// Event Trigger: User selects a model from the model picker menu
    case aiChatAddressBarModelSelected

    /// Event Trigger: User selects a reasoning effort from the native omnibar picker
    case aiChatAddressBarReasoningEffortSelected

    /// Event Trigger: User opens a new voice Duck.ai chat from the native omnibar
    case aiChatNewVoiceChatOmnibarNative

    // MARK: - Image Generation Mode

    /// Event Trigger: User activates image generation mode via the Tools menu
    case aiChatAddressBarImageGenerationActivated

    /// Event Trigger: User dismisses the image generation chip (× button)
    case aiChatAddressBarImageGenerationDeactivated

    /// Event Trigger: User submits a prompt while image generation mode is active
    case aiChatAddressBarImageGenerationSubmitted

    // MARK: - Web Search Mode

    /// Event Trigger: User activates web search mode via the Tools menu
    case aiChatAddressBarWebSearchActivated

    /// Event Trigger: User dismisses the web search chip (× button)
    case aiChatAddressBarWebSearchDeactivated

    /// Event Trigger: User submits a prompt while web search mode is active
    case aiChatAddressBarWebSearchSubmitted

    /// Event Trigger: User submits a prompt with images from the New Tab Page omnibar
    case aiChatNtpSubmitWithImage(imageCount: Int)

    /// Event Trigger: User selects a model from the New Tab Page model picker
    case aiChatNtpModelSelected

    /// Event Trigger: User selects a reasoning effort from the New Tab Page omnibar picker
    case aiChatNtpReasoningEffortSelected

    /// Event Trigger: User taps "View all chats" from the New Tab Page omnibar
    case aiChatNtpViewAllChatsClicked

    /// Event Trigger: User opens a new voice Duck.ai chat from the New Tab Page omnibar
    case aiChatNewVoiceChatOmnibarNtp

    // MARK: - NTP Image Generation Mode

    /// Event Trigger: User submits a prompt while image generation mode is active on the New Tab Page
    case aiChatNtpImageGenerationSubmitted

    // MARK: - NTP Web Search Mode

    /// Event Trigger: User submits a prompt while web search mode is active on the New Tab Page
    case aiChatNtpWebSearchSubmitted

    /// Event Trigger: User taps "View all chats" from the native address bar omnibar
    case aiChatViewAllChatsClicked

    /// Event Trigger: Models API fetch fails (endpoint unreachable or returns error)
    case aiChatModelsFetchFailed

    // MARK: - Prompt Metrics

    /// Event Trigger: User submits their first prompt in a new Duck.ai conversation
    case aiChatMetricStartNewConversation

    /// Event Trigger: User submits a prompt in an ongoing Duck.ai conversation
    case aiChatMetricSentPromptOngoingChat

    // MARK: - Onboarding

    /// Event Trigger: User enables the Duck.ai toggle during onboarding
    case aiChatOnboardingTogglePreferenceOn

    /// Event Trigger: User disables the Duck.ai toggle during onboarding
    case aiChatOnboardingTogglePreferenceOff

    /// Event Trigger: User completes onboarding with the Duck.ai toggle enabled
    case aiChatOnboardingFinishedToggleOn

    /// Event Trigger: User completes onboarding with the Duck.ai toggle disabled
    case aiChatOnboardingFinishedToggleOff

    // MARK: - Main menu

    /// Event Trigger: User taps Open Duck.ai from the main menu
    case aiChatOpenDuckAiMainMenu

    /// Event Trigger: User opens a new Duck.ai chat from the main menu
    case aiChatNewChatMainMenu

    /// Event Trigger: User opens a new Duck.ai voice chat from the main menu
    case aiChatNewVoiceChatMainMenu

    /// Event Trigger: User opens a new Duck.ai image chat from the main menu
    case aiChatNewImageChatMainMenu

    /// Event Trigger: User selects a recent chat from the main menu
    case aiChatRecentChatSelectedMainMenu

    /// Event Trigger: User confirms Delete All Chats from the main menu
    case aiChatDeleteAllChatsMainMenu

    // MARK: - More options menu

    /// Event Trigger: User taps Open Duck.ai from the more options menu
    case aiChatOpenDuckAiMoreOptionsMenu

    /// Event Trigger: User opens a new Duck.ai chat from the more options menu
    case aiChatNewChatMoreOptionsMenu

    /// Event Trigger: User opens a new Duck.ai voice chat from the more options menu
    case aiChatNewVoiceChatMoreOptionsMenu

    /// Event Trigger: User opens a new Duck.ai image chat from the more options menu
    case aiChatNewImageChatMoreOptionsMenu

    /// Event Trigger: User selects a recent chat from the more options menu
    case aiChatRecentChatSelectedMoreOptionsMenu

    /// Event Trigger: User confirms Delete All Chats from the more options menu
    case aiChatDeleteAllChatsMoreOptionsMenu

    /// Event Trigger: User taps "View All Chats..." from the main menu
    case aiChatViewAllChatsMainMenu

    /// Event Trigger: User taps "View All Chats..." from the more options menu
    case aiChatViewAllChatsMoreOptionsMenu

    /// Event Trigger: Duck.ai tab WebKit process terminates
    case aiChatTabDidTerminate(error: Error)

    // MARK: - Daily

    /// Event Trigger: Fires daily when the app becomes active, reporting whether AI Chat features are enabled or disabled
    case aiChatIsEnabled(isEnabled: Bool)

    /// Event Trigger: The Duck.ai FE reported that `getUserMedia()` rejected while attempting
    /// to start a voice chat. `reason` distinguishes the case we acted on (`mic_os_denied`)
    /// from anything else (`other`) — useful for measuring how often the FE hook fires for
    /// unrelated WebKit failures and for sizing the OS-deny remediation funnel.
    case aiChatVoiceChatStartFailed(reason: AIChatVoiceChatStartFailedReason)

    // MARK: -

    var name: String {
        switch self {
        case .aichatApplicationMenuAppClicked:
            return "aichat_application-menu-app-clicked"
        case .aichatApplicationMenuFileClicked:
            return "aichat_application-menu-file-clicked"
        case .aichatNoRemoteSettingsFound(let settings):
            return "aichat_no_remote_settings_found-\(settings.rawValue.lowercased())"
        case .aiChatSettingsGlobalToggleTurnedOn:
            return "aichat_settings_global-toggle_on"
        case .aiChatSettingsGlobalToggleTurnedOff:
            return "aichat_settings_global-toggle_off"
        case .aiChatSettingsNewTabPageShortcutTurnedOn:
            return "aichat_settings_new-tab-page_on"
        case .aiChatSettingsNewTabPageShortcutTurnedOff:
            return "aichat_settings_new-tab-page_off"
        case .aiChatSettingsAddressBarShortcutTurnedOn:
            return "aichat_settings_addressbar_on"
        case .aiChatSettingsAddressBarShortcutTurnedOff:
            return "aichat_settings_addressbar_off"
        case .aiChatSettingsAddressBarTypingShortcutTurnedOn:
            return "aichat_settings_addressbar_typing_on"
        case .aiChatSettingsAddressBarTypingShortcutTurnedOff:
            return "aichat_settings_addressbar_typing_off"
        case .aiChatSettingsApplicationMenuShortcutTurnedOff:
            return "aichat_settings_application_menu_off"
        case .aiChatSettingsApplicationMenuShortcutTurnedOn:
            return "aichat_settings_application_menu_on"
        case .aiChatSettingsDisplayed:
            return "aichat_settings_displayed"
        case .aiChatAddressBarButtonClicked:
            return "aichat_addressbar_button_clicked"
        case .aiChatSidebarOpened:
            return "aichat_sidebar_opened"
        case .aiChatSidebarClosed:
            return "aichat_sidebar_closed"
        case .aiChatSidebarExpanded:
            return "aichat_sidebar_expanded"
        case .aiChatSidebarSettingChanged:
            return "aichat_sidebar_setting_changed_u"
        case .aiChatSidebarResized:
            return "aichat_sidebar_resized"
        case .aiChatSidebarDetached:
            return "aichat_sidebar_detached"
        case .aiChatSidebarAttached:
            return "aichat_sidebar_attached"
        case .aiChatSidebarFloatingClosed:
            return "aichat_sidebar_floating_closed"
        case .aiChatSidebarFloatingTabActivated:
            return "aichat_sidebar_floating_tab_activated"
        case .aiChatTabbarButtonClicked:
            return "aichat_tabbar_button_clicked"
        case .aiChatSummarizeText:
            return "aichat_summarize_text"
        case .aiChatSummarizeSourceLinkClicked:
            return "aichat_summarize_source_link_clicked"
        case .aiChatTranslateText:
            return "aichat_translate_text"
        case .aiChatTranslationSourceLinkClicked:
            return "aichat_translation_source_link_clicked"
        case .aiChatPageContextSourceLinkClicked:
            return "aichat_page_context_source_link_clicked"
        case .aiChatPageContextAdded:
            return "aichat_page_context_added"
        case .aiChatPageContextRemoved:
            return "aichat_page_context_removed"
        case let .aiChatAutoClearHistorySettingToggled(enabled):
            if enabled {
                return "m_mac_aichat_history_autoclear_enabled"
            } else {
                return "m_mac_aichat_history_autoclear_disabled"
            }
        case .aiChatDeleteHistoryRequested:
            return "m_mac_aichat_history_delete_requested"
        case .aiChatDeleteHistorySuccessful:
            return "m_mac_aichat_history_delete_successful"
        case .aiChatDeleteHistoryFailed:
            return "m_mac_aichat_history_delete_failed"
        case .aiChatAddressBarActivatedToggleOn:
            return "aichat_addressbar_activated_toggle_on"
        case .aiChatAddressBarActivatedToggleOff:
            return "aichat_addressbar_activated_toggle_off"
        case .aiChatAddressBarToggleChangedAIChat:
            return "aichat_addressbar_toggle_changed_aichat"
        case .aiChatAddressBarToggleChangedSearch:
            return "aichat_addressbar_toggle_changed_search"
        case .aiChatAddressBarAIChatSubmitPrompt:
            return "aichat_addressbar_aichat_submit_prompt"
        case .aiChatAddressBarAIChatSubmitURL:
            return "aichat_addressbar_aichat_submit_url"
        case .aiChatSuggestionAIChatSubmittedMouse:
            return "aichat_suggestion_aichat_submitted_mouse"
        case .aiChatSuggestionAIChatSubmittedKeyboard:
            return "aichat_suggestion_aichat_submitted_keyboard"
        case .aiChatRecentChatSelectedPinnedMouse:
            return "aichat_recent_chat_selected_pinned_mouse"
        case .aiChatRecentChatSelectedPinnedKeyboard:
            return "aichat_recent_chat_selected_pinned_keyboard"
        case .aiChatRecentChatSelectedMouse:
            return "aichat_recent_chat_selected_mouse"
        case .aiChatRecentChatSelectedKeyboard:
            return "aichat_recent_chat_selected_keyboard"
        case .aiChatRecentChatDeleteButtonClicked:
            return "aichat_recent_chat_delete_button_clicked"
        case .aiChatRecentChatDeleteConfirmed:
            return "aichat_recent_chat_delete_confirmed"
        case .aiChatRecentChatDeleteCancelled:
            return "aichat_recent_chat_delete_cancelled"

        case .aiChatSyncScopedSyncTokenError:
            return "aichat_sync_internal_scoped-sync-token-error"
        case .aiChatSyncEncryptionError:
            return "aichat_sync_internal_encryption-error"
        case .aiChatSyncDecryptionError:
            return "aichat_sync_internal_decryption-error"
        case .aiChatSyncHistoryEnabledError:
            return "aichat_sync_internal_history_enabled-error"
        case .aiChatTermsAcceptedDuplicateSyncOff:
            return "aichat_terms_accepted_duplicate_sync_off"
        case .aiChatTermsAcceptedDuplicateSyncOn:
            return "aichat_terms_accepted_duplicate_sync_on"
        case .aiChatReportMetricDecodeError:
            return "aichat_report_metric_decode_error"
        case .aiChatOnboardingTogglePreferenceOn:
            return "aichat_onboarding_toggle_preference_on"
        case .aiChatOnboardingTogglePreferenceOff:
            return "aichat_onboarding_toggle_preference_off"
        case .aiChatOnboardingFinishedToggleOn:
            return "aichat_onboarding_finished_toggle_on"
        case .aiChatOnboardingFinishedToggleOff:
            return "aichat_onboarding_finished_toggle_off"
        case .aiChatAddressBarImageAttached:
            return "aichat_addressbar_image_attached"
        case .aiChatAddressBarImageRemoved:
            return "aichat_addressbar_image_removed"
        case .aiChatAddressBarSubmitWithImage:
            return "aichat_addressbar_submit_with_image"
        case .aiChatAddressBarSubmitWithTabs:
            return "aichat_addressbar_submit_with_tabs"
        case .aiChatAddressBarFileAttached:
            return "aichat_addressbar_file_attached"
        case .aiChatAddressBarFileRemoved:
            return "aichat_addressbar_file_removed"
        case .aiChatAddressBarFileValidationFailed:
            return "aichat_addressbar_file_validation_failed"
        case .aiChatAddressBarSubmitWithFiles:
            return "aichat_addressbar_submit_with_files"
        case .aiChatAddressBarAttachTabsPickerShown:
            return "aichat_addressbar_attach_tabs_picker_shown"
        case .aiChatAddressBarAttachTabChosen:
            return "aichat_addressbar_attach_tab_chosen"
        case .aiChatAddressBarAttachTabRemoved:
            return "aichat_addressbar_attach_tab_removed"
        case .aiChatAddressBarAttachPickerCanceled:
            return "aichat_addressbar_attach_picker_canceled"
        case .aiChatAddressBarMentionPickerShown:
            return "aichat_addressbar_mention_picker_shown"
        case .aiChatAddressBarMentionTabChosen:
            return "aichat_addressbar_mention_tab_chosen"
        case .aiChatAddressBarMentionTabRemoved:
            return "aichat_addressbar_mention_tab_removed"
        case .aiChatAddressBarMentionPickerCanceled:
            return "aichat_addressbar_mention_picker_canceled"
        case .aiChatAddressBarModelSelected:
            return "aichat_addressbar_model_selected"
        case .aiChatAddressBarReasoningEffortSelected:
            return "aichat_addressbar_reasoning_effort_selected"
        case .aiChatNewVoiceChatOmnibarNative:
            return "aichat_new_voice_chat_omnibar_native"
        case .aiChatAddressBarImageGenerationActivated:
            return "aichat_addressbar_image_generation_activated"
        case .aiChatAddressBarImageGenerationDeactivated:
            return "aichat_addressbar_image_generation_deactivated"
        case .aiChatAddressBarImageGenerationSubmitted:
            return "aichat_addressbar_image_generation_submitted"
        case .aiChatAddressBarWebSearchActivated:
            return "aichat_addressbar_web_search_activated"
        case .aiChatAddressBarWebSearchDeactivated:
            return "aichat_addressbar_web_search_deactivated"
        case .aiChatAddressBarWebSearchSubmitted:
            return "aichat_addressbar_web_search_submitted"
        case .aiChatNtpSubmitWithImage:
            return "aichat_ntp_submit_with_image"
        case .aiChatNtpModelSelected:
            return "aichat_ntp_model_selected"
        case .aiChatNtpReasoningEffortSelected:
            return "aichat_ntp_reasoning_effort_selected"
        case .aiChatNtpViewAllChatsClicked:
            return "aichat_ntp_view_all_chats_clicked"
        case .aiChatNewVoiceChatOmnibarNtp:
            return "aichat_new_voice_chat_omnibar_ntp"
        case .aiChatNtpImageGenerationSubmitted:
            return "aichat_ntp_image_generation_submitted"
        case .aiChatNtpWebSearchSubmitted:
            return "aichat_ntp_web_search_submitted"
        case .aiChatViewAllChatsClicked:
            return "aichat_view_all_chats_clicked"
        case .aiChatModelsFetchFailed:
            return "aichat_models_fetch_failed"
        case .aiChatMetricStartNewConversation:
            return "aichat_start_new_conversation"
        case .aiChatMetricSentPromptOngoingChat:
            return "aichat_sent_prompt_ongoing_chat"
        case .aiChatOpenDuckAiMainMenu:
            return "aichat_open_duck_ai_main_menu"
        case .aiChatNewChatMainMenu:
            return "aichat_new_chat_main_menu"
        case .aiChatNewVoiceChatMainMenu:
            return "aichat_new_voice_chat_main_menu"
        case .aiChatNewImageChatMainMenu:
            return "aichat_new_image_chat_main_menu"
        case .aiChatRecentChatSelectedMainMenu:
            return "aichat_recent_chat_selected_main_menu"
        case .aiChatDeleteAllChatsMainMenu:
            return "aichat_delete_all_chats_main_menu"
        case .aiChatOpenDuckAiMoreOptionsMenu:
            return "aichat_open_duck_ai_more_options_menu"
        case .aiChatNewChatMoreOptionsMenu:
            return "aichat_new_chat_more_options_menu"
        case .aiChatNewVoiceChatMoreOptionsMenu:
            return "aichat_new_voice_chat_more_options_menu"
        case .aiChatNewImageChatMoreOptionsMenu:
            return "aichat_new_image_chat_more_options_menu"
        case .aiChatRecentChatSelectedMoreOptionsMenu:
            return "aichat_recent_chat_selected_more_options_menu"
        case .aiChatDeleteAllChatsMoreOptionsMenu:
            return "aichat_delete_all_chats_more_options_menu"
        case .aiChatViewAllChatsMainMenu:
            return "aichat_view_all_chats_main_menu"
        case .aiChatViewAllChatsMoreOptionsMenu:
            return "aichat_view_all_chats_more_options_menu"
        case .aiChatTabDidTerminate:
            return "aichat_tab_did_terminate"
        case .aiChatIsEnabled:
            return "aichat_is_enabled"
        case .aiChatVoiceChatStartFailed:
            return "aichat_voice_chat_start_failed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .aichatApplicationMenuAppClicked,
                .aichatApplicationMenuFileClicked,
                .aichatNoRemoteSettingsFound,
                .aiChatSettingsGlobalToggleTurnedOn,
                .aiChatSettingsGlobalToggleTurnedOff,
                .aiChatSettingsNewTabPageShortcutTurnedOn,
                .aiChatSettingsNewTabPageShortcutTurnedOff,
                .aiChatSettingsAddressBarShortcutTurnedOn,
                .aiChatSettingsAddressBarShortcutTurnedOff,
                .aiChatSettingsAddressBarTypingShortcutTurnedOn,
                .aiChatSettingsAddressBarTypingShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOn,
                .aiChatSettingsDisplayed,
                .aiChatSidebarExpanded,
                .aiChatSidebarSettingChanged,
                .aiChatSidebarDetached,
                .aiChatSidebarAttached,
                .aiChatSidebarFloatingClosed,
                .aiChatSidebarFloatingTabActivated,
                .aiChatTabbarButtonClicked,
                .aiChatSummarizeSourceLinkClicked,
                .aiChatTranslateText,
                .aiChatTranslationSourceLinkClicked,
                .aiChatPageContextSourceLinkClicked,
                .aiChatAutoClearHistorySettingToggled,
                .aiChatDeleteHistoryRequested,
                .aiChatDeleteHistorySuccessful,
                .aiChatDeleteHistoryFailed,
                .aiChatAddressBarActivatedToggleOn,
                .aiChatAddressBarActivatedToggleOff,
                .aiChatAddressBarToggleChangedAIChat,
                .aiChatAddressBarToggleChangedSearch,
                .aiChatAddressBarAIChatSubmitPrompt,
                .aiChatAddressBarAIChatSubmitURL,
                .aiChatSuggestionAIChatSubmittedMouse,
                .aiChatSuggestionAIChatSubmittedKeyboard,
                .aiChatRecentChatSelectedPinnedMouse,
                .aiChatRecentChatSelectedPinnedKeyboard,
                .aiChatRecentChatSelectedMouse,
                .aiChatRecentChatSelectedKeyboard,
                .aiChatRecentChatDeleteButtonClicked,
                .aiChatRecentChatDeleteConfirmed,
                .aiChatRecentChatDeleteCancelled,
                .aiChatOnboardingTogglePreferenceOn,
                .aiChatOnboardingTogglePreferenceOff,
                .aiChatOnboardingFinishedToggleOn,
                .aiChatOnboardingFinishedToggleOff,
                .aiChatAddressBarImageAttached,
                .aiChatAddressBarImageRemoved,
                .aiChatAddressBarFileAttached,
                .aiChatAddressBarFileRemoved,
                .aiChatAddressBarAttachTabsPickerShown,
                .aiChatAddressBarAttachTabChosen,
                .aiChatAddressBarAttachTabRemoved,
                .aiChatAddressBarAttachPickerCanceled,
                .aiChatAddressBarMentionPickerShown,
                .aiChatAddressBarMentionTabChosen,
                .aiChatAddressBarMentionTabRemoved,
                .aiChatAddressBarMentionPickerCanceled,
                .aiChatAddressBarModelSelected,
                .aiChatAddressBarReasoningEffortSelected,
                .aiChatAddressBarImageGenerationActivated,
                .aiChatAddressBarImageGenerationDeactivated,
                .aiChatAddressBarImageGenerationSubmitted,
                .aiChatAddressBarWebSearchActivated,
                .aiChatAddressBarWebSearchDeactivated,
                .aiChatAddressBarWebSearchSubmitted,
                .aiChatNtpModelSelected,
                .aiChatNtpReasoningEffortSelected,
                .aiChatNtpViewAllChatsClicked,
                .aiChatNewVoiceChatOmnibarNtp,
                .aiChatNtpImageGenerationSubmitted,
                .aiChatNtpWebSearchSubmitted,
                .aiChatViewAllChatsClicked,
                .aiChatModelsFetchFailed,
                .aiChatMetricStartNewConversation,
                .aiChatMetricSentPromptOngoingChat,
                .aiChatTermsAcceptedDuplicateSyncOff,
                .aiChatTermsAcceptedDuplicateSyncOn,
                .aiChatOpenDuckAiMainMenu,
                .aiChatNewChatMainMenu,
                .aiChatNewVoiceChatMainMenu,
                .aiChatNewVoiceChatOmnibarNative,
                .aiChatNewImageChatMainMenu,
                .aiChatRecentChatSelectedMainMenu,
                .aiChatDeleteAllChatsMainMenu,
                .aiChatOpenDuckAiMoreOptionsMenu,
                .aiChatNewChatMoreOptionsMenu,
                .aiChatNewVoiceChatMoreOptionsMenu,
                .aiChatNewImageChatMoreOptionsMenu,
                .aiChatRecentChatSelectedMoreOptionsMenu,
                .aiChatDeleteAllChatsMoreOptionsMenu,
                .aiChatViewAllChatsMainMenu,
                .aiChatViewAllChatsMoreOptionsMenu,
                .aiChatTabDidTerminate:
            return nil
        case .aiChatIsEnabled(let isEnabled):
            return ["is_enabled": isEnabled ? "1" : "0"]
        case .aiChatAddressBarSubmitWithImage(let imageCount),
             .aiChatNtpSubmitWithImage(let imageCount):
            return ["imageCount": String(imageCount)]
        case .aiChatAddressBarSubmitWithTabs(let tabCount):
            return ["tabCount": String(tabCount)]
        case .aiChatAddressBarSubmitWithFiles(let fileCount):
            return ["fileCount": String(fileCount)]
        case .aiChatAddressBarFileValidationFailed(let reason):
            return ["reason": reason]
        case .aiChatAddressBarButtonClicked(let action):
            return ["action": action.rawValue]
        case .aiChatSidebarOpened(let source, let shouldAutomaticallySendPageContext, let minutesSinceSidebarHidden):
            var params = ["source": source.rawValue]
            if let shouldAutomaticallySendPageContext {
                params["automaticPageContext"] = String(shouldAutomaticallySendPageContext)
            }
            if let minutesSinceSidebarHidden {
                params["minutesSinceSidebarHidden"] = String(minutesSinceSidebarHidden)
            }
            return params
        case .aiChatSidebarClosed(let source):
            return ["source": source.rawValue]
        case .aiChatSidebarResized(let width):
            return ["width": String(width)]
        case .aiChatSummarizeText(let source):
            return ["source": source.rawValue]
        case .aiChatPageContextAdded(let automaticEnabled), .aiChatPageContextRemoved(let automaticEnabled):
            return ["automaticEnabled": String(automaticEnabled)]
        case .aiChatSyncScopedSyncTokenError(let reason),
                .aiChatSyncEncryptionError(let reason),
                .aiChatSyncDecryptionError(let reason),
                .aiChatSyncHistoryEnabledError(let reason):
            return ["reason": reason]
        case .aiChatReportMetricDecodeError(_, let failureReason):
            return ["failureReason": failureReason.rawValue]
        case .aiChatVoiceChatStartFailed(let reason):
            return ["reason": reason.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .aichatApplicationMenuAppClicked,
                .aichatApplicationMenuFileClicked,
                .aichatNoRemoteSettingsFound,
                .aiChatSettingsGlobalToggleTurnedOn,
                .aiChatSettingsGlobalToggleTurnedOff,
                .aiChatSettingsNewTabPageShortcutTurnedOn,
                .aiChatSettingsNewTabPageShortcutTurnedOff,
                .aiChatSettingsAddressBarShortcutTurnedOn,
                .aiChatSettingsAddressBarShortcutTurnedOff,
                .aiChatSettingsAddressBarTypingShortcutTurnedOn,
                .aiChatSettingsAddressBarTypingShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOff,
                .aiChatSettingsApplicationMenuShortcutTurnedOn,
                .aiChatSettingsDisplayed,
                .aiChatAutoClearHistorySettingToggled,
                .aiChatAddressBarButtonClicked,
                .aiChatSidebarOpened,
                .aiChatSidebarClosed,
                .aiChatSidebarExpanded,
                .aiChatSidebarSettingChanged,
                .aiChatSidebarResized,
                .aiChatSidebarDetached,
                .aiChatSidebarAttached,
                .aiChatSidebarFloatingClosed,
                .aiChatSidebarFloatingTabActivated,
                .aiChatTabbarButtonClicked,
                .aiChatSummarizeText,
                .aiChatSummarizeSourceLinkClicked,
                .aiChatTranslateText,
                .aiChatTranslationSourceLinkClicked,
                .aiChatPageContextSourceLinkClicked,
                .aiChatPageContextAdded,
                .aiChatPageContextRemoved,
                .aiChatDeleteHistoryRequested,
                .aiChatDeleteHistorySuccessful,
                .aiChatDeleteHistoryFailed,
                .aiChatAddressBarActivatedToggleOn,
                .aiChatAddressBarActivatedToggleOff,
                .aiChatAddressBarToggleChangedAIChat,
                .aiChatAddressBarToggleChangedSearch,
                .aiChatAddressBarAIChatSubmitPrompt,
                .aiChatAddressBarAIChatSubmitURL,
                .aiChatSuggestionAIChatSubmittedMouse,
                .aiChatSuggestionAIChatSubmittedKeyboard,
                .aiChatRecentChatSelectedPinnedMouse,
                .aiChatRecentChatSelectedPinnedKeyboard,
                .aiChatRecentChatSelectedMouse,
                .aiChatRecentChatSelectedKeyboard,
                .aiChatRecentChatDeleteButtonClicked,
                .aiChatRecentChatDeleteConfirmed,
                .aiChatRecentChatDeleteCancelled,
                .aiChatSyncScopedSyncTokenError,
                .aiChatSyncEncryptionError,
                .aiChatSyncDecryptionError,
                .aiChatSyncHistoryEnabledError,
                .aiChatOnboardingTogglePreferenceOn,
                .aiChatOnboardingTogglePreferenceOff,
                .aiChatOnboardingFinishedToggleOn,
                .aiChatOnboardingFinishedToggleOff,
                .aiChatAddressBarImageAttached,
                .aiChatAddressBarImageRemoved,
                .aiChatAddressBarSubmitWithImage,
                .aiChatAddressBarSubmitWithTabs,
                .aiChatAddressBarFileAttached,
                .aiChatAddressBarFileRemoved,
                .aiChatAddressBarFileValidationFailed,
                .aiChatAddressBarSubmitWithFiles,
                .aiChatAddressBarAttachTabsPickerShown,
                .aiChatAddressBarAttachTabChosen,
                .aiChatAddressBarAttachTabRemoved,
                .aiChatAddressBarAttachPickerCanceled,
                .aiChatAddressBarMentionPickerShown,
                .aiChatAddressBarMentionTabChosen,
                .aiChatAddressBarMentionTabRemoved,
                .aiChatAddressBarMentionPickerCanceled,
                .aiChatAddressBarModelSelected,
                .aiChatAddressBarReasoningEffortSelected,
                .aiChatNtpSubmitWithImage,
                .aiChatNtpModelSelected,
                .aiChatNtpReasoningEffortSelected,
                .aiChatNtpViewAllChatsClicked,
                .aiChatNewVoiceChatOmnibarNtp,
                .aiChatNtpImageGenerationSubmitted,
                .aiChatNtpWebSearchSubmitted,
                .aiChatViewAllChatsClicked,
                .aiChatModelsFetchFailed,
                .aiChatMetricStartNewConversation,
                .aiChatMetricSentPromptOngoingChat,
                .aiChatTermsAcceptedDuplicateSyncOff,
                .aiChatTermsAcceptedDuplicateSyncOn,
                .aiChatReportMetricDecodeError,
                .aiChatOpenDuckAiMainMenu,
                .aiChatNewChatMainMenu,
                .aiChatNewVoiceChatMainMenu,
                .aiChatNewVoiceChatOmnibarNative,
                .aiChatNewImageChatMainMenu,
                .aiChatRecentChatSelectedMainMenu,
                .aiChatDeleteAllChatsMainMenu,
                .aiChatOpenDuckAiMoreOptionsMenu,
                .aiChatNewChatMoreOptionsMenu,
                .aiChatNewVoiceChatMoreOptionsMenu,
                .aiChatNewImageChatMoreOptionsMenu,
                .aiChatRecentChatSelectedMoreOptionsMenu,
                .aiChatDeleteAllChatsMoreOptionsMenu,
                .aiChatViewAllChatsMainMenu,
                .aiChatViewAllChatsMoreOptionsMenu,
                .aiChatAddressBarImageGenerationActivated,
                .aiChatAddressBarImageGenerationDeactivated,
                .aiChatAddressBarImageGenerationSubmitted,
                .aiChatAddressBarWebSearchActivated,
                .aiChatAddressBarWebSearchDeactivated,
                .aiChatAddressBarWebSearchSubmitted,
                .aiChatIsEnabled,
                .aiChatVoiceChatStartFailed,
                .aiChatTabDidTerminate:
            return [.pixelSource]
        }
    }

}

/// Action performed when address bar button is clicked
enum AIChatAddressBarAction: String, CaseIterable {
    case sidebar = "sidebar"
    case tab = "tab"
    case tabWithPrompt = "tab-with-prompt"
}

/// Source of AI Chat sidebar open action
enum AIChatSidebarOpenSource: String, CaseIterable {
    case addressBarButton = "address-bar-button"
    case summarization = "summarization"
    case serp = "serp"
    case contextMenu = "context-menu"
    case translation = "translation"
    case tabbarButton = "tabbar-button"
}

/// Source of AI Chat sidebar close action
enum AIChatSidebarCloseSource: String, CaseIterable {
    case addressBarButton = "address-bar-button"
    case sidebarCloseButton = "sidebar-close-button"
    case contextMenu = "context-menu"
    case tabbarButton = "tabbar-button"
}

/// Reason associated with a Duck.ai voice-chat start failure reported by the FE
enum AIChatVoiceChatStartFailedReason: String, CaseIterable {
    /// FE reported `NotAllowedError` and the OS has denied microphone access to the app —
    /// the remediation surface was shown.
    case micOsDenied = "mic_os_denied"
    /// Any other reason (transient WebKit error, hardware unavailable, etc.) — no action taken.
    case other
}
