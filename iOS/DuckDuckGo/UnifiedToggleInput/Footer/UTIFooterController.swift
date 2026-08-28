//
//  UTIFooterController.swift
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
import Foundation
import os.log
import UIKit

@MainActor
protocol UTIFooterPresenting: AnyObject {
    func applyFooterMessage(_ message: UTIFooterMessage?)
    /// State-only drop of a stored-but-unapplied message; must not touch layout or animate.
    func clearPendingFooterMessage()
}

/// Presents the shared usage-limit view model on the Duck.ai input's footer slot. The view model
/// decides what to say; this decides when the card can be on screen, and animates it.
@MainActor
final class UTIFooterController {

    typealias Animator = (_ changes: @escaping () -> Void) -> Void

    private enum Constants {
        static let duration: TimeInterval = 0.4
        static let damping: CGFloat = 0.85
    }

    weak var presenter: UTIFooterPresenting?

    private let viewModel: DuckAiUsageWarningViewModel
    private let mapper: UTIFooterMessageMapper
    private let animator: Animator

    private var isSuppressed = false

    private(set) var currentMessage: UTIFooterMessage?

    init(viewModel: DuckAiUsageWarningViewModel,
         mapper: UTIFooterMessageMapper = UTIFooterMessageMapper(),
         animator: Animator? = nil) {
        self.viewModel = viewModel
        self.mapper = mapper
        self.animator = animator ?? Self.springAnimator
    }

    /// Synchronous: a lookup in the already-loaded entries blob.
    func refresh() {
        viewModel.refresh()
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller refresh → warning=\(self.viewModel.warning == nil ? "none" : "present", privacy: .public) suppressed=\(self.isSuppressed, privacy: .public)")
        applyCurrentState()
    }

    func resetForPoseChange() {
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller reset for pose change")
        // Not a dismissal: the next refresh re-reads the snapshot and the message comes back.
        viewModel.clear()
        currentMessage = nil
        // Keeps the view's copy in lockstep — otherwise a later refresh that resolves to no
        // warning no-ops (nil == nil) and the view resurrects the stale card on the next expand.
        presenter?.clearPendingFooterMessage()
    }

    func setSuppressed(_ suppressed: Bool) {
        guard isSuppressed != suppressed else { return }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller suppressed=\(suppressed, privacy: .public)")
        isSuppressed = suppressed
        applyCurrentState()
    }

    /// Persisted by the view model, so the message stays down until the window resets or the user
    /// crosses the next redisplay threshold.
    func dismissCurrent() {
        viewModel.dismiss()
        applyCurrentState()
    }

    func performPrimaryAction() {
        guard currentMessage?.primaryAction != nil else { return }
        viewModel.performAction()
        // The CTA can change what there is left to offer — a model switch retires its own suggestion.
        applyCurrentState()
    }

    private func applyCurrentState() {
        let message = resolveMessage()
        guard message != currentMessage else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller no-op: message unchanged (\(message == nil ? "nil" : "visible", privacy: .public))")
            return
        }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller applying: \(message?.title ?? "nil", privacy: .public)")
        currentMessage = message
        animator { [weak self] in
            self?.presenter?.applyFooterMessage(message)
        }
    }

    private func resolveMessage() -> UTIFooterMessage? {
        guard !isSuppressed else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] nothing to show: suppressed (editing or Search mode)")
            return nil
        }
        guard let warning = viewModel.warning else { return nil }
        return mapper.message(for: warning)
    }

    static let springAnimator: Animator = { changes in
        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(withDuration: Constants.duration,
                       delay: 0,
                       usingSpringWithDamping: Constants.damping,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: changes)
    }
}
