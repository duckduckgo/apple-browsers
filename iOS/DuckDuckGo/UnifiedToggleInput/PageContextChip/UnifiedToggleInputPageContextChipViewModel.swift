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
///   - attach affordance command → placeholder.
///   - attached + pending → `.attached` feedback until the user submits.
///   - attached + delivered → hidden (already submitted).
///   - no attachment → placeholder. The half-sheet is the user's attach/skip gate; once
///     they're in the chat, an empty state always offers a tap target.
@MainActor
final class UnifiedToggleInputPageContextChipViewModel: ObservableObject {

    @Published private(set) var state: AIChatContextChipView.State = .placeholder
    @Published private(set) var isVisible: Bool = false

    /// Invoked when the user taps the placeholder chip.
    var onAttachActionRequested: (() -> Void)?

    /// Invoked when the user taps the X on the attached chip.
    var onRemoveActionRequested: (() -> Void)?

    private let isAutoAttachEnabled: () -> Bool
    private(set) var attachedContext: AIChatPageContext?
    private var attachedURL: URL?
    private var originatingURL: URL?
    /// Whether the current attachment is waiting to be included in a prompt or has already
    /// been delivered. `markPromptSubmitted()` flips pending attachments to delivered.
    private var attachmentDeliveryState: PageContextAttachmentDeliveryState = .pendingSubmit
    private var isShowingAttachAffordance = false
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
        updateAttachment(context, deliveryState: deliveryState)
        Logger.contextualUTI.debug("PageContextChip attached")
        recompute()
    }

    func clearAttached() {
        isShowingAttachAffordance = false
        clearAttachmentState()
        Logger.contextualUTI.debug("PageContextChip detached")
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
            Logger.contextualUTI.info("PageContextChip placeholder tapped — attaching \(url.shortDescription, privacy: .private)")
        } else {
            Logger.contextualUTI.info("PageContextChip placeholder tapped — attaching without originating URL")
        }
        onAttachActionRequested?()
    }

    func tapToRemove() {
        Logger.contextualUTI.info("PageContextChip remove tapped — detaching")
        clearAttached()
        onRemoveActionRequested?()
    }

    var pendingAttachedContextData: AIChatPageContextData? {
        guard attachmentDeliveryState == .pendingSubmit else { return nil }
        return attachedContext?.contextData
    }

    /// Mark the current attachment as delivered (submitted in a prompt). Hides the chip if the
    /// attachment is matching — we don't need to keep showing what's silently riding along.
    func markPromptSubmitted() {
        guard attachedContext != nil, attachmentDeliveryState != .delivered else { return }
        attachmentDeliveryState = .delivered
        recompute()
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

        if isShowingAttachAffordance {
            state = .placeholder
            isVisible = true
            branch = "attachAffordance"
        } else if let ctx = attachedContext {
            state = .attached(title: ctx.title, favicon: ctx.favicon)
            isVisible = attachmentDeliveryState == .pendingSubmit
            branch = "attached(matching=\(isMatching), deliveryState=\(attachmentDeliveryState))"
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
        Logger.contextualUTI.debug("ChipViewModel recompute → \(branch, privacy: .public) state=\(stateDesc, privacy: .public) isVisible=\(self.isVisible, privacy: .public) auto=\(self.isAutoAttachEnabled(), privacy: .public) attached=\(self.attachedContext != nil, privacy: .public) attachedURL=\(self.attachedURL?.shortDescription ?? "nil", privacy: .private) originatingURL=\(self.originatingURL?.shortDescription ?? "nil", privacy: .private)")
    }
}
