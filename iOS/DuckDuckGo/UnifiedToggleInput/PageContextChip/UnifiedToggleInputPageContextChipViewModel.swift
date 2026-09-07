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
/// Command-driven so JS-side auto-emissions don't bleed in; the host pushes after attach, detach
/// and suggest. Half-sheet carry-over arrives `.delivered`, so the chat opens silent.
///
/// `state` is what to draw, and `nil` means draw nothing:
///   - loading → `.loading`.
///   - attached + pending → `.attached` until the user submits; delivered → nil.
///   - suggested → `.suggested`, the offer to attach the page navigated to. Not attached until tapped.
///   - otherwise nil. Context attach is also offered from the attachment menu.
@MainActor
final class UnifiedToggleInputPageContextChipViewModel: ObservableObject {

    @Published private(set) var state: AIChatContextChipView.State?

    /// Invoked when the user requests page-context attachment from the attachment menu.
    var onAttachActionRequested: (() -> Void)?

    /// Invoked when the user taps the X on the attached chip.
    var onRemoveActionRequested: (() -> Void)?

    /// Invoked when the user taps the suggested chip, accepting the offer to attach that page.
    var onSuggestionAccepted: ((AIChatPageContext) -> Void)?

    /// Invoked when the user taps the X on the suggested chip.
    var onSuggestionDismissed: (() -> Void)?

    private let isAutoAttachEnabled: () -> Bool
    private(set) var attachedContext: AIChatPageContext?
    private(set) var suggestedContext: AIChatPageContext?
    private var attachedURL: URL?
    private var originatingURL: URL?
    /// Presentation-only pending/delivered flag; set solely by `setAttached`, never decided by the chip.
    private var attachmentDeliveryState: PageContextAttachmentDeliveryState = .pendingSubmit
    private var isShowingAttachAffordance = false
    private var isLoading = false
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered,
        isAutoAttachEnabled: @escaping () -> Bool
    ) {
        self.isAutoAttachEnabled = isAutoAttachEnabled
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
        isLoading = false
        suggestedContext = nil
        updateAttachment(context, deliveryState: deliveryState)
        Logger.contextualUTI.debug("PageContextChip attached")
        recompute()
    }

    /// Offers the page as an attachment without attaching it. Never displaces a pending attachment.
    func setSuggested(_ context: AIChatPageContext) {
        guard pendingAttachedContextData == nil else {
            Logger.contextualUTI.debug("PageContextChip keeping pending attachment instead of suggesting")
            return
        }
        suggestedContext = context
        Logger.contextualUTI.debug("PageContextChip suggested")
        recompute()
    }

    func clearSuggested() {
        guard suggestedContext != nil else { return }
        suggestedContext = nil
        Logger.contextualUTI.debug("PageContextChip suggestion cleared")
        recompute()
    }

    func clearAttached() {
        isShowingAttachAffordance = false
        isLoading = false
        clearAttachmentState()
        Logger.contextualUTI.debug("PageContextChip detached")
        recompute()
    }

    func beginLoading() {
        guard !isLoading else { return }
        isLoading = true
        Logger.contextualUTI.debug("PageContextChip loading")
        recompute()
    }

    func endLoading() {
        guard isLoading else { return }
        isLoading = false
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
        if let suggestedContext {
            Logger.contextualUTI.info("PageContextChip suggestion accepted")
            onSuggestionAccepted?(suggestedContext)
            return
        }
        if let url = originatingURL {
            Logger.contextualUTI.info("PageContext attach requested — attaching \(url.shortDescription, privacy: .private)")
        } else {
            Logger.contextualUTI.info("PageContext attach requested — attaching without originating URL")
        }
        onAttachActionRequested?()
    }

    /// Dismissing a suggestion is not a detach: nothing was attached, so it must not run the removal
    /// path or fire its pixel.
    func tapToRemove() {
        if suggestedContext != nil {
            Logger.contextualUTI.info("PageContextChip suggestion dismissed")
            clearSuggested()
            onSuggestionDismissed?()
            return
        }
        Logger.contextualUTI.info("PageContextChip remove tapped — detaching")
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
        let branch: String

        if isLoading {
            state = .loading
            branch = "loading"
        } else if let ctx = attachedContext, attachmentDeliveryState == .pendingSubmit {
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            branch = "attached"
        } else if let suggestion = suggestedContext {
            state = .suggested(title: suggestion.title, favicon: suggestion.favicon)
            branch = "suggested"
        } else {
            state = nil
            branch = attachedContext != nil ? "attachedDelivered" : "nothing"
        }

        let stateDesc: String = {
            switch state {
            case .suggested(let title, _): return "suggested(\(title))"
            case .attached(let title, _): return "attached(\(title))"
            case .loading: return "loading"
            case nil: return "none"
            }
        }()
        Logger.contextualUTI.debug("ChipViewModel recompute → \(branch, privacy: .public) state=\(stateDesc, privacy: .public) affordance=\(self.isShowingAttachAffordance, privacy: .public) auto=\(self.isAutoAttachEnabled(), privacy: .public) attached=\(self.attachedContext != nil, privacy: .public) attachedURL=\(self.attachedURL?.shortDescription ?? "nil", privacy: .private) originatingURL=\(self.originatingURL?.shortDescription ?? "nil", privacy: .private)")
    }
}
