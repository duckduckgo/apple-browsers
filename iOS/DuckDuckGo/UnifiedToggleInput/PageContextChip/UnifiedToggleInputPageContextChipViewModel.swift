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
/// host re-collects. `isVisible` stays false until the first navigation after init, so the chip
/// doesn't re-confirm what the user just did in the half-sheet.
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
    private var hasObservedFirstURL = false
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        isAutoAttachEnabled: @escaping () -> Bool
    ) {
        self.isAutoAttachEnabled = isAutoAttachEnabled
        self.attachedContext = initialAttachedContext
        self.attachedURL = Self.url(of: initialAttachedContext)
        originatingURLPublisher
            .sink { [weak self] url in
                guard let self else { return }
                if self.hasObservedFirstURL {
                    if !self.isVisible { self.isVisible = true }
                } else {
                    self.hasObservedFirstURL = true
                }
                self.originatingURL = url
                if self.shouldClearOnNavigationAway { self.clearAttachment() }
                self.recomputeState()
            }
            .store(in: &cancellables)
        recomputeState()
    }

    func setAttached(_ context: AIChatPageContext?) {
        updateAttachment(context)
        if context == nil {
            Logger.contextualUTI.debug("PageContextChip detached")
        } else {
            Logger.contextualUTI.debug("PageContextChip attached")
        }
        recomputeState()
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
    }

    private static func url(of context: AIChatPageContext?) -> URL? {
        context.flatMap { URL(string: $0.contextData.url) }
    }

    private func recomputeState() {
        guard let attachedContext, let attachedURL else {
            state = .placeholder
            return
        }
        if attachedURL == originatingURL {
            state = .attached(title: attachedContext.title, favicon: attachedContext.favicon)
        } else {
            state = .placeholder
        }
    }
}
