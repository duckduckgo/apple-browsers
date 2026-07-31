//
//  UnifiedToggleInputPageContextChipViewModel.swift
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
import Combine
import Foundation
import UIKit
import os.log

enum PageContextAttachmentDeliveryState {
    case pendingSubmit
    case delivered
}

/// Drives the page-context chip in the contextual chat UTI.
///
/// `attachedContext` is command-driven so JS-side auto-emissions don't bleed in; the host
/// pushes after attach/detach. Auto-attach OFF clears on nav-away (mirrors legacy FE); ON
/// preserves the attachment while the host re-collects. Half-sheet carry-over arrives
/// `.delivered`, so the chat opens silent.
///
/// Visibility:
///   - attach affordance command → hidden placeholder.
///   - attached + pending → `.attached` feedback until the user submits.
///   - attached + delivered → hidden (already submitted).
///   - no attachment → hidden placeholder. Context attach is offered from the attachment menu.
@MainActor
final class UnifiedToggleInputPageContextChipViewModel: ObservableObject {

    @Published private(set) var state: AIChatContextChipView.State = .placeholder
    @Published private(set) var isVisible: Bool = false

    /// Invoked when the user requests page-context attachment from the attachment menu.
    var onAttachActionRequested: (() -> Void)?

    /// Invoked when the user taps the X on the attached chip.
    var onRemoveActionRequested: (() -> Void)?

    private let isAutoAttachEnabled: () -> Bool
    /// Whether removing the page context leaves a re-attach button in place of the pill.
    private let showsAttachAffordance: Bool
    private(set) var attachedContext: AIChatPageContext?
    private var attachedURL: URL?
    private var originatingURL: URL?
    /// Presentation-only pending/delivered flag; set solely by `setAttached`, never decided by the chip.
    private var attachmentDeliveryState: PageContextAttachmentDeliveryState = .pendingSubmit
    private var isShowingAttachAffordance = false
    /// Set only by an explicit removal, so the button appears in place of the pill the user dismissed.
    private var isOfferingReattach = false
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered,
        isAutoAttachEnabled: @escaping () -> Bool,
        showsAttachAffordance: Bool = false
    ) {
        self.isAutoAttachEnabled = isAutoAttachEnabled
        self.showsAttachAffordance = showsAttachAffordance
        self.attachedContext = initialAttachedContext
        self.attachedURL = Self.url(of: initialAttachedContext)
        self.attachmentDeliveryState = initialAttachedContext == nil ? .pendingSubmit : initialAttachmentDeliveryState
        Logger.contextualUTI.debug("ChipViewModel init — carryOver=\(initialAttachedContext != nil, privacy: .public) auto=\(isAutoAttachEnabled(), privacy: .public)")
        originatingURLPublisher
            .sink { [weak self] url in
                guard let self else { return }
                Logger.contextualUTI.debug("ChipViewModel originatingURL changed → \(url?.shortDescription ?? "nil", privacy: .private)")
                self.originatingURL = url
                self.recompute()
            }
            .store(in: &cancellables)
        recompute()
    }

    func setAttached(_ context: AIChatPageContext, deliveryState: PageContextAttachmentDeliveryState = .pendingSubmit) {
        isShowingAttachAffordance = false
        isOfferingReattach = false
        updateAttachment(context, deliveryState: deliveryState)
        Logger.contextualUTI.debug("PageContextChip attached")
        recompute()
    }

    /// Deliberately leaves `isOfferingReattach` alone: removing the context makes the coordinator clear
    /// the page-context handler, which delivers a nil context straight back here, so resetting the
    /// offer would cancel the button a frame after the removal that asked for it.
    func clearAttached() {
        isShowingAttachAffordance = false
        clearAttachmentState()
        Logger.contextualUTI.debug("PageContextChip detached")
        recompute()
    }

    /// Cancels a pending re-attach offer, for session boundaries such as starting a new chat.
    func clearReattachOffer() {
        guard isOfferingReattach else { return }
        isOfferingReattach = false
        recompute()
    }

    func showAttachAffordance() {
        guard pendingAttachedContextData == nil else {
            Logger.contextualUTI.debug("PageContextChip keeping pending attachment instead of showing attach affordance")
            return
        }
        isShowingAttachAffordance = true
        Logger.contextualUTI.debug("PageContextChip showing attach affordance")
        recompute()
    }

    func tapToAttach() {
        if let url = originatingURL {
            Logger.contextualUTI.info("PageContext attach requested — attaching \(url.shortDescription, privacy: .private)")
        } else {
            Logger.contextualUTI.info("PageContext attach requested — attaching without originating URL")
        }
        onAttachActionRequested?()
    }

    func tapToRemove() {
        Logger.contextualUTI.info("PageContextChip remove tapped — detaching")
        // Set before clearing so `clearAttached`'s own recompute lands the final state in one pass.
        // Publishing twice would make the strip drop the chip and re-add it, costing two layout passes.
        // Only an explicit removal leaves the re-attach button behind; clearing for any other reason
        // (a new chat, say) leaves the strip empty rather than inviting a re-attach.
        isOfferingReattach = showsAttachAffordance
        clearAttached()
        onRemoveActionRequested?()
    }

    var pendingAttachedContextData: AIChatPageContextData? {
        guard attachmentDeliveryState == .pendingSubmit else { return nil }
        return attachedContext?.contextData
    }

    private func updateAttachment(_ context: AIChatPageContext?, deliveryState: PageContextAttachmentDeliveryState) {
        attachedContext = context
        attachedURL = Self.url(of: context)
        attachmentDeliveryState = deliveryState
    }

    private func clearAttachmentState() {
        attachedContext = nil
        attachedURL = nil
        attachmentDeliveryState = .pendingSubmit
    }

    private static func url(of context: AIChatPageContext?) -> URL? {
        context.flatMap { URL(string: $0.contextData.url) }
    }

    private func recompute() {
        let isMatching = attachedURL != nil && attachedURL == originatingURL
        let branch: String

        if isShowingAttachAffordance || isOfferingReattach {
            state = .placeholder
            // Only an explicit removal shows the re-attach button. The attach-affordance command is a
            // separate, pre-existing signal whose contract is a hidden placeholder — keying visibility
            // off the feature flag instead would have made that path render the button too.
            isVisible = isOfferingReattach
            branch = "attachAffordance(reattachOffer=\(isOfferingReattach))"
        } else if let ctx = attachedContext {
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            isVisible = attachmentDeliveryState == .pendingSubmit
            branch = "attached(matching=\(isMatching), deliveryState=\(attachmentDeliveryState))"
        } else {
            state = .placeholder
            isVisible = false
            branch = "noAttachment"
        }

        let stateDesc: String = {
            switch state {
            case .placeholder: return "placeholder"
            case .attached(let title, _): return "attached(\(title))"
            }
        }()
        Logger.contextualUTI.debug("ChipViewModel recompute → \(branch, privacy: .public) state=\(stateDesc, privacy: .public) isVisible=\(self.isVisible, privacy: .public) auto=\(self.isAutoAttachEnabled(), privacy: .public) attached=\(self.attachedContext != nil, privacy: .public) attachedURL=\(self.attachedURL?.shortDescription ?? "nil", privacy: .private) originatingURL=\(self.originatingURL?.shortDescription ?? "nil", privacy: .private)")
    }
}
