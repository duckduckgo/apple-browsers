//
//  AIChatContextualModePixelHandler.swift
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

import Core
import Foundation

/// Protocol for firing contextual mode pixels, enabling dependency injection and testing.
protocol AIChatContextualModePixelFiring {
    // MARK: - Sheet Lifecycle
    func fireSheetOpened()
    func fireSheetDismissed(hadUnsubmittedSelections: Bool)
    func fireSessionRestored()

    // MARK: - Sheet Actions
    func fireExpandButtonTapped()
    func fireHeaderTitleTapped()
    func fireNewChatButtonTapped()
    func fireQuickActionSummarizeSelected()
    func fireQuickActionAskAboutPageShown()
    func fireQuickActionAskAboutPageSelected()
    func fireFireButtonTapped()
    func fireFireButtonConfirmed()

    // MARK: - Address Bar Menu
    func fireAddressBarMenuShown()
    func fireAddressBarMenuNewChatSelected()
    func fireAddressBarMenuAskAboutPageSelected()

    // MARK: - Floating Input
    func fireFloatingInputDismissedWithoutSubmission(hadUnsubmittedSelections: Bool)
    func fireFloatingInputPromotedToSheet()

    // MARK: - Suggested Prompts
    func fireAskAboutPageSuggestionSelected(pageType: SuggestionsPageType)
    func fireSuggestionSelected(suggestionId: String, pageType: SuggestionsPageType)
    func fireSuggestionsViewed(isSmart: Bool, pageType: SuggestionsPageType, scope: ResolvePageSuggestionsInput.Scope)
    func fireSuggestionsContextCollectionTimedOut()

    // MARK: - Recent Chats Popup
    func fireRecentChatsPopupDisplayed()
    func fireRecentChatSelected()
    func fireViewAllChatsTapped()

    // MARK: - Page Context Attachment
    func firePageContextAutoAttached()
    func firePageContextUpdatedOnNavigation(url: String)
    func firePageContextManuallyAttachedNative()
    func firePageContextManuallyAttachedFrontend()

    // MARK: - Page Context Removal
    func firePageContextRemovedNative()
    func firePageContextRemovedFrontend()

    // MARK: - Text Selections
    func fireSelectionAttached()
    func fireSelectionLimitReached()
    func fireSelectionRemoved()
    func firePromptSubmittedWithSelections(count: Int)
    func fireSelectionToolDeliveryTimedOut()

    // MARK: - Page Context Collection
    func firePageContextCollectionEmpty()
    func firePageContextCollectionUnavailable()

    // MARK: - Prompt Submission
    func firePromptSubmittedWithContext()
    func firePromptSubmittedWithoutContext()

    // MARK: - Manual Attach State
    func beginManualAttach()
    func endManualAttach()
    var isManualAttachInProgress: Bool { get }

    // MARK: - Reset
    func reset()
}

/// Handles all pixel firing for contextual AI chat mode.
/// Single source of truth for contextual mode analytics.
///
/// **Thread Safety**: This class is thread-safe. All mutable state access is synchronized using a serial queue.
final class AIChatContextualModePixelHandler: AIChatContextualModePixelFiring {

    private static let askAboutPageSuggestionId = "ask-about-page"

    // MARK: - State

    /// Serial queue for synchronizing access to mutable state
    private let stateQueue = DispatchQueue(label: "com.duckduckgo.aichat.contextual.pixelhandler", qos: .userInitiated)

    /// Tracks whether a manual attach operation is in progress.
    private var _isManualAttachInProgress = false

    // MARK: - Dependencies

    private let firePixel: (Pixel.Event) -> Void
    private let firePixelWithParameters: (Pixel.Event, [String: String]) -> Void

    // MARK: - Public Properties

    var isManualAttachInProgress: Bool {
        stateQueue.sync { _isManualAttachInProgress }
    }

    // MARK: - Initialization

    init(firePixel: @escaping (Pixel.Event) -> Void = { DailyPixel.fireDailyAndCount(pixel: $0) },
         firePixelWithParameters: @escaping (Pixel.Event, [String: String]) -> Void = {
             DailyPixel.fireDailyAndCount(pixel: $0, withAdditionalParameters: $1)
         }) {
        self.firePixel = firePixel
        self.firePixelWithParameters = firePixelWithParameters
    }

    // MARK: - Sheet Lifecycle

    func fireSheetOpened() {
        firePixel(.aiChatContextualSheetOpened)
    }

    func fireSheetDismissed(hadUnsubmittedSelections: Bool) {
        firePixelWithParameters(.aiChatContextualSheetDismissed,
                                [PixelParameters.aiChatHadUnsubmittedSelections: String(hadUnsubmittedSelections)])
    }

    func fireSessionRestored() {
        firePixel(.aiChatContextualSessionRestored)
    }

    // MARK: - Sheet Actions

    func fireExpandButtonTapped() {
        firePixel(.aiChatContextualExpandButtonTapped)
    }

    func fireHeaderTitleTapped() {
        firePixel(.aiChatContextualHeaderTitleTapped)
    }

    func fireNewChatButtonTapped() {
        firePixel(.aiChatContextualNewChatButtonTapped)
    }

    func fireQuickActionSummarizeSelected() {
        firePixel(.aiChatContextualQuickActionSummarizeSelected)
    }

    func fireQuickActionAskAboutPageShown() {
        firePixel(.aiChatContextualQuickActionAskAboutPageShown)
    }

    func fireQuickActionAskAboutPageSelected() {
        firePixel(.aiChatContextualQuickActionAskAboutPageSelected)
    }

    func fireAddressBarMenuShown() {
        firePixel(.aiChatContextualAddressBarMenuShown)
    }

    func fireAddressBarMenuNewChatSelected() {
        firePixel(.aiChatContextualAddressBarMenuNewChatSelected)
    }

    func fireAddressBarMenuAskAboutPageSelected() {
        firePixel(.aiChatContextualAddressBarMenuAskAboutPageSelected)
    }

    func fireFloatingInputDismissedWithoutSubmission(hadUnsubmittedSelections: Bool) {
        firePixelWithParameters(.aiChatContextualFloatingInputDismissedWithoutSubmission,
                                [PixelParameters.aiChatHadUnsubmittedSelections: String(hadUnsubmittedSelections)])
    }

    func fireFloatingInputPromotedToSheet() {
        firePixel(.aiChatContextualFloatingInputPromotedToSheet)
    }

    func fireFireButtonTapped() {
        firePixel(.aiChatContextualFireButtonTapped)
    }

    func fireFireButtonConfirmed() {
        firePixel(.aiChatContextualFireButtonConfirmed)
    }

    // MARK: - Page Context Attachment

    func firePageContextAutoAttached() {
        firePixel(.aiChatContextualPageContextAutoAttached)
    }

    func firePageContextUpdatedOnNavigation(url: String) {
        firePixel(.aiChatContextualPageContextUpdatedOnNavigation)
    }

    func firePageContextManuallyAttachedNative() {
        firePixel(.aiChatContextualPageContextManuallyAttachedNative)
    }

    func firePageContextManuallyAttachedFrontend() {
        firePixel(.aiChatContextualPageContextManuallyAttachedFrontend)
    }

    // MARK: - Page Context Removal

    func firePageContextRemovedNative() {
        firePixel(.aiChatContextualPageContextRemovedNative)
    }

    func firePageContextRemovedFrontend() {
        firePixel(.aiChatContextualPageContextRemovedFrontend)
    }

    // MARK: - Text Selections

    func fireSelectionAttached() {
        firePixel(.aiChatContextualSelectionAttached)
    }

    func fireSelectionLimitReached() {
        firePixel(.aiChatContextualSelectionLimitReached)
    }

    func fireSelectionRemoved() {
        firePixel(.aiChatContextualSelectionRemoved)
    }

    func firePromptSubmittedWithSelections(count: Int) {
        let countBucket: String
        switch count {
        case 1: countBucket = "1"
        case 2: countBucket = "2"
        case 3...AIChatSelectionContextBuilder.maxAttachedSelections: countBucket = "3-5"
        default: return
        }
        firePixelWithParameters(.aiChatContextualPromptSubmittedWithSelections,
                                [PixelParameters.aiChatSelectionCount: countBucket])
    }

    func fireSelectionToolDeliveryTimedOut() {
        firePixel(.aiChatContextualSelectionToolDeliveryTimedOut)
    }

    // MARK: - Page Context Collection

    func firePageContextCollectionEmpty() {
        firePixel(.aiChatContextualPageContextCollectionEmpty)
    }

    func firePageContextCollectionUnavailable() {
        firePixel(.aiChatContextualPageContextCollectionUnavailable)
    }

    // MARK: - Prompt Submission

    func firePromptSubmittedWithContext() {
        firePixel(.aiChatContextualPromptSubmittedWithContextNative)
    }

    func firePromptSubmittedWithoutContext() {
        firePixel(.aiChatContextualPromptSubmittedWithoutContextNative)
    }

    // MARK: - Suggested Prompts

    func fireAskAboutPageSuggestionSelected(pageType: SuggestionsPageType) {
        fireSuggestionSelected(suggestionId: Self.askAboutPageSuggestionId, pageType: pageType)
    }

    func fireSuggestionSelected(suggestionId: String, pageType: SuggestionsPageType) {
        firePixelWithParameters(.aiChatContextualSuggestionSelected, [
            PixelParameters.suggestionId: suggestionId,
            PixelParameters.suggestionsPageType: pageType.rawValue
        ])
    }

    func fireSuggestionsViewed(isSmart: Bool, pageType: SuggestionsPageType, scope: ResolvePageSuggestionsInput.Scope) {
        firePixelWithParameters(.aiChatContextualSuggestionsViewed, [
            PixelParameters.suggestionsAreSmart: String(isSmart),
            PixelParameters.suggestionsPageType: pageType.rawValue,
            PixelParameters.aiChatSuggestionScope: scope.rawValue
        ])
    }

    func fireSuggestionsContextCollectionTimedOut() {
        firePixel(.aiChatContextualSuggestionsContextCollectionTimedOut)
    }

    // MARK: - Recent Chats Popup

    func fireRecentChatsPopupDisplayed() {
        firePixel(.aiChatContextualRecentChatsPopupDisplayed)
    }

    func fireRecentChatSelected() {
        firePixel(.aiChatContextualRecentChatSelected)
    }

    func fireViewAllChatsTapped() {
        firePixel(.aiChatContextualViewAllChatsTapped)
    }

    // MARK: - Manual Attach State

    func beginManualAttach() {
        stateQueue.sync {
            _isManualAttachInProgress = true
        }
    }

    func endManualAttach() {
        stateQueue.sync {
            _isManualAttachInProgress = false
        }
    }

    // MARK: - Reset

    /// Resets state. Call when the contextual session ends.
    func reset() {
        stateQueue.sync {
            _isManualAttachInProgress = false
        }
    }
}
