//
//  AIChatContextualSheetViewController+NativeChat.swift
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
import DuckAINative
import UIKit

/// What the native chat was started from, so "Continue in Duck.ai" can replay it on the web.
struct NativeChatOrigin {
    let prompt: String
    let isSuggestedPrompt: Bool
}

extension AIChatContextualSheetViewController: NativeChatDelegate {

    var isShowingNativeChat: Bool {
        nativeChatViewController != nil
    }

    /// Summarize / Translate chips and other suggestions. Returns false to fall back to the web path.
    func deliverSuggestionNatively(_ suggestion: ContextualSuggestedPrompt, actsOnSelection: Bool) async -> Bool {
        if !actsOnSelection {
            await delegate?.aiChatContextualSheetViewControllerAttachContextForSuggestion(self)
        }
        let page: AIChatPageContextData? = if !actsOnSelection, case .attached(let context) = sessionState.chipState {
            context.contextData
        } else {
            nil
        }
        guard let context = NativeChatContextFactory.context(suggestionID: suggestion.id,
                                                             prompt: suggestion.prompt,
                                                             page: page,
                                                             selections: actsOnSelection ? sessionState.attachedSelections : [],
                                                             uiLocale: Locale.current.identifier) else { return false }
        showNativeChat(context, origin: NativeChatOrigin(prompt: suggestion.prompt, isSuggestedPrompt: true))
        return true
    }

    /// The first prompt typed into the sheet. Returns false to let the web chat take it.
    func startNativeChatIfEnabled(prompt: String, page: AIChatPageContextData?) -> Bool {
        guard !bypassesNativeChat,
              DuckAINativeSettings.shared.opensNewChatsNatively,
              let context = NativeChatContextFactory.context(prompt: prompt, page: page, selections: sessionState.attachedSelections) else {
            return false
        }
        showNativeChat(context, origin: NativeChatOrigin(prompt: prompt, isSuggestedPrompt: false))
        return true
    }

    /// New Chat, or leaving for the web. Puts the sheet's own input back.
    func tearDownNativeChat() {
        guard nativeChatViewController != nil else { return }
        if let binding = nativeChatBinding as? NativeChatInputBinding {
            binding.session.close()
            binding.unbind()
        }
        nativeChatViewController = nil
        nativeChatBinding = nil
        nativeChatOrigin = nil
        showNativeInputUI()
    }

    func nativeChatDidRequestClose() {
        dismiss(animated: true)
    }

    func nativeChatDidRequestContinueInWeb(_ context: ChatContext) {
        guard let origin = nativeChatOrigin else { return }
        tearDownNativeChat()
        bypassesNativeChat = true
        submitSuggestionPrompt(origin.prompt, isSuggestedPrompt: origin.isSuggestedPrompt)
        bypassesNativeChat = false
    }

    private func showNativeChat(_ context: ChatContext, origin: NativeChatOrigin) {
        let session = ChatSession(context: context, provider: NativeChatProviderFactory.makeProvider())
        // The sheet's own input drives the native chat when it has one.
        let chat = DuckAINative.makeChatViewController(session: session,
                                                       surface: .contextualSheet,
                                                       showsComposer: persistentUTIHost == nil,
                                                       delegate: self)
        nativeChatBinding = persistentUTIHost.map { NativeChatInputBinding(host: $0, session: session) }
        removeCurrentChildViewController()
        isWebViewVisible = false
        nativeChatViewController = chat
        nativeChatOrigin = origin
        embedChildViewController(chat)
        isAwaitingSubmittedChat = false
        cancelWaitingForInitialPromptResponseState()
        mountPersistentUTIHostIfNeeded()
        sessionState.consumeAttachedSelections(ids: sessionState.attachedSelections.map { $0.id })
        sessionState.beginChatForUTISubmission()
        expandToLargeDetent()
    }
}
