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

/// Owns the usage-limit message for one Duck.ai input surface. With no UI yet, the debug log is the
/// observable surface: it reports the resolved decision, or the gate that suppressed it.
public final class DuckAiUsageWarningViewModel: ObservableObject {

    @Published public private(set) var warning: DuckAiUsageWarning?

    /// Wired to the platform's model selection and upsell; this type decides what to offer, never applies it.
    public var onAction: ((DuckAiUsageAction) -> Void)?
    /// The `>` beside the primary action.
    public var onOpenModelPicker: (() -> Void)?

    /// `nil` means inactive (flag off, or no storage bridge), which differs from having nothing to show.
    private let limitsProvider: DuckAiUsageLimitsProviding?
    private let tierProvider: () -> AIChatUserTier
    private let isInternalUser: () -> Bool
    private let dismissalStore: DuckAiUsageWarningDismissalStoring
    private let resolver: DuckAiUsageWarningResolver
    private let isTrialEligible: () -> Bool
    /// Re-read on every refresh, so a surface whose fire state changes at runtime can't go stale.
    private let isFireMode: () -> Bool
    private let dateProvider: () -> Date

    /// Kept so `dismiss()` can recover the window's `resetsAt` without a second storage read.
    private var lastReadLimits: DuckAiUsageLimits = .noData

    public init(limitsProvider: DuckAiUsageLimitsProviding?,
                tierProvider: @escaping () -> AIChatUserTier,
                isInternalUser: @escaping () -> Bool,
                dismissalStore: DuckAiUsageWarningDismissalStoring,
                modelSuggester: DuckAiModelSuggesting = NullDuckAiModelSuggester(),
                isTrialEligible: @escaping () -> Bool = { false },
                isFireMode: @escaping () -> Bool = { false },
                dateProvider: @escaping () -> Date = Date.init) {
        self.limitsProvider = limitsProvider
        self.tierProvider = tierProvider
        self.isInternalUser = isInternalUser
        self.dismissalStore = dismissalStore
        self.resolver = DuckAiUsageWarningResolver(dismissalStore: dismissalStore,
                                                   modelSuggester: modelSuggester)
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
        guard let limitsProvider else {
            warning = nil
            Logger.aiChat.debug("Duck.ai usage warning: none — reason=featureInactive")
            return
        }
        lastReadLimits = limitsProvider.currentUsageLimits()
        resolveAndPublish()
    }

    /// Holds until the window resets or the user crosses the next redisplay threshold.
    public func dismiss() {
        guard let warning, warning.isDismissible, let data = lastReadLimits.window(warning.window) else { return }

        let window = warning.window
        let threshold = window.redisplayThreshold(forPercentUsed: data.percentUsed)
        dismissalStore.setDismissal(DuckAiUsageWarningDismissal(resetsAt: data.resetsAt, threshold: threshold),
                                    for: window)
        Logger.aiChat.debug("""
            Duck.ai usage warning dismissed: window=\(window.rawValue, privacy: .public) \
            threshold=\(threshold, privacy: .public)
            """)
        resolveAndPublish()
    }

    public func performAction() {
        guard let action = warning?.action else { return }

        Logger.aiChat.debug("Duck.ai usage warning CTA taken: \(action.buttonTitle, privacy: .public)")
        onAction?(action)
        resolveAndPublish()
    }

    public func openModelPicker() {
        guard warning?.offersModelPicker == true else { return }

        Logger.aiChat.debug("Duck.ai usage warning model picker opened")
        onOpenModelPicker?()
    }

    /// Teardown: drops the message without recording a dismissal.
    public func clear() {
        warning = nil
        lastReadLimits = .noData
    }

    private func resolveAndPublish() {
        let outcome = resolver.resolve(limits: lastReadLimits,
                                       tier: tierProvider(),
                                       isInternalUser: isInternalUser(),
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
            message=\(warning.message.rawValue, privacy: .public) \
            severity=\(warning.severity.loggingName, privacy: .public) \
            tier=\(self.tierProvider().rawValue, privacy: .public) \
            cta=\(ctaDiagnosis, privacy: .public)]
            """)
    }
}
