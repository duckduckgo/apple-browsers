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

/// Owns the usage-limit message for one Duck.ai input surface.
public final class DuckAiUsageWarningViewModel: ObservableObject {

    @Published public private(set) var warning: DuckAiUsageWarning?

    /// This type decides what to offer; the platform applies it.
    public var onAction: ((DuckAiUsageAction) -> Void)?
    /// The `>` beside the primary action.
    public var onOpenModelPicker: (() -> Void)?

    /// `nil` means inactive (flag off, no bridge), which differs from having nothing to show.
    private let snapshotProvider: DuckAiUsageSnapshotProviding?
    private let dismissalStore: DuckAiUsageWarningDismissalStoring
    private let resolver: DuckAiUsageWarningResolver
    private let isTrialEligible: () -> Bool
    /// Re-read on every refresh, so a surface whose fire state changes at runtime can't go stale.
    private let isFireMode: () -> Bool
    private let dateProvider: () -> Date

    /// So `dismiss()` and `performAction()` record against the notice they were shown for.
    private var lastReadSnapshot: DuckAiUsageSnapshot = .noData

    public init(snapshotProvider: DuckAiUsageSnapshotProviding?,
                dismissalStore: DuckAiUsageWarningDismissalStoring,
                modelSuggester: DuckAiModelSuggesting = NullDuckAiModelSuggester(),
                isTrialEligible: @escaping () -> Bool = { false },
                isFireMode: @escaping () -> Bool = { false },
                dateProvider: @escaping () -> Date = Date.init) {
        self.snapshotProvider = snapshotProvider
        self.dismissalStore = dismissalStore
        self.resolver = DuckAiUsageWarningResolver(dismissalStore: dismissalStore,
                                                   modelSuggester: modelSuggester)
        self.isTrialEligible = isTrialEligible
        self.isFireMode = isFireMode
        self.dateProvider = dateProvider
    }

    /// The notice the snapshot carries, whether or not it is being shown. Acting on a message
    /// retires the message, not the limit behind it, and a caller may still have to respect it.
    public var activeNoticeID: DuckAiUsageNotice.ID? { lastReadSnapshot.notice?.id }

    /// Synchronous: a lookup in the already-loaded entries blob.
    public func refresh() {
        // An isolated session must not surface the regular session's usage.
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
        Logger.aiChat.debug("Duck.ai usage warning dismissed: notice=\(notice.id.rawValue, privacy: .public)")
        resolveAndPublish()
    }

    public func performAction() {
        guard let action = warning?.action, let notice = lastReadSnapshot.notice else { return }

        Logger.aiChat.debug("Duck.ai usage warning CTA taken: \(action.buttonTitle, privacy: .public)")
        onAction?(action)

        // After the sink has run, and before the re-resolve that has to see it.
        if action.suppressesNoticeUntilSnapshotChanges, let signature = lastReadSnapshot.signature {
            dismissalStore.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: notice.id.rawValue,
                                                                           signature: signature))
        }
        resolveAndPublish()
    }

    /// The `>` opens a picker that applies the model itself, so the message is stood down from there
    /// too — otherwise the chevron leaves it up while the button beside it hides it.
    public func modelSwitchedFromMessage() {
        guard warning?.offersModelPicker == true else { return }
        recordActedOnCurrentSnapshot()
    }

    /// A switch made in the normal model picker, which is the CTA by another route. Call it *before*
    /// applying the switch: the suggestion retargets to the new model as soon as it lands. Only the
    /// model the message offers counts — any other pick hasn't taken its advice.
    @discardableResult
    public func modelSwitchedToSuggestion(_ modelId: String) -> Bool {
        guard warning?.action?.suggestedModelId == modelId else { return false }
        return recordActedOnCurrentSnapshot()
    }

    /// A switch from the bar's own picker settles the message only if web offered that model as a step
    /// down from the one the user was on. Read off the CTA: iOS re-resolves before reporting the switch.
    public func userSwitchedModel(from previousModelId: String?, to modelId: String) {
        guard let cta = lastReadSnapshot.cta, cta.id.asksForModelSwitch,
              cta.target(forSelectedModelId: previousModelId).candidateModelIds.contains(modelId) else { return }

        Logger.aiChat.debug("Duck.ai usage warning stood down: user switched model")
        recordActedOnCurrentSnapshot()
    }

    @discardableResult
    private func recordActedOnCurrentSnapshot() -> Bool {
        guard let notice = lastReadSnapshot.notice,
              let signature = lastReadSnapshot.signature else { return false }

        dismissalStore.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: notice.id.rawValue,
                                                                       signature: signature))
        resolveAndPublish()
        return true
    }

    public func openModelPicker() {
        guard warning?.offersModelPicker == true else { return }

        Logger.aiChat.debug("Duck.ai usage warning model picker opened")
        onOpenModelPicker?()
    }

    /// Teardown: drops the message without recording a dismissal.
    public func clear() {
        warning = nil
        lastReadSnapshot = .noData
    }

    private func resolveAndPublish() {
        let outcome = resolver.resolve(snapshot: lastReadSnapshot,
                                       isTrialEligible: isTrialEligible(),
                                       now: dateProvider())
        switch outcome {
        case .warning(let warning, let modelSuggestion):
            self.warning = warning
            log(warning, modelSuggestion: modelSuggestion)
        case .none(let reason):
            self.warning = nil
            Logger.aiChat.debug("Duck.ai usage warning: none — reason=\(reason.rawValue, privacy: .public)")
        }
    }

    /// `.public` because redacting the line the message is read from would defeat logging it.
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
