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
    private let highUsageNotice: UTIFooterHighUsageNoticeSource?
    private let mapper: UTIFooterMessageMapper
    private let urlOpener: URLOpener
    private let animator: Animator

    private var isSuppressed = false

    private(set) var currentMessage: UTIFooterMessage?

    init(viewModel: DuckAiUsageWarningViewModel,
         highUsageNotice: UTIFooterHighUsageNoticeSource? = nil,
         mapper: UTIFooterMessageMapper = UTIFooterMessageMapper(),
         urlOpener: URLOpener = UIApplication.shared,
         animator: Animator? = nil) {
        self.viewModel = viewModel
        self.highUsageNotice = highUsageNotice
        self.mapper = mapper
        self.urlOpener = urlOpener
        self.animator = animator ?? Self.springAnimator
    }

    /// Synchronous: a lookup in the already-loaded entries blob.
    func refresh() {
        viewModel.refresh()
        highUsageNotice?.refresh()
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller refresh → warning=\(self.viewModel.warning == nil ? "none" : "present", privacy: .public) suppressed=\(self.isSuppressed, privacy: .public)")
        applyCurrentState()
    }

    func resetForPoseChange() {
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller reset for pose change")
        // Not a dismissal: the next refresh re-reads the snapshot and the message comes back.
        viewModel.clear()
        highUsageNotice?.clear()
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

    /// Routed to whichever message owns the slot: the two dismissals are recorded separately, so
    /// closing a usage warning must not also spend the notice's.
    func dismissCurrent() {
        if viewModel.warning != nil {
            viewModel.dismiss()
        } else {
            highUsageNotice?.dismissCurrent()
        }
        applyCurrentState()
    }

    func performPrimaryAction() {
        guard currentMessage?.primaryAction != nil else { return }
        viewModel.performAction()
        // The CTA can change what there is left to offer — a model switch retires its own suggestion.
        applyCurrentState()
    }

    func performLinkAction() {
        guard let url = currentMessage?.link?.url else { return }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] footer link opened")
        urlOpener.open(url)
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

    /// A usage warning is actionable and the notice is only informational, so the warning takes the slot.
    private func resolveMessage() -> UTIFooterMessage? {
        guard !isSuppressed else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] nothing to show: suppressed (editing or Search mode)")
            return nil
        }
        if let warning = viewModel.warning {
            return mapper.message(for: warning)
        }
        if let notice = highUsageNotice?.notice {
            return mapper.message(for: notice)
        }
        return nil
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

// MARK: - High-usage model notice

/// Owns the high-usage-model notice for the footer slot: applies the shared resolver to whichever
/// model is selected now, and remembers dismissals per model.
@MainActor
final class UTIFooterHighUsageNoticeSource {

    private let resolver: DuckAiHighUsageModelNoticeResolver
    private let dismissalStore: DuckAiHighUsageNoticeDismissalStoring
    /// Re-read per refresh, so switching models mid-session is picked up.
    private let modelProvider: () -> (id: String?, shortName: String?)

    private(set) var notice: DuckAiHighUsageModelNotice?

    init(dismissalStore: DuckAiHighUsageNoticeDismissalStoring = DuckAiHighUsageNoticeDismissalStore(),
         modelProvider: @escaping () -> (id: String?, shortName: String?)) {
        self.dismissalStore = dismissalStore
        self.resolver = DuckAiHighUsageModelNoticeResolver(dismissalStore: dismissalStore)
        self.modelProvider = modelProvider
    }

    func refresh() {
        let model = modelProvider()
        switch resolver.resolve(modelId: model.id, modelShortName: model.shortName) {
        case .notice(let notice):
            self.notice = notice
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] high-usage notice: model=\(notice.modelId, privacy: .public)")
        case .none(let reason):
            notice = nil
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] high-usage notice: none — reason=\(reason.rawValue, privacy: .public)")
        }
    }

    /// One-time per model: there is no reset window to expire against.
    func dismissCurrent() {
        guard let notice else { return }
        dismissalStore.setDismissed(modelId: notice.modelId)
        self.notice = nil
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] high-usage notice dismissed: model=\(notice.modelId, privacy: .public)")
    }

    /// Teardown: drops the notice without recording a dismissal.
    func clear() {
        notice = nil
    }
}
