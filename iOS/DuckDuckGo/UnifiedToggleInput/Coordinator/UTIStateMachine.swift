//
//  UTIStateMachine.swift
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

/// Owns the UTI `displayState` and derives everything that is a pure function of it: the
/// display-state booleans, the card layout, and the `UTIRenderState` snapshot pushed to the view.
/// Non-owned inputs (mode, text state, keyboard visibility, …) are passed in per call so this stays
/// a pure derivation with `displayState` as its single source of truth.
@MainActor
final class UTIStateMachine {

    private(set) var displayState: UnifiedToggleInputDisplayState
    private let host: UnifiedToggleInputHost
    private let hidesToggleOnDuckAITab: Bool

    init(displayState: UnifiedToggleInputDisplayState = .hidden,
         host: UnifiedToggleInputHost,
         hidesToggleOnDuckAITab: Bool) {
        self.displayState = displayState
        self.host = host
        self.hidesToggleOnDuckAITab = hidesToggleOnDuckAITab
    }

    func transition(to newState: UnifiedToggleInputDisplayState) {
        displayState = newState
    }

    // MARK: - Derived state (pure functions of `displayState`)

    var isOmnibarSession: Bool {
        if case .omnibar = displayState { return true }
        return false
    }

    var isAITabState: Bool {
        if case .aiTab = displayState { return true }
        return false
    }

    var isAITabExpanded: Bool {
        displayState == .aiTab(.expanded)
    }

    var isContextualChatState: Bool {
        displayState == .contextualChat
    }

    /// Folds contextual + Duck.ai tab into one "Duck.ai surface" bucket — used only for the funnel `origin`.
    var isDuckAISurfaceForAttribution: Bool {
        isAITabState || isContextualChatState
    }

    /// The hosting surface for the `surface` pixel parameter (the funnel `origin` uses `isDuckAISurfaceForAttribution`).
    var pixelSurface: UnifiedToggleInputPixelSurface {
        if isContextualChatState { return .contextualChat }
        if isAITabState { return .duckAI }
        return .addressBar
    }

    /// True when the current display state corresponds to the expanded card layout.
    /// Synchronous (driven by `displayState`) so it's safe to read before the deferred
    /// `applyCardLayout` runs from the intent handler.
    var isInputPaneExpanded: Bool {
        switch displayState {
        case .contextualChat, .aiTab(.expanded), .omnibar(.active): return true
        default: return false
        }
    }

    var isInputEditing: Bool {
        isOmnibarSession || isAITabExpanded || isContextualChatState
    }

    var isActive: Bool {
        displayState != .hidden
    }

    /// Whether the toggle row appears in the UTI and the swipe-between-modes gesture is active.
    /// Combines user setting + Duck.ai-tab hide flag; the kill-switch term drops out on non-AI tabs.
    func isToggleVisible(isToggleEnabled: Bool) -> Bool {
        isToggleEnabled && !(hidesToggleOnDuckAITab && isAITabState)
    }

    // MARK: - Render

    func computeRenderState(inputMode: TextEntryMode,
                            textState: InputTextState,
                            cardPosition: UnifiedToggleInputCardPosition,
                            isInputVisibleForKeyboard: Bool,
                            isContentOverlaySuppressed: Bool,
                            isToggleEnabled: Bool,
                            floatingReturnKeyState: UnifiedToggleInputFloatingReturnKeyState) -> UTIRenderState {
        let isExpanded: Bool
        let isInputVisible: Bool
        let isContentVisible: Bool
        let inactiveAppearance: Bool

        switch displayState {
        case .hidden:
            isExpanded = false
            isInputVisible = false
            isContentVisible = false
            inactiveAppearance = false

        case .contextualChat:
            isExpanded = true
            isInputVisible = true
            isContentVisible = false
            inactiveAppearance = false

        case .aiTab(.collapsed):
            isExpanded = false
            isInputVisible = true
            isContentVisible = false
            inactiveAppearance = false

        case .aiTab(.expanded):
            isExpanded = true
            isInputVisible = true
            let isAIChatOnAITab = isAITabState && inputMode == .aiChat
            let isSearchOnAITab = isAITabState && inputMode == .search
            // Toggling to Search on a chat tab without visible text is a mode switch — keep the
            // chat web view; `textState` (not `currentText`) excludes preserved drafts from
            // dismiss-cleanup.
            let isSearchOnAITabWithoutText = isSearchOnAITab && textState == .empty
            isContentVisible = !(isAIChatOnAITab || isSearchOnAITabWithoutText)
            let isSearchKeyboardHidden = isSearchOnAITab && !isInputVisibleForKeyboard
            inactiveAppearance = isSearchKeyboardHidden

        case .omnibar(.active):
            isExpanded = true
            isInputVisible = true
            isContentVisible = true
            inactiveAppearance = false

        case .omnibar(.inactive):
            isExpanded = true
            isInputVisible = true
            isContentVisible = true
            inactiveAppearance = (cardPosition == .bottom)
        }

        let canShowFloatingReturnKey = floatingReturnKeyState.canInsertReturn
        let shouldSuppressContentOverlay = isOmnibarSession && isContentOverlaySuppressed && textState != .userTyped
        let effectiveContentVisible = isContentVisible && !shouldSuppressContentOverlay

        return UTIRenderState(
            isInputVisible: isInputVisible,
            isContentVisible: effectiveContentVisible,
            cardLayout: cardLayout(forIsExpanded: isExpanded, inputMode: inputMode, isToggleEnabled: isToggleEnabled),
            cardPosition: cardPosition,
            usesOmnibarMargins: cardPosition == .top && isOmnibarSession,
            inactiveAppearance: inactiveAppearance,
            isFloatingReturnKeyVisible: canShowFloatingReturnKey,
            contentInputMode: inputMode,
            inputMode: inputMode,
            isInlineDismissHidden: isAITabState || isContextualChatState,
            isAITab: isAITabState
        )
    }

    /// Decides which card components are visible right now, based on host + display state +
    /// toggle setting + input mode. Centralised here so the view layer just renders.
    private func cardLayout(forIsExpanded isExpanded: Bool,
                            inputMode: TextEntryMode,
                            isToggleEnabled: Bool) -> UnifiedToggleInputCardLayout {
        guard isExpanded else {
            return isAITabState ? .flanked : .collapsed
        }
        switch host {
        case .contextualChat:
            return .expanded(showsToggle: false, showsToolbar: true)
        case .omnibar:
            // Keep the AI-chat toolbar on Duck.ai tabs even when the toggle is hidden,
            // so the user retains the model selector / attachments / send affordances.
            let showsToolbar = inputMode == .aiChat && (isToggleEnabled || isAITabState)
            return .expanded(showsToggle: isToggleVisible(isToggleEnabled: isToggleEnabled), showsToolbar: showsToolbar)
        }
    }
}
