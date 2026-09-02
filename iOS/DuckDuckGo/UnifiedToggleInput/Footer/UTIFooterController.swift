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
    private let measurement: DuckAiUsageWarningMeasurement
    private let createImagePixelFiring: CreateImagePixelFiring
    private let animator: Animator

    private var isSuppressed = false
    /// The message the user acted on, held so the CTA can retire one that carries no close button.
    private var actedOnMessage: UTIFooterMessage?
    /// What the current message is about, for the pixels. Kept in step with `currentMessage`.
    private var currentExposure: DuckAiUsageWarningExposure?

    private var modelSwitchNotice: CreateImageModelSwitchNotice?

    private(set) var currentMessage: UTIFooterMessage?

    init(viewModel: DuckAiUsageWarningViewModel,
         highUsageNotice: UTIFooterHighUsageNoticeSource? = nil,
         mapper: UTIFooterMessageMapper = UTIFooterMessageMapper(),
         measurement: DuckAiUsageWarningMeasurement = DuckAiUsageWarningMeasurement(),
         createImagePixelFiring: CreateImagePixelFiring,
         animator: Animator? = nil) {
        self.viewModel = viewModel
        self.highUsageNotice = highUsageNotice
        self.mapper = mapper
        self.measurement = measurement
        self.createImagePixelFiring = createImagePixelFiring
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
        measurement.inputSessionEnded()
        viewModel.clear()
        highUsageNotice?.clear()
        currentMessage = nil
        currentExposure = nil
        // Keeps the view's copy in lockstep — otherwise a later refresh that resolves to no
        // warning no-ops (nil == nil) and the view resurrects the stale card on the next expand.
        presenter?.clearPendingFooterMessage()
    }

    func setSuppressed(_ suppressed: Bool) {
        guard isSuppressed != suppressed else { return }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller suppressed=\(suppressed, privacy: .public)")
        isSuppressed = suppressed
        // Editing a previous prompt, or leaving Duck.ai mode, settles what the user did about the message.
        if suppressed {
            measurement.inputSessionEnded()
        }
        applyCurrentState()
    }

    func showModelSwitchNotice(_ notice: CreateImageModelSwitchNotice) {
        modelSwitchNotice = notice
        applyCurrentState()
    }

    func clearModelSwitchNotice() {
        guard modelSwitchNotice != nil else { return }
        modelSwitchNotice = nil
        applyCurrentState()
    }

    /// The user closing the card. A model switch is not a usage warning. It spends neither the
    /// warning's dismissal record nor its pixel.
    func dismissCurrent() {
        if modelSwitchNotice != nil {
            modelSwitchNotice = nil
            createImagePixelFiring.modelSwitchNoticeDismissed()
            applyCurrentState()
            return
        }
        measurement.warningDismissed()
        retireCurrent()
    }

    /// The card entering or leaving the footer slot. Only entering is an impression: the exposure
    /// outlives the card, so a prompt sent after a dismissal still belongs to the message.
    func footerVisibilityChanged(isVisible: Bool) {
        guard isVisible, let exposure = currentExposure else { return }
        measurement.cardBecameVisible(exposure)
    }

    func recordPromptSubmitted() {
        measurement.promptSubmitted()
    }

    /// A switch from the bar's picker: always reported, but it only retires the message when it is the
    /// step down the message asked for. The card's own CTA reports and retires itself.
    func userSwitchedModel(from previousModelId: String?, to modelId: String) {
        measurement.modelSwitched()
        viewModel.userSwitchedModel(from: previousModelId, to: modelId)
        applyCurrentState()
    }

    func performPrimaryAction() {
        guard let message = currentMessage, message.primaryAction != nil else { return }

        if let cta = Self.cta(for: viewModel.warning?.action) {
            measurement.ctaTapped(cta)
        }
        let switchesModel = currentActionSwitchesModel
        viewModel.performAction()
        // The upsell leaves the user just as blocked, so only a switch retires its message.
        guard switchesModel else { return applyCurrentState() }

        actedOnMessage = message
        retireCurrent()
    }

    /// Spends the message's own dismissal record without reporting a close: also how a taken CTA
    /// retires a card that carries no close button.
    private func retireCurrent() {
        // The two dismissals are recorded separately, so each message spends only its own.
        if viewModel.warning != nil {
            viewModel.dismiss()
        } else {
            highUsageNotice?.dismissCurrent()
        }
        applyCurrentState()
    }

    private static func cta(for action: DuckAiUsageAction?) -> DuckAiUsageWarningMeasurement.CTA? {
        switch action {
        case .switchToModel, .switchToFreeModel: return .switchModel
        case .tryForFree: return .upsell
        case .startUsingWeeklyLimit, .none: return nil
        }
    }

    private var currentActionSwitchesModel: Bool {
        switch viewModel.warning?.action {
        case .switchToModel, .switchToFreeModel: return true
        default: return false
        }
    }

    private func applyCurrentState() {
        let card = resolveCard()
        let message = card?.message
        guard message != currentMessage else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller no-op: message unchanged (\(message == nil ? "nil" : "visible", privacy: .public))")
            return
        }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller applying: \(message?.title ?? "nil", privacy: .public)")
        currentMessage = message
        // Set before the presenter runs: applying can reveal the card synchronously, and the
        // impression that reports needs the exposure it belongs to.
        currentExposure = card.flatMap(\.exposure)
        animator { [weak self] in
            self?.presenter?.applyFooterMessage(message)
        }
    }

    private struct ResolvedCard {
        let message: UTIFooterMessage
        /// `nil` for a card that is not a usage warning, so it reports no usage-warning pixel.
        let exposure: DuckAiUsageWarningExposure?
    }

    /// One slot: the model switch outranks an actionable warning, which outranks the informational
    /// notice.
    private func resolveCard() -> ResolvedCard? {
        guard !isSuppressed else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] nothing to show: suppressed (editing or Search mode)")
            return nil
        }
        // The model switch is something the app just did to the user's selection, so it outranks a
        // usage warning, which stays available once the notice is gone. It carries no CTA, so the
        // acted-on check never applies to it.
        if let modelSwitchNotice {
            return ResolvedCard(message: mapper.message(for: modelSwitchNotice), exposure: nil)
        }
        if let warning = viewModel.warning {
            guard let message = unlessActedOn(mapper.message(for: warning)) else { return nil }
            return ResolvedCard(message: message, exposure: DuckAiUsageWarningExposure(warning: warning))
        }
        if let notice = highUsageNotice?.notice {
            guard let message = unlessActedOn(mapper.message(for: notice)) else { return nil }
            return ResolvedCard(message: message, exposure: DuckAiUsageWarningExposure(notice: notice))
        }
        return nil
    }

    /// Releases as soon as the resolver produces a different message, so the next rung still shows,
    /// and once the acted-on record is gone, so clearing it is not undone by this copy.
    private func unlessActedOn(_ message: UTIFooterMessage) -> UTIFooterMessage? {
        guard viewModel.hasActedOnCurrentNotice, message == actedOnMessage else { return message }
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

/// Applies the shared resolver to the selected model, and remembers dismissals per model.
@MainActor
final class UTIFooterHighUsageNoticeSource {

    private let resolver: DuckAIHighUsageModelNoticeResolver
    private let dismissalStore: DuckAiHighUsageNoticeDismissalStoring
    /// Re-read per refresh, so switching models mid-session is picked up.
    private let modelProvider: () -> (id: String?, shortName: String?)

    private(set) var notice: DuckAiHighUsageModelNotice?

    init(dismissalStore: DuckAiHighUsageNoticeDismissalStoring = DuckAiHighUsageNoticeDismissalStore(),
         modelProvider: @escaping () -> (id: String?, shortName: String?)) {
        self.dismissalStore = dismissalStore
        self.resolver = DuckAIHighUsageModelNoticeResolver(dismissalStore: dismissalStore)
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
