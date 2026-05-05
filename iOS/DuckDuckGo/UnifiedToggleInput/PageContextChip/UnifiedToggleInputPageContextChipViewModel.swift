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
///   - attached + URL matches + delivered → hidden (FE silently uses it).
///   - attached + URL matches + pending → `.attached` feedback until the user submits.
///   - attached + URL doesn't match + auto ON → `.attached` only if pending; if delivered,
///     stay hidden until the new page's context lands (otherwise a silent old chip briefly
///     reappears during nav transition).
///   - no attachment → placeholder. The half-sheet is the user's attach/skip gate; once
///     they're in the chat, an empty state always offers a tap target.
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
        // Propagate through the host so it also clears the page-context handler — otherwise
        // its cached context survives and the next prompt would carry stale context.
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
            isVisible = attachmentDeliveryState == .pendingSubmit
            branch = "matching(deliveryState=\(attachmentDeliveryState))"
        } else if let ctx = attachedContext, isAutoAttachEnabled() {
            // Auto-mode nav transition: keep showing the attached site only if it was
            // pending feedback; if delivered, stay hidden so we don't briefly resurrect it.
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            isVisible = attachmentDeliveryState == .pendingSubmit
            branch = "autoTransition(deliveryState=\(attachmentDeliveryState))"
        } else {
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
