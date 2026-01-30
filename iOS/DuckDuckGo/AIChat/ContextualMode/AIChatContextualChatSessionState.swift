//
//  AIChatContextualChatSessionState.swift
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

import Combine
import Foundation
import os.log

/// Tracks the lifecycle state of the frontend chat
enum FrontendChatState: CustomStringConvertible {
    case noChat
    case chatWithoutInitialContext
    case chatWithInitialContext

    var description: String {
        switch self {
        case .noChat: return "noChat"
        case .chatWithoutInitialContext: return "chatWithoutInitialContext"
        case .chatWithInitialContext: return "chatWithInitialContext"
        }
    }
}

/// Tracks the current state of the context chip
enum ChipState: CustomStringConvertible {
    case none
    case placeholder
    case attached

    var description: String {
        switch self {
        case .none: return "none"
        case .placeholder: return "placeholder"
        case .attached: return "attached"
        }
    }
}

/// Manages all state for a contextual chat session.
/// Single source of truth for frontend chat state, chip state, and session lifecycle.
final class AIChatContextualChatSessionState {

    // MARK: - State

    @Published private(set) var frontendState: FrontendChatState = .noChat
    @Published private(set) var chipState: ChipState = .none

    /// Tracks whether the user explicitly downgraded from attached to placeholder
    private(set) var userDowngradedToPlaceholder = false

    // MARK: - Frontend Chat State Transitions

    /// Call when submitting initial prompt to frontend
    func startChat(withContext: Bool) {
        if withContext {
            frontendState = .chatWithInitialContext
            Logger.aiChat.debug("[PageContext] Chat started WITH initial context")
        } else {
            frontendState = .chatWithoutInitialContext
            Logger.aiChat.debug("[PageContext] Chat started WITHOUT initial context")
        }
    }

    /// Call when starting a new chat (resetting frontend)
    func resetToNoChat() {
        frontendState = .noChat
        Logger.aiChat.debug("[PageContext] Reset to no chat")
    }

    // MARK: - Chip State Transitions

    func attachChip() {
        chipState = .attached
        userDowngradedToPlaceholder = false
        Logger.aiChat.debug("[PageContext] Chip attached")
    }

    func showPlaceholder() {
        chipState = .placeholder
        Logger.aiChat.debug("[PageContext] Chip showing placeholder")
    }

    func hideChip() {
        chipState = .none
        userDowngradedToPlaceholder = false
        Logger.aiChat.debug("[PageContext] Chip hidden")
    }

    /// Handles chip removal by user (X button tap)
    /// Returns true if should downgrade to placeholder, false if should hide
    func handleChipRemoval(hasSnapshot: Bool) -> Bool {
        guard chipState == .attached else { return false }

        if hasSnapshot {
            chipState = .placeholder
            userDowngradedToPlaceholder = true
            Logger.aiChat.debug("[PageContext] Chip downgraded to placeholder (user action)")
            return true
        } else {
            chipState = .none
            userDowngradedToPlaceholder = false
            Logger.aiChat.debug("[PageContext] Chip hidden (no snapshot)")
            return false
        }
    }

    func resetChipStateForNewChat(hasSnapshot: Bool, autoAttachEnabled: Bool) {
        userDowngradedToPlaceholder = false

        if hasSnapshot {
            chipState = autoAttachEnabled ? .attached : .placeholder
            Logger.aiChat.debug("[PageContext] New chat chip reset - hasSnapshot=true, autoAttach=\(autoAttachEnabled), chipState=\(self.chipState)")
        } else {
            chipState = .none
            Logger.aiChat.debug("[PageContext] New chat chip reset - hasSnapshot=false, chipState=.none")
        }
    }

    // MARK: - Business Logic

    /// Determines if context should be collected on navigation/DOM change
    func shouldCollectContext(autoAttachEnabled: Bool) -> Bool {
        guard frontendState != .chatWithInitialContext else {
            Logger.aiChat.debug("[PageContext] shouldCollect=false (frontend has initial context)")
            return false
        }

        Logger.aiChat.debug("[PageContext] shouldCollect=\(autoAttachEnabled) (autoAttach setting)")
        return autoAttachEnabled
    }

    /// Determines if UI should be updated when new context arrives
    func shouldUpdateUI(autoAttachEnabled: Bool) -> Bool {
        Logger.aiChat.debug("[PageContext] shouldUpdateUI=\(autoAttachEnabled) (autoAttach setting)")
        return autoAttachEnabled
    }

    /// Determines if context can be pushed to frontend web view
    func canPushToFrontend() -> Bool {
        let canPush = frontendState == .chatWithoutInitialContext
        Logger.aiChat.debug("[PageContext] canPushToFrontend=\(canPush) (frontendState=\(self.frontendState))")
        return canPush
    }

    /// Checks if automatic upgrades from placeholder to attached should be allowed
    func shouldAllowAutomaticUpgrade() -> Bool {
        return !userDowngradedToPlaceholder
    }

    /// Clears the user downgrade flag on navigation
    /// Navigation to a new page means user's previous downgrade no longer applies
    func clearUserDowngradeOnNavigation() {
        if userDowngradedToPlaceholder {
            userDowngradedToPlaceholder = false
            Logger.aiChat.debug("[PageContext] Cleared user downgrade flag on navigation")
        }
    }

    /// Resets chip state on navigation when collection is skipped (e.g. auto-attach OFF)
    func resetChipOnNavigation(autoAttachEnabled: Bool) {
        // If we have an active chat with context, we might want to keep the chip? 
        // But assuming we want to clear "stale" page context if we aren't tracking the new page.
        // For now, if we are not collecting, and we are in noChat or chatWithoutInitialContext, we should probably clear.
        
        if frontendState == .chatWithInitialContext {
            // Chat is locked to a context. Do not clear the chip as it represents the active chat context.
            return
        }
        
        // If we are here, we are NOT collecting context for the new page.
        // So any existing attached chip is stale (belongs to previous page).
        if chipState != .none {
            chipState = .none
            Logger.aiChat.debug("[PageContext] Chip reset to none on navigation (stale context)")
        }
    }

    /// Returns true if showing native input (no active chat)
    var isShowingNativeInput: Bool {
        frontendState == .noChat
    }
}
