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
import UIKit
import os.log

@MainActor
protocol UTIFooterPresenting: AnyObject {
    func applyFooterMessages(_ messages: [UTIFooterItem])
    func clearPendingFooterMessage()
}

@MainActor
final class UTIFooterController {
    typealias Animator = (_ changes: @escaping () -> Void) -> Void

    weak var presenter: UTIFooterPresenting?
    var onInputBlockChanged: ((Bool) -> Void)?
    var onAttachmentPrivacyEvent: ((AttachmentPrivacyPixel.Action, AttachmentPrivacyPixel.Kind) -> Void)?

    private let viewModel: DuckAiUsageWarningViewModel?
    private let highUsageNotice: UTIFooterHighUsageNoticeSource?
    private let attachmentPrivacyNotice: UTIFooterAttachmentPrivacyNoticeSource?
    private let mapper: UTIFooterMessageMapper
    private let measurement: DuckAiUsageWarningMeasurement
    private let highUsageMeasurement: DuckAiUsageWarningMeasurement
    private let createImagePixelFiring: CreateImagePixelFiring
    private let animator: Animator
    private var isSuppressed = false
    private var isEditing = false
    private var isInputBlocked = false
    private var actedOnMessage: UTIFooterMessage?
    private var modelSwitchNotice: CreateImageModelSwitchNotice?
    private var visibleIDs: Set<UTIFooterItem.ID> = []
    private var retainedMessageIDs: Set<UTIFooterItem.ID>?
    private var applicableIDs: Set<UTIFooterItem.ID> = []
    private var applicableHighUsageModelID: String?
    private var applicableWarning: DuckAiUsageWarning?
    private var isDismissing = false
    private var currentPrivacyKind: AttachmentPrivacyPixel.Kind?
    private(set) var currentMessages: [UTIFooterItem] = []
    var currentMessage: UTIFooterMessage? { currentMessages.first?.message }

    init(viewModel: DuckAiUsageWarningViewModel?,
         highUsageNotice: UTIFooterHighUsageNoticeSource? = nil,
         attachmentPrivacyNotice: UTIFooterAttachmentPrivacyNoticeSource? = nil,
         mapper: UTIFooterMessageMapper = UTIFooterMessageMapper(),
         measurement: DuckAiUsageWarningMeasurement = DuckAiUsageWarningMeasurement(),
         highUsageMeasurement: DuckAiUsageWarningMeasurement = DuckAiUsageWarningMeasurement(),
         createImagePixelFiring: CreateImagePixelFiring,
         animator: Animator? = nil) {
        self.viewModel = viewModel
        self.highUsageNotice = highUsageNotice
        self.attachmentPrivacyNotice = attachmentPrivacyNotice
        self.mapper = mapper
        self.measurement = measurement
        self.highUsageMeasurement = highUsageMeasurement
        self.createImagePixelFiring = createImagePixelFiring
        self.animator = animator ?? Self.springAnimator
    }

    func refresh() {
        viewModel?.refresh()
        highUsageNotice?.refresh()
        applyCurrentState()
    }

    func resetForPoseChange() {
        releaseWaitingMessages()
        measurement.inputSessionEnded()
        highUsageMeasurement.inputSessionEnded()
        viewModel?.clear()
        highUsageNotice?.clear()
        attachmentPrivacyNotice?.clear()
        currentMessages = []
        applicableIDs = []
        applicableHighUsageModelID = nil
        applicableWarning = nil
        visibleIDs = []
        currentPrivacyKind = nil
        updateInputBlock()
        presenter?.clearPendingFooterMessage()
    }

    func setSuppressed(_ suppressed: Bool) {
        guard isSuppressed != suppressed else { return }
        releaseWaitingMessages()
        isSuppressed = suppressed
        if suppressed {
            measurement.inputSessionEnded()
            highUsageMeasurement.inputSessionEnded()
        }
        applyCurrentState()
    }

    func setEditing(_ editing: Bool) {
        guard isEditing != editing else { return }
        releaseWaitingMessages()
        isEditing = editing
        applyCurrentState()
    }

    func showModelSwitchNotice(_ notice: CreateImageModelSwitchNotice) {
        releaseWaitingMessages()
        modelSwitchNotice = notice
        applyCurrentState()
    }

    func clearModelSwitchNotice() {
        guard modelSwitchNotice != nil else { return }
        modelSwitchNotice = nil
        applyCurrentState()
    }


    func dismiss(_ id: UTIFooterItem.ID) {
        guard visibleIDs.contains(id), currentMessages.first(where: { $0.id == id })?.message.isDismissible == true else { return }
        beginDismissal()
        defer { finishDismissal() }
        switch id {
#if DEBUG || ALPHA
        case .termsConsent: return
#endif
        case .outOfUsage, .attachmentPrivacy: return
        case .modelSwitch:
            modelSwitchNotice = nil
            createImagePixelFiring.modelSwitchNoticeDismissed()
        case .usageWarning:
            measurement.warningDismissed()
            viewModel?.dismiss()
        case .highUsage:
            highUsageMeasurement.warningDismissed()
            highUsageNotice?.dismissCurrent()
        }
    }


    func footerVisibilityChanged(visible ids: [UTIFooterItem.ID]) {
        let next = Set(ids).intersection(currentMessages.map(\.id))
        let entered = next.subtracting(visibleIDs)
        visibleIDs = next
        if !next.contains(.attachmentPrivacy) {
            currentPrivacyKind = nil
            attachmentPrivacyNotice?.endDisplay()
        }
        if entered.contains(.attachmentPrivacy), attachmentPrivacyNotice?.recordDisplay() == true {
            currentPrivacyKind = attachmentPrivacyNotice?.kind
            if let currentPrivacyKind { onAttachmentPrivacyEvent?(.shown, currentPrivacyKind) }
        }
        if !next.isDisjoint(with: [.usageWarning, .outOfUsage]), let warning = viewModel?.warning {
            measurement.cardBecameVisible(DuckAiUsageWarningExposure(warning: warning))
        }
        if next.contains(.highUsage), let notice = highUsageNotice?.notice {
            highUsageMeasurement.cardBecameVisible(DuckAiUsageWarningExposure(notice: notice))
        }
        applyCurrentState()
    }

    func recordLinkTapped(_ id: UTIFooterItem.ID = .attachmentPrivacy) {
        guard id == .attachmentPrivacy, visibleIDs.contains(id), let currentPrivacyKind else { return }
        onAttachmentPrivacyEvent?(.learnMoreTapped, currentPrivacyKind)
    }

    func recordPromptSubmitted() {
#if DEBUG || ALPHA
        UTIFooterDebugOverrides.clearTermsPreview()
#endif
        measurement.promptSubmitted()
        highUsageMeasurement.promptSubmitted()
        modelSwitchNotice = nil
        applyCurrentState()
    }

    func userSwitchedModel(from previousModelId: String?, to modelId: String) {
        measurement.modelSwitched()
        highUsageMeasurement.modelSwitched()
        viewModel?.userSwitchedModel(from: previousModelId, to: modelId)
        highUsageNotice?.refresh()
        applyCurrentState()
    }


    func performPrimaryAction(_ id: UTIFooterItem.ID) {
        guard id == .usageWarning || id == .outOfUsage, visibleIDs.contains(id),
              let message = currentMessages.first(where: { $0.id == id })?.message,
              message.primaryAction != nil else { return }
        if id == .usageWarning { beginDismissal() }
        defer {
            if id == .usageWarning {
                finishDismissal()
            } else {
                applyCurrentState()
            }
        }
        if let cta = Self.cta(for: viewModel?.warning?.action) { measurement.ctaTapped(cta) }
        viewModel?.performAction()
        if viewModel?.hasActedOnCurrentNotice == true { actedOnMessage = message }
    }

    private static func cta(for action: DuckAiUsageAction?) -> DuckAiUsageWarningMeasurement.CTA? {
        switch action {
        case .switchToModel, .switchToFreeModel: return .switchModel
        case .tryForFree: return .upsell
        case .startUsingWeeklyLimit, .none: return nil
        }
    }

    private func beginDismissal() {
        retainedMessageIDs = Set(currentMessages.map(\.id))
        isDismissing = true
    }

    private func finishDismissal() {
        applyCurrentState()
        isDismissing = false
    }

    private func releaseWaitingMessages() {
        guard !isDismissing else { return }
        retainedMessageIDs = nil
    }

    private func applyCurrentState() {
        attachmentPrivacyNotice?.refresh()
        updateInputBlock()
        let applicable = applicableMessages()
        let nextIDs = Set(applicable.map(\.id))
        let endedVisibleMessage = !applicableIDs.subtracting(nextIDs).isDisjoint(with: currentMessages.map(\.id))
        let highUsageModelID = highUsageNotice?.notice?.modelId
        let warning = nextIDs.isDisjoint(with: [.usageWarning, .outOfUsage]) ? nil : viewModel?.warning
        let newWarning = warning != nil && (warning?.message != applicableWarning?.message || warning?.window != applicableWarning?.window)
        if !nextIDs.subtracting(applicableIDs).isEmpty || endedVisibleMessage || newWarning ||
            (highUsageModelID != nil && highUsageModelID != applicableHighUsageModelID) {
            releaseWaitingMessages()
        }
        applicableIDs = nextIDs
        applicableHighUsageModelID = highUsageModelID
        applicableWarning = warning
        let eligible = retainedMessageIDs.map { retained in applicable.filter { retained.contains($0.id) } } ?? applicable
        let messages = isSuppressed ? [] : UTIFooterItem.visible(from: eligible, isEditing: isEditing)
        guard messages != currentMessages else { return }
        currentMessages = messages
        visibleIDs.formIntersection(messages.map(\.id))
        if !visibleIDs.contains(.attachmentPrivacy) {
            currentPrivacyKind = nil
            attachmentPrivacyNotice?.endDisplay()
        }
        animator { [weak self] in self?.presenter?.applyFooterMessages(messages) }
    }

    private func updateInputBlock() {
        let blocked = !isSuppressed && !isEditing && viewModel?.warning?.blocksInput == true
        guard blocked != isInputBlocked else { return }
        isInputBlocked = blocked
        onInputBlockChanged?(blocked)
    }

    private func applicableMessages() -> [UTIFooterItem] {
        var items: [UTIFooterItem] = []
#if DEBUG || ALPHA
        if let terms = UTIFooterDebugOverrides.termsMessage, viewModel?.warning?.blocksInput != true {
            items.append(.init(id: .termsConsent, message: terms))
        }
#endif
        if attachmentPrivacyNotice?.isPresented == true, viewModel?.warning?.blocksInput != true {
            items.append(.init(id: .attachmentPrivacy, message: mapper.attachmentPrivacyMessage()))
        }
        if let modelSwitchNotice { items.append(.init(id: .modelSwitch, message: mapper.message(for: modelSwitchNotice))) }
        if let warning = viewModel?.warning {
            let message = mapper.message(for: warning)
            if viewModel?.hasActedOnCurrentNotice != true || message != actedOnMessage {
                items.append(.init(id: warning.blocksInput ? .outOfUsage : .usageWarning, message: message))
            }
        }
        if let notice = highUsageNotice?.notice { items.append(.init(id: .highUsage, message: mapper.message(for: notice))) }
        return items
    }

    static let springAnimator: Animator = { changes in
        guard !UIAccessibility.isReduceMotionEnabled else { return changes() }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
    }
}

// MARK: - Attachment privacy notice

/// Resolves the disclosure from valid attachments and the display cap for the current browsing scope.
@MainActor
final class UTIFooterAttachmentPrivacyNoticeSource {

    enum DisplayScope: Equatable {
        case normal
        case fireTab(Tab?)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.normal, .normal): return true
            case (.fireTab(let lhs), .fireTab(let rhs)): return lhs === rhs
            default: return false
            }
        }
    }

    private let displayScope: () -> DisplayScope
    private let attachmentKind: () -> AttachmentPrivacyPixel.Kind?
    private let isEnabled: () -> Bool
    private let displayStore: UTIAttachmentPrivacyNoticeDisplayStoring
    private var displayedScope: DisplayScope?

    private(set) var isPresented = false
    private(set) var kind: AttachmentPrivacyPixel.Kind?

    init(attachmentKind: @escaping () -> AttachmentPrivacyPixel.Kind?,
         isEnabled: @escaping () -> Bool,
         displayScope: @escaping () -> DisplayScope = { .normal },
         displayStore: UTIAttachmentPrivacyNoticeDisplayStoring = UTIAttachmentPrivacyNoticeDisplayStore()) {
        self.displayScope = displayScope
        self.attachmentKind = attachmentKind
        self.isEnabled = isEnabled
        self.displayStore = displayStore
    }

    func refresh() {
        kind = attachmentKind()
        let enabled = isEnabled()
        let scope = displayScope()
        if !enabled || kind == nil || displayedScope != scope { endDisplay() }
        isPresented = enabled && kind != nil && (displayedScope != nil || count(in: scope) < UTIAttachmentPrivacyNoticeDisplayStore.displayLimit)
    }

    func recordDisplay() -> Bool {
        let scope = displayScope()
        guard isPresented, displayedScope == nil,
              count(in: scope) < UTIAttachmentPrivacyNoticeDisplayStore.displayLimit else { return false }
        switch scope {
        case .normal:
            displayStore.recordDisplay()
        case .fireTab(let tab):
            tab?.attachmentPrivacyNoticeDisplayCount += 1
        }
        displayedScope = scope
        return true
    }

    func endDisplay() {
        displayedScope = nil
    }

    func clear() {
        endDisplay()
        isPresented = false
    }

    private func count(in scope: DisplayScope) -> Int {
        switch scope {
        case .normal: return displayStore.displayCount
        case .fireTab(let tab): return tab?.attachmentPrivacyNoticeDisplayCount ?? 0
        }
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
