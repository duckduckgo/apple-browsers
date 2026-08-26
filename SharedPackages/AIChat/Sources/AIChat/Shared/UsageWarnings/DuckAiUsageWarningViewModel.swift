//
//  DuckAiUsageWarningViewModel.swift
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

import Combine
import Foundation
import os.log

/// Owns the usage-limit message for one Duck.ai input surface: reads the snapshot web published,
/// publishes the message to render, and reports what the user did with it.
public final class DuckAiUsageWarningViewModel: ObservableObject {

    @Published public private(set) var warning: DuckAiUsageWarning?

    /// Wired to the platform's model selection, upsell and entry writes; this type decides what to
    /// offer, never applies it.
    public var onAction: ((DuckAiUsageAction) -> Void)?
    /// The `>` beside the primary action.
    public var onOpenModelPicker: (() -> Void)?

    /// `nil` means inactive (flag off, or no storage bridge), which differs from having nothing to show.
    private let snapshotProvider: DuckAiUsageSnapshotProviding?
    private let dismissalStore: DuckAiUsageWarningDismissalStoring
    private let resolver: DuckAiUsageWarningResolver
    private let pixelFiring: DuckAiUsageWarningPixelFiring
    private let isTrialEligible: () -> Bool
    /// Re-read on every refresh, so a surface whose fire state changes at runtime can't go stale.
    private let isFireMode: () -> Bool
    private let dateProvider: () -> Date

    /// Kept so `dismiss()` and `performAction()` can record against the notice they were shown for,
    /// without a second storage read.
    private var lastReadSnapshot: DuckAiUsageSnapshot = .noData
    /// So re-resolving on every input activation doesn't report the same message as newly shown.
    private var lastReportedNotice: DuckAiUsageWarningDismissal?

    public init(snapshotProvider: DuckAiUsageSnapshotProviding?,
                dismissalStore: DuckAiUsageWarningDismissalStoring,
                modelSuggester: DuckAiModelSuggesting = NullDuckAiModelSuggester(),
                pixelFiring: DuckAiUsageWarningPixelFiring = NullDuckAiUsageWarningPixelFiring(),
                isTrialEligible: @escaping () -> Bool = { false },
                isFireMode: @escaping () -> Bool = { false },
                dateProvider: @escaping () -> Date = Date.init) {
        self.snapshotProvider = snapshotProvider
        self.dismissalStore = dismissalStore
        self.resolver = DuckAiUsageWarningResolver(dismissalStore: dismissalStore,
                                                   modelSuggester: modelSuggester)
        self.pixelFiring = pixelFiring
        self.isTrialEligible = isTrialEligible
        self.isFireMode = isFireMode
        self.dateProvider = dateProvider
    }

    /// Synchronous: a lookup in the already-loaded entries blob.
    public func refresh() {
        // Fire windows and fire tabs are out of scope: an isolated session must not surface the
        // regular session's usage, and has no usage of its own worth warning about.
        guard !isFireMode() else {
            warning = nil
            Logger.aiChat.debug("Duck.ai usage warning: none — reason=fireMode")
            return
        }
        guard let snapshotProvider else {
            warning = nil
            Logger.aiChat.debug("Duck.ai usage warning: none — reason=featureInactive")
            return
        }
        lastReadSnapshot = snapshotProvider.currentSnapshot()
        resolveAndPublish()
    }

    /// Holds until web publishes a snapshot for the next reset period.
    public func dismiss() {
        guard let warning, warning.isDismissible, let notice = lastReadSnapshot.notice else { return }

        dismissalStore.setDismissal(DuckAiUsageWarningDismissal(notice: notice))
        pixelFiring.fire(.noticeDismissed(noticeID: notice.id))
        Logger.aiChat.debug("Duck.ai usage warning dismissed: notice=\(notice.id.rawValue, privacy: .public)")
        resolveAndPublish()
    }

    public func performAction() {
        guard let action = warning?.action, let notice = lastReadSnapshot.notice else { return }

        Logger.aiChat.debug("Duck.ai usage warning CTA taken: \(action.buttonTitle, privacy: .public)")
        pixelFiring.fire(.ctaTapped(ctaID: action.ctaID, noticeID: notice.id))
        onAction?(action)

        // Recorded after the sink has run, and before the re-resolve that has to see it.
        if action.suppressesNoticeUntilSnapshotChanges, let signature = lastReadSnapshot.signature {
            dismissalStore.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: notice.id.rawValue,
                                                                           signature: signature))
        }
        resolveAndPublish()
    }

    public func openModelPicker() {
        guard warning?.offersModelPicker == true else { return }

        Logger.aiChat.debug("Duck.ai usage warning model picker opened")
        onOpenModelPicker?()
    }

    /// Teardown: drops the message without recording anything.
    public func clear() {
        warning = nil
        lastReadSnapshot = .noData
        lastReportedNotice = nil
    }

    private func resolveAndPublish() {
        let outcome = resolver.resolve(snapshot: lastReadSnapshot,
                                       isTrialEligible: isTrialEligible(),
                                       now: dateProvider())
        switch outcome {
        case .warning(let warning, let modelSuggestion):
            self.warning = warning
            reportShownIfNew(warning)
            log(warning, modelSuggestion: modelSuggestion)
        case .none(let reason):
            self.warning = nil
            lastReportedNotice = nil
            Logger.aiChat.debug("Duck.ai usage warning: none — reason=\(reason.rawValue, privacy: .public)")
        }
    }

    /// One impression per notice per reset period per surface, rather than one per input activation:
    /// the message is re-resolved every time the user opens the input, and counting those would say
    /// more about how often they open it than about the message.
    private func reportShownIfNew(_ warning: DuckAiUsageWarning) {
        guard let notice = lastReadSnapshot.notice else { return }

        let shown = DuckAiUsageWarningDismissal(notice: notice)
        guard shown != lastReportedNotice else { return }
        lastReportedNotice = shown
        pixelFiring.fire(.noticeShown(noticeID: notice.id, window: warning.window))
    }

    /// The title carries the percentage and goes out `.public`: this is debug-level behind an
    /// internal-only flag, and redacting the line the message is read from would defeat logging it.
    private func log(_ warning: DuckAiUsageWarning, modelSuggestion: DuckAiModelSuggestionOutcome) {
        let message = warning.messagePreview
        let ctaDiagnosis: String
        switch modelSuggestion {
        case .suggestion(let suggestion): ctaDiagnosis = "model=\(suggestion.modelId)"
        case .none(let reason): ctaDiagnosis = "none reason=\(reason.rawValue)"
        }

        Logger.aiChat.debug("""
            Duck.ai usage warning: title="\(message.title, privacy: .public)" \
            button="\(message.button ?? "—", privacy: .public)" \
            picker=\(warning.offersModelPicker, privacy: .public) \
            dismissible=\(warning.isDismissible, privacy: .public) \
            [window=\(warning.window.rawValue, privacy: .public) \
            notice=\(warning.message.rawValue, privacy: .public) \
            cta=\(ctaDiagnosis, privacy: .public)]
            """)
    }
}
