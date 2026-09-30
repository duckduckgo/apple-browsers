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

import BrowserServicesKit
import Core
import Foundation
import PixelKit

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
    func fireAddressBarMenuAskAboutSearchSelected()
    func fireAddressBarMenuRecentChatsSelected()

    // MARK: - Floating Input
    func fireFloatingInputDismissedWithoutSubmission(hadUnsubmittedSelections: Bool)
    func fireFloatingInputPromotedToSheet()

    // MARK: - Suggested Prompts
    func fireAskAboutPageSuggestionSelected(pageType: SuggestionsPageType)
    func fireSuggestionSelected(suggestionId: String, pageType: SuggestionsPageType, surface: AIChatContextualSuggestionsSurface)
    func fireSuggestionsViewed(isSmart: Bool,
                               pageType: SuggestionsPageType,
                               scope: ResolvePageSuggestionsInput.Scope,
                               surface: AIChatContextualSuggestionsSurface)
    func fireSuggestionsContextCollectionTimedOut(surface: AIChatContextualSuggestionsSurface)

    // MARK: - Recent Chats Menu
    func fireRecentChatsMenuDisplayed()
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
    func firePromptSubmittedWithContext(isFollowUp: Bool)
    func firePromptSubmittedWithoutContext(isFollowUp: Bool)
    func firePromptSubmittedInOngoingChat(hasPageContext: Bool)
    func fireActiveChatDiscardedAfterDeletion()

    // MARK: - Page Context Offer
    func firePageContextOffered()
    func firePageContextOfferAccepted()
    func firePageContextOfferDismissed()

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
    private let firePixelKitEvent: (PixelKit.Event, PixelKit.Frequency) -> Void
    private let featureDiscovery: FeatureDiscovery

    // MARK: - Public Properties

    var isManualAttachInProgress: Bool {
        stateQueue.sync { _isManualAttachInProgress }
    }

    // MARK: - Initialization

    init(firePixel: @escaping (Pixel.Event) -> Void = { PixelKit.fire($0, frequency: .dailyAndCount) },
         firePixelWithParameters: @escaping (Pixel.Event, [String: String]) -> Void = {
             PixelKit.fire($0, frequency: .dailyAndCount, options: .parameters($1))
         },
         firePixelKitEvent: @escaping (PixelKit.Event, PixelKit.Frequency) -> Void = {
             PixelKit.fire($0, frequency: $1)
         },
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery()) {
        self.firePixel = firePixel
        self.firePixelWithParameters = firePixelWithParameters
        self.firePixelKitEvent = firePixelKitEvent
        self.featureDiscovery = featureDiscovery
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

    func fireAddressBarMenuAskAboutSearchSelected() {
        firePixel(.aiChatContextualAddressBarMenuAskAboutSearchSelected)
    }

    func fireAddressBarMenuRecentChatsSelected() {
        firePixelKitEvent(AIChatAddressBarMenuPixel.recentChatsSelected, .dailyAndCount)
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
        firePixelKitEvent(AIChatContextualSelectionPixel.attached, .dailyAndCount)
    }

    func fireSelectionLimitReached() {
        firePixelKitEvent(AIChatContextualSelectionPixel.limitReached, .dailyAndCount)
    }

    func fireSelectionRemoved() {
        firePixelKitEvent(AIChatContextualSelectionPixel.removed, .dailyAndCount)
    }

    func firePromptSubmittedWithSelections(count: Int) {
        let countBucket: String
        switch count {
        case 1: countBucket = "1"
        case 2: countBucket = "2"
        case 3...AIChatSelectionContextBuilder.maxAttachedSelections: countBucket = "3-5"
        default: return
        }
        firePixelKitEvent(AIChatContextualSelectionPixel.promptSubmitted(selectionCount: countBucket), .dailyAndCount)
    }

    func fireSelectionToolDeliveryTimedOut() {
        firePixelKitEvent(AIChatContextualSelectionPixel.toolDeliveryTimedOut, .dailyAndCount)
    }

    // MARK: - Page Context Collection

    func firePageContextCollectionEmpty() {
        firePixel(.aiChatContextualPageContextCollectionEmpty)
    }

    func firePageContextCollectionUnavailable() {
        firePixel(.aiChatContextualPageContextCollectionUnavailable)
    }

    // MARK: - Prompt Submission

    func firePromptSubmittedWithContext(isFollowUp: Bool) {
        firePromptSubmissionPixel(.aiChatContextualPromptSubmittedWithContextNative, isFollowUp: isFollowUp)
    }

    func firePromptSubmittedWithoutContext(isFollowUp: Bool) {
        firePromptSubmissionPixel(.aiChatContextualPromptSubmittedWithoutContextNative, isFollowUp: isFollowUp)
    }

    /// Marking after the fire keeps the first-prompt claim on this submission's pixel; the UTI
    /// prompt pixel for the same submission fires earlier in the flow, so it reads the same state.
    private func firePromptSubmissionPixel(_ event: Pixel.Event, isFollowUp: Bool) {
        var parameters = [PixelParameters.aiChatContextualPromptIsFollowUp: String(isFollowUp)]
        let isFirstPromptOnNewInstall = featureDiscovery.isFirstDuckAIPromptNewInstall
        if isFirstPromptOnNewInstall {
            parameters[PixelParameters.aiChatFirstPromptNewInstall] = "true"
        }
        firePixelWithParameters(event, parameters)
        if isFirstPromptOnNewInstall {
            featureDiscovery.markDuckAIPromptSubmitted()
        }
    }

    /// A reopened chat never reaches the first-prompt paths, so its submissions are reported here.
    func firePromptSubmittedInOngoingChat(hasPageContext: Bool) {
        firePixelWithParameters(.aiChatContextualPromptSubmittedOngoingChat,
                                [PixelParameters.aiChatContextualHasPageContext: String(hasPageContext)])
    }

    func fireActiveChatDiscardedAfterDeletion() {
        firePixel(.aiChatContextualActiveChatDiscardedAfterDeletion)
    }

    // MARK: - Page Context Offer

    func firePageContextOffered() {
        firePixel(.aiChatContextualPageContextOffered)
    }

    func firePageContextOfferAccepted() {
        firePixel(.aiChatContextualPageContextOfferAccepted)
    }

    func firePageContextOfferDismissed() {
        firePixel(.aiChatContextualPageContextOfferDismissed)
    }

    // MARK: - Suggested Prompts

    func fireAskAboutPageSuggestionSelected(pageType: SuggestionsPageType) {
        fireSuggestionSelected(suggestionId: Self.askAboutPageSuggestionId, pageType: pageType, surface: .sheet)
    }

    func fireSuggestionSelected(suggestionId: String, pageType: SuggestionsPageType, surface: AIChatContextualSuggestionsSurface) {
        firePixelWithParameters(.aiChatContextualSuggestionSelected, [
            PixelParameters.suggestionId: suggestionId,
            PixelParameters.aiChatSuggestionsSurface: surface.rawValue,
            PixelParameters.suggestionsPageType: pageType.rawValue
        ])
    }

    func fireSuggestionsViewed(isSmart: Bool,
                               pageType: SuggestionsPageType,
                               scope: ResolvePageSuggestionsInput.Scope,
                               surface: AIChatContextualSuggestionsSurface) {
        firePixelWithParameters(.aiChatContextualSuggestionsViewed, [
            PixelParameters.suggestionsAreSmart: String(isSmart),
            PixelParameters.suggestionsPageType: pageType.rawValue,
            PixelParameters.aiChatSuggestionScope: scope.rawValue,
            PixelParameters.aiChatSuggestionsSurface: surface.rawValue
        ])
    }

    func fireSuggestionsContextCollectionTimedOut(surface: AIChatContextualSuggestionsSurface) {
        firePixelWithParameters(.aiChatContextualSuggestionsContextCollectionTimedOut,
                                [PixelParameters.aiChatSuggestionsSurface: surface.rawValue])
    }

    // MARK: - Recent Chats Menu

    func fireRecentChatsMenuDisplayed() {
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

enum AIChatContextualSuggestionsSurface: String {
    case floatingInput = "floating_input"
    case sheet
    /// The strip shown over a chat already under way, rather than the pre-submit sheet.
    case activeChat = "active_chat"
}

enum AIChatContextualSelectionPixel: PixelKit.Event {
    /// This pixel signature is non-standard and not aligned to the current PixelKit defaults. This policy freezes the signature to a legacy, and incorrect, suffix ordering.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyBeforeFrequencySuffix }

    case attached
    case limitReached
    case removed
    case promptSubmitted(selectionCount: String)
    case toolDeliveryTimedOut

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .attached:
            return "aichat_contextual_selection_attached"
        case .limitReached:
            return "aichat_contextual_selection_limit_reached"
        case .removed:
            return "aichat_contextual_selection_removed"
        case .promptSubmitted:
            return "aichat_contextual_prompt_submitted_with_selections"
        case .toolDeliveryTimedOut:
            return "debug_aichat_contextual_selection_tool_delivery_timed_out"
        }
    }

    var parameters: [String: String]? {
        guard case .promptSubmitted(let selectionCount) = self else { return nil }
        return [PixelParameters.aiChatSelectionCount: selectionCount]
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

enum AIChatAddressBarMenuPixel: PixelKit.Event {
    case recentChatsSelected

    var name: String {
        switch self {
        case .recentChatsSelected:
            return "aichat_contextual_address_bar_menu_all_chats_selected"
        }
    }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
