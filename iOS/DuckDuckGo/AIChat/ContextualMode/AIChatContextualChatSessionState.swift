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

import AIChat
import Combine
import Foundation
import os.log
import UIKit

// MARK: - State Enums

/// Manages the lifecycle state of the frontend chat
enum FrontendChatState: CustomStringConvertible {
    case noChat
    case chatWithoutInitialContext
    case chatWithInitialContext
    case restoredChat

    var description: String {
        switch self {
        case .noChat: return "noChat"
        case .chatWithoutInitialContext: return "chatWithoutInitialContext"
        case .chatWithInitialContext: return "chatWithInitialContext"
        case .restoredChat: return "restoredChat"
        }
    }
}

/// Manages the current state of the context chip
enum ChipState: CustomStringConvertible {
    case placeholder
    case attached(AIChatPageContext)

    var description: String {
        switch self {
        case .placeholder: return "placeholder"
        case .attached: return "attached"
        }
    }
}

struct SheetViewState {
    let content: ContentMode
    let isExpandButtonEnabled: Bool
    let shouldShowNewChatButton: Bool
    let chipState: ChipState

    enum ContentMode {
        case nativeInput
        case webView(restoreURL: URL?)
    }
}

enum SheetEffect {
    case submitPrompt(prompt: String, context: AIChatPageContextData?)
    case reloadWebView
    case pushContextToFrontend(AIChatPageContextData)
    case clearPrompt
}

// MARK: - Session State

/// Single source of truth for all contextual chat session state.
@MainActor
final class AIChatContextualChatSessionState {

    // MARK: - Dependencies

    private let aiChatSettings: AIChatSettingsProvider
    private let pixelHandler: AIChatContextualModePixelFiring

    // MARK: - Core State (private(set) - mutations happen via methods)

    private(set) var frontendState: FrontendChatState = .noChat
    private(set) var chipState: ChipState = .placeholder
    private(set) var contextualChatURL: URL?
    private(set) var latestContext: AIChatPageContext?

    @Published private(set) var viewState = SheetViewState(
        content: .nativeInput,
        isExpandButtonEnabled: true,
        shouldShowNewChatButton: false,
        chipState: .placeholder
    )

    let effects = PassthroughSubject<SheetEffect, Never>()

    /// Tracks whether the user explicitly downgraded from attached to placeholder
    private(set) var userDowngradedToPlaceholder = false
    private var wasAutoAttachEnabled: Bool

    // MARK: - Internal Flags

    /// Flag to track a manual attach flow in progress
    private var isManualAttachInProgress = false
    private var isManualAttachFromFrontend = false

    /// Flag to prevent duplicate navigation processing
    private var isProcessingNavigation = false

    // MARK: - Initialization

    init(aiChatSettings: AIChatSettingsProvider,
         pixelHandler: AIChatContextualModePixelFiring) {
        self.aiChatSettings = aiChatSettings
        self.pixelHandler = pixelHandler
        self.wasAutoAttachEnabled = aiChatSettings.isAutomaticContextAttachmentEnabled
        rebuildViewState()
    }

    // MARK: - Derived Properties (computed, no storage)

    /// Whether there's an active chat session (frontend is loaded)
    var hasActiveChat: Bool {
        frontendState != .noChat
    }

    /// Whether the new chat button should be visible
    var isNewChatButtonVisible: Bool {
        hasActiveChat
    }

    /// Whether the expand button should be enabled
    var isExpandEnabled: Bool {
        frontendState == .noChat || contextualChatURL != nil
    }

    /// Whether showing native input (no active chat)
    var isShowingNativeInput: Bool {
        frontendState == .noChat
    }

    /// Whether context is available for display
    var hasContext: Bool {
        latestContext != nil
    }

    /// Whether automatic context collection is enabled
    var shouldAutoCollectContext: Bool {
        aiChatSettings.isAutomaticContextAttachmentEnabled
    }

    // MARK: - Frontend Chat State Transitions

    /// Call when user submits a prompt from native input
    func handlePromptSubmission(_ prompt: String, url: URL? = nil) {
        guard frontendState != .restoredChat else {
            Logger.aiChat.debug("[SessionState] Chat start request ignored - preserving .restoredChat state")
            return
        }

        let contextData: AIChatPageContextData?
        switch chipState {
        case .attached(let context):
            contextData = context.contextData
            frontendState = .chatWithInitialContext
            pixelHandler.firePromptSubmittedWithContext()
            Logger.aiChat.debug("[SessionState] Chat started WITH initial context (chip was attached)")
        case .placeholder:
            contextData = nil
            frontendState = .chatWithoutInitialContext
            pixelHandler.firePromptSubmittedWithoutContext()
            Logger.aiChat.debug("[SessionState] Chat started WITHOUT initial context (chip was placeholder)")
        }

        if let url = url {
            contextualChatURL = url
        }

        rebuildViewState()
        emit(.submitPrompt(prompt: prompt, context: contextData))
    }

    /// Call when starting a new chat (resetting frontend)
    func resetToNoChat() {
        frontendState = .noChat
        chipState = .placeholder
        contextualChatURL = nil
        userDowngradedToPlaceholder = false
        isManualAttachInProgress = false
        isManualAttachFromFrontend = false
        isProcessingNavigation = false
        pixelHandler.endManualAttach()
        rebuildViewState()
        emit(.clearPrompt)
        Logger.aiChat.debug("[SessionState] Reset to no chat")
    }

    /// Updates the contextual chat URL (for persistence/expansion)
    func updateContextualChatURL(_ url: URL?) {
        contextualChatURL = url
        rebuildViewState()

        if let url {
            Logger.aiChat.debug("[SessionState] Updated contextual chat URL: \(url.absoluteString)")
        } else {
            Logger.aiChat.debug("[SessionState] Cleared contextual chat URL")
        }
    }

    func restoreChat(with url: URL) {
        contextualChatURL = url
        frontendState = .restoredChat
        rebuildViewState()
        Logger.aiChat.debug("[SessionState] Restored chat URL: \(url.absoluteString)")
    }

    // MARK: - Chip State Transitions

    /// Handles chip removal by user (X button tap)
    func handleChipRemoval() -> Bool {
        guard case .attached = chipState else { return false }

        chipState = .placeholder
        userDowngradedToPlaceholder = true
        pixelHandler.firePageContextRemovedNative()
        rebuildViewState()
        Logger.aiChat.debug("[SessionState] Chip downgraded to placeholder (user action)")
        return true
    }

    /// Downgrades an attached chip to placeholder state.
    func downgradeToPlaceholder() {
        guard case .attached = chipState else { return }
        chipState = .placeholder
        userDowngradedToPlaceholder = true
        pixelHandler.firePageContextRemovedNative()
        rebuildViewState()
        Logger.aiChat.debug("[SessionState] Chip downgraded to placeholder via coordinator")
    }

    // MARK: - Context Management

    /// Begin a manual attach operation (user tapped "Attach Page")
    func beginManualAttach(fromFrontend: Bool = false) {
        Logger.aiChat.debug("[SessionState] Manual attach requested (frontend: \(fromFrontend))")
        pixelHandler.beginManualAttach()
        isManualAttachInProgress = true
        isManualAttachFromFrontend = fromFrontend
    }

    /// Notify that page navigation occurred
    func notifyPageChanged() {
        Logger.aiChat.debug("[SessionState] Page navigation detected")
        clearUserDowngradeOnNavigation()
        isProcessingNavigation = true
    }

    /// Clear the navigation processing flag (called when collection can't start)
    func clearProcessingNavigationFlag() {
        isProcessingNavigation = false
        Logger.aiChat.debug("[SessionState] Cleared processing navigation flag")
    }

    /// Refresh cached auto-attach setting and clear user downgrade if toggled on.
    func refreshAutoAttachSetting() {
        let isEnabled = shouldAutoCollectContext
        if isEnabled && !wasAutoAttachEnabled {
            userDowngradedToPlaceholder = false
            Logger.aiChat.debug("[SessionState] Auto-attach enabled - cleared user downgrade")
        }
        wasAutoAttachEnabled = isEnabled
    }

    /// Updates the latest page context and determines attach behavior based on internal state.
    func updateContext(_ context: AIChatPageContext?) {
        guard let context = context else {
            Logger.aiChat.debug("[SessionState] Context collection returned nil - clearing context and downgrading to placeholder")
            latestContext = nil
            chipState = .placeholder
            cleanupFlags()
            rebuildViewState()
            return
        }

        latestContext = context
        Logger.aiChat.debug("[SessionState] Context updated: \(context.title)")

        if isManualAttachInProgress {
            handleManualAttach(context)
        } else if shouldAutoCollectContext {
            handleAutoAttach(context)
        } else {
            Logger.aiChat.debug("[SessionState] Context updated without chip change (auto-attach OFF)")
        }

        if isProcessingNavigation {
            pixelHandler.firePageContextUpdatedOnNavigation(url: context.contextData.url)
            isProcessingNavigation = false
        }

        rebuildViewState()
    }

    /// Cancels an in-progress manual attach operation.
    func cancelManualAttach() {
        guard isManualAttachInProgress else { return }
        isManualAttachInProgress = false
        isManualAttachFromFrontend = false
        pixelHandler.endManualAttach()
        Logger.aiChat.debug("[SessionState] Manual attach cancelled")
    }

    /// Requests a WebView reload. ViewController should observe `effects`.
    func requestWebViewReload() {
        emit(.reloadWebView)
    }
}

// MARK: - Private

private extension AIChatContextualChatSessionState {

    func handleManualAttach(_ context: AIChatPageContext) {
        if isShowingNativeInput {
            chipState = .attached(context)
            userDowngradedToPlaceholder = false
            Logger.aiChat.debug("[SessionState] Manually attached context")
        }

        if canPushToFrontend() {
            emit(.pushContextToFrontend(context.contextData))
        }

        if isManualAttachFromFrontend {
            pixelHandler.firePageContextManuallyAttachedFrontend()
        } else {
            pixelHandler.firePageContextManuallyAttachedNative()
        }

        isManualAttachInProgress = false
        isManualAttachFromFrontend = false
        pixelHandler.endManualAttach()
    }

    func handleAutoAttach(_ context: AIChatPageContext) {
        if isShowingNativeInput {
            switch chipState {
            case .placeholder:
                if shouldAllowAutomaticUpgrade() {
                    chipState = .attached(context)
                    userDowngradedToPlaceholder = false
                    Logger.aiChat.debug("[SessionState] Auto-attached context (setting ON)")
                    pixelHandler.firePageContextAutoAttached()
                }

            case .attached:
                chipState = .attached(context)
                Logger.aiChat.debug("[SessionState] Updated attached context (setting ON)")
            }
        } else {
            Logger.aiChat.debug("[SessionState] Context updated on navigation (WebView active, chip not updated)")
        }

        if canPushToFrontend() {
            emit(.pushContextToFrontend(context.contextData))
        }
    }

    func cleanupFlags() {
        Logger.aiChat.debug("[SessionState] Context update - nil result, preserving existing context")

        if isManualAttachInProgress {
            isManualAttachInProgress = false
            pixelHandler.endManualAttach()
        }
        if isProcessingNavigation {
            isProcessingNavigation = false
        }
    }

    func canPushToFrontend() -> Bool {
        let canPush = frontendState == .chatWithoutInitialContext || frontendState == .restoredChat
        Logger.aiChat.debug("[SessionState] canPushToFrontend=\(canPush) (frontendState=\(self.frontendState))")
        return canPush
    }

    func shouldAllowAutomaticUpgrade() -> Bool {
        return !userDowngradedToPlaceholder
    }

    func clearUserDowngradeOnNavigation() {
        if userDowngradedToPlaceholder {
            userDowngradedToPlaceholder = false
            Logger.aiChat.debug("[SessionState] Cleared user downgrade flag on navigation")
        }
    }

    func rebuildViewState() {
        let content: SheetViewState.ContentMode
        switch frontendState {
        case .noChat:
            content = .nativeInput
        case .chatWithInitialContext, .chatWithoutInitialContext, .restoredChat:
            content = .webView(restoreURL: contextualChatURL)
        }

        viewState = SheetViewState(
            content: content,
            isExpandButtonEnabled: frontendState == .noChat || contextualChatURL != nil,
            shouldShowNewChatButton: frontendState != .noChat,
            chipState: chipState
        )
    }

    func emit(_ effect: SheetEffect) {
        effects.send(effect)
    }
}
