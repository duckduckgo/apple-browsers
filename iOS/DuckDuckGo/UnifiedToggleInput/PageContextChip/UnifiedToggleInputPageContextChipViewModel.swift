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
/// `attachedContext` is command-driven (`setAttached(_:)`) so JS-side auto-emissions don't bleed
/// into the chip; only the host pushes after a successful attach/detach. With auto-attach OFF,
/// navigating away clears the attachment (mirrors legacy FE); with ON, it's preserved while the
/// host re-collects.
///
/// Visibility:
///   - attachment exists AND URL matches AND already submitted with → hidden (FE keeps using
///     it silently; on-screen chip would be redundant noise).
///   - attachment exists AND URL matches AND not yet submitted → show as `.attached` so the
///     user sees confirmation of what they just attached, until they submit a prompt.
///   - no attachment → placeholder (regardless of mode — the half-sheet is where the user
///     exercises their attach/skip agency; once they're in the chat, an empty state should
///     always offer a tap target so they can re-attach if they change their mind).
///   - auto mode + pending attachment but URL doesn't match → show `.attached` (transition
///     between nav and re-attach; avoids placeholder flash for visible pending feedback).
///   - auto mode + delivered attachment but URL doesn't match → keep hidden until the new
///     page's context lands; otherwise the already-silent old chip briefly reappears.
/// Half-sheet carry-over starts in the "already submitted" state — the half-sheet sent the
/// first prompt with that attachment, so the chat opens silent.
@MainActor
final class UnifiedToggleInputPageContextChipViewModel: ObservableObject {

    @Published private(set) var state: AIChatContextChipView.State = .placeholder
    @Published private(set) var isVisible: Bool = false

    /// Invoked when the user taps the placeholder chip and an originating URL is available.
    var onAttachActionRequested: ((URL) -> Void)?

    /// Invoked when the user taps the X on the attached chip.
    var onRemoveActionRequested: (() -> Void)?

    private let isAutoAttachEnabled: () -> Bool
    private(set) var attachedContext: AIChatPageContext?
    private var attachedURL: URL?
    private var originatingURL: URL?
    /// Whether the current attachment is waiting to be included in a prompt or has already
    /// been delivered. `markPromptSubmitted()` flips pending attachments to delivered.
    private var attachmentDeliveryState: PageContextAttachmentDeliveryState = .pendingSubmit
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
                Logger.contextualUTI.debug("ChipViewModel originatingURL changed → \(url?.absoluteString ?? "nil", privacy: .private)")
                self.originatingURL = url
                if self.shouldClearOnNavigationAway { self.clearAttachedDueToNavigationAway() }
                self.recompute()
            }
            .store(in: &cancellables)
        recompute()
    }

    func setAttached(_ context: AIChatPageContext, deliveryState: PageContextAttachmentDeliveryState = .pendingSubmit) {
        updateAttachment(context, deliveryState: deliveryState)
        Logger.contextualUTI.debug("PageContextChip attached")
        recompute()
    }

    func clearAttached() {
        clearAttachmentState()
        Logger.contextualUTI.debug("PageContextChip detached")
        recompute()
    }

    func tapToAttach() {
        guard let url = originatingURL else {
            Logger.contextualUTI.debug("PageContextChip tapped but no originating URL — ignoring")
            return
        }
        Logger.contextualUTI.info("PageContextChip placeholder tapped — attaching \(url.absoluteString, privacy: .private)")
        onAttachActionRequested?(url)
    }

    func tapToRemove() {
        Logger.contextualUTI.info("PageContextChip remove tapped — detaching")
        onRemoveActionRequested?()
    }

    /// Mark the current attachment as delivered (submitted in a prompt). Hides the chip if the
    /// attachment is matching — we don't need to keep showing what's silently riding along.
    func markPromptSubmitted() {
        guard attachedContext != nil, attachmentDeliveryState != .delivered else { return }
        attachmentDeliveryState = .delivered
        recompute()
    }

    private var shouldClearOnNavigationAway: Bool {
        guard let attachedURL, attachedURL != originatingURL else { return false }
        return !isAutoAttachEnabled()
    }

    private func clearAttachedDueToNavigationAway() {
        Logger.contextualUTI.debug("PageContextChip clearing attachment — tab navigated away (auto-attach OFF)")
        clearAttachmentState()
        // Propagate through the host so it clears the page-context handler buffer and pushes
        // nil to the FE — otherwise `AIChatUserScript.lastPushedPageContext` retains the stale
        // context and the next prompt would still carry it (chip shows detached, but AI sees
        // the old page).
        onRemoveActionRequested?()
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

        if isMatching, let ctx = attachedContext {
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            // Show as feedback until the user submits the prompt; then go silent.
            isVisible = attachmentDeliveryState == .pendingSubmit
            branch = "matching(deliveryState=\(attachmentDeliveryState))"
        } else if let ctx = attachedContext, isAutoAttachEnabled() {
            // Auto mode mid-transition (URL changed, re-attach not yet landed): keep showing the
            // attached site only if it was already visible feedback.
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            isVisible = attachmentDeliveryState == .pendingSubmit
            branch = "autoTransition(deliveryState=\(attachmentDeliveryState))"
        } else {
            // No attachment: always show placeholder so the user can attach. The half-sheet
            // is the gate for "do I want to attach this page?"; once we're in the chat, an
            // empty state needs an affordance.
            state = .placeholder
            isVisible = true
            branch = "noAttachment"
        }

        let stateDesc: String = {
            switch state {
            case .placeholder: return "placeholder"
            case .attached(let title, _): return "attached(\(title))"
            }
        }()
        Logger.contextualUTI.debug("ChipViewModel recompute → \(branch, privacy: .public) state=\(stateDesc, privacy: .public) isVisible=\(self.isVisible, privacy: .public) auto=\(self.isAutoAttachEnabled(), privacy: .public) attached=\(self.attachedContext != nil, privacy: .public) attachedURL=\(self.attachedURL?.absoluteString ?? "nil", privacy: .private) originatingURL=\(self.originatingURL?.absoluteString ?? "nil", privacy: .private)")
    }
}
