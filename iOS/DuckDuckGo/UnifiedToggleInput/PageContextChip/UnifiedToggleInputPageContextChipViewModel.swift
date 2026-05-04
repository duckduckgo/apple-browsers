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
///   - manual mode + no attachment → placeholder (user can attach).
///   - auto mode + attached but URL doesn't match → show `.attached` (transition between nav
///     and re-attach; avoids placeholder flash).
///   - auto mode + no attachment → hidden (waiting for auto-attach, or user detached).
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
    /// Whether the current attachment has already been included in a submitted prompt. Resets
    /// to false on every attachment change (new context = new "needs feedback" cycle); flips
    /// true on `markPromptSubmitted()` and starts true for half-sheet carry-over.
    private var attachmentDelivered: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        isAutoAttachEnabled: @escaping () -> Bool
    ) {
        self.isAutoAttachEnabled = isAutoAttachEnabled
        self.attachedContext = initialAttachedContext
        self.attachedURL = Self.url(of: initialAttachedContext)
        // Carry-over implies the half-sheet already submitted with this attachment.
        self.attachmentDelivered = initialAttachedContext != nil
        originatingURLPublisher
            .sink { [weak self] url in
                guard let self else { return }
                self.originatingURL = url
                if self.shouldClearOnNavigationAway { self.clearAttachment() }
                self.recompute()
            }
            .store(in: &cancellables)
        recompute()
    }

    func setAttached(_ context: AIChatPageContext?) {
        updateAttachment(context)
        if context == nil {
            Logger.contextualUTI.debug("PageContextChip detached")
        } else {
            Logger.contextualUTI.debug("PageContextChip attached")
        }
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
        guard !attachmentDelivered else { return }
        attachmentDelivered = true
        recompute()
    }

    private var shouldClearOnNavigationAway: Bool {
        guard let attachedURL, attachedURL != originatingURL else { return false }
        return !isAutoAttachEnabled()
    }

    private func clearAttachment() {
        Logger.contextualUTI.debug("PageContextChip clearing attachment — tab navigated away (auto-attach OFF)")
        updateAttachment(nil)
        // Propagate through the host so it clears the page-context handler buffer and pushes
        // nil to the FE — otherwise `AIChatUserScript.lastPushedPageContext` retains the stale
        // context and the next prompt would still carry it (chip shows detached, but AI sees
        // the old page).
        onRemoveActionRequested?()
    }

    private func updateAttachment(_ context: AIChatPageContext?) {
        attachedContext = context
        attachedURL = Self.url(of: context)
        attachmentDelivered = false
    }

    private static func url(of context: AIChatPageContext?) -> URL? {
        context.flatMap { URL(string: $0.contextData.url) }
    }

    private func recompute() {
        let isMatching = attachedURL != nil && attachedURL == originatingURL

        if isMatching, let ctx = attachedContext {
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            // Show as feedback until the user submits the prompt; then go silent.
            isVisible = !attachmentDelivered
        } else if let ctx = attachedContext, isAutoAttachEnabled() {
            // Auto mode mid-transition (URL changed, re-attach not yet landed): keep showing the
            // attached site rather than flashing placeholder.
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            isVisible = true
        } else if isAutoAttachEnabled() {
            // Auto + no attachment: hidden — auto-attach is in flight (cold start) or the user
            // explicitly detached and we trust them to navigate / reopen chat to retrigger.
            state = .placeholder
            isVisible = false
        } else {
            // Manual: always show placeholder so the user can attach.
            state = .placeholder
            isVisible = true
        }
    }
}
