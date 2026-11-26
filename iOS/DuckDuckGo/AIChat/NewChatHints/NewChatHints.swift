//
//  NewChatHints.swift
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

import Foundation

/// A chip above the native input that shows a returning user what Duck.ai can do on a blank new chat.
enum NewChatHint: CaseIterable {
    case documents
    case photo
    case imageGeneration
}

/// Everything that decides which hints show. Any one term being false hides them all.
struct NewChatHintsInputs: Equatable {
    /// Has sent a Duck.ai prompt before and accepted the Terms of Service.
    var isEligibleUser = false
    /// See `NewChatState.isGuaranteedNewChat`.
    var isGuaranteedNewChat = false
    /// The page said no promo is showing on this tab. No message yet means not clear.
    var isPromoClear = false
    /// The footer isn't showing the "type @" tip. Other footer messages leave the hints alone.
    var isTypeAtTipHidden = false
    /// No text, no attachments and no selected tool.
    var isDraftEmpty = false
    /// The hints the available models can serve, in this tab's order.
    var availableHints: [NewChatHint] = []

    var visibleHints: [NewChatHint] {
        let isShown = isEligibleUser && isGuaranteedNewChat && isPromoClear && isTypeAtTipHidden && isDraftEmpty
        return isShown ? availableHints : []
    }
}

/// What the full-tab input knows about the chat on screen. Each exclusion is a case that
/// looked like a new chat on Android and briefly showed hints there.
struct NewChatState: Equatable {
    /// The input is the full-tab Duck.ai input, not the omnibar or the contextual sheet.
    var isFullTabInput = false
    /// This tab is the one on screen, and the input is bound to its page rather than the previous tab's.
    var isTabSelected = false
    /// The page reported it is ready for a prompt and hasn't hidden its input (voice does).
    var isInputReady = false
    /// The URL names a chat, or a prompt was already sent on this one.
    var hasChat = false
    /// The page was asked to auto-submit a prompt (`prompt=1`).
    var carriesPrompt = false
    /// Voice mode is open, was requested for this page, or closed less than a second ago.
    var isVoiceHeld = false
    /// An earlier message is being edited.
    var isEditing = false

    static let none = NewChatState()

    var isGuaranteedNewChat: Bool {
        isFullTabInput && isTabSelected && isInputReady
            && !hasChat && !carriesPrompt && !isVoiceHeld && !isEditing
    }
}
