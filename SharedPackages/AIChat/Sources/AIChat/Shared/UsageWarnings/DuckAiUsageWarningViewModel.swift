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

/// Owns the usage-limit message for one Duck.ai input surface: reads the snapshot on activation, resolves
/// it against the rules, and publishes whatever should be on screen.
///
/// There is no UI yet, so the debug log is the observable surface — it reports the resolved decision, or
/// the specific gate that suppressed it.
public final class DuckAiUsageWarningViewModel: ObservableObject {

    @Published public private(set) var warning: DuckAiUsageWarning?

    /// Wired by the platform to its existing model-selection path. This view model decides *what* to
    /// suggest; it never reaches into model selection itself.
    public var onSwitchToSuggestedModel: ((DuckAiCheaperModelSuggestion) -> Void)?

    /// `nil` means the feature is inactive — the flag is off, or this surface has no storage bridge. That
    /// is not the same as an active feature with nothing to show.
    private let limitsProvider: DuckAiUsageLimitsProviding?
    private let tierProvider: () -> AIChatUserTier
    private let isInternalUser: () -> Bool
    private let dismissalStore: DuckAiUsageWarningDismissalStoring
    private let resolver: DuckAiUsageWarningResolver
    private let dateProvider: () -> Date

    /// Kept so `dismiss()` can recover the window's `resetsAt` without a second storage read.
    private var lastReadLimits: DuckAiUsageLimits = .noData

    public init(limitsProvider: DuckAiUsageLimitsProviding?,
                tierProvider: @escaping () -> AIChatUserTier,
                isInternalUser: @escaping () -> Bool,
                dismissalStore: DuckAiUsageWarningDismissalStoring,
                cheaperModelSuggester: DuckAiCheaperModelSuggesting = NullDuckAiCheaperModelSuggester(),
                dateProvider: @escaping () -> Date = Date.init) {
        self.limitsProvider = limitsProvider
        self.tierProvider = tierProvider
        self.isInternalUser = isInternalUser
        self.dismissalStore = dismissalStore
        self.resolver = DuckAiUsageWarningResolver(dismissalStore: dismissalStore,
                                                   cheaperModelSuggester: cheaperModelSuggester)
        self.dateProvider = dateProvider
    }

    /// Synchronous: a lookup in the already-loaded entries blob, so it needs no async treatment.
    public func refresh() {
        guard let limitsProvider else {
            warning = nil
            Logger.aiChat.debug("Duck.ai usage warning: none — reason=featureInactive")
            return
        }
        lastReadLimits = limitsProvider.currentUsageLimits()
        resolveAndPublish()
    }

    /// Records a dismissal at the threshold the user is currently in, so the message stays hidden until
    /// the window resets or they cross the next one.
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

    /// The one-click step down the CTA offers — no picker, no dropdown.
    public func switchToSuggestedModel() {
        guard let suggestion = warning?.cheaperModelSuggestion else { return }

        Logger.aiChat.debug("Duck.ai usage warning CTA taken: model=\(suggestion.modelId, privacy: .public)")
        onSwitchToSuggestedModel?(suggestion)
        resolveAndPublish()
    }

    /// Teardown. Drops the published message without touching persisted dismissals.
    public func clear() {
        warning = nil
        lastReadLimits = .noData
    }

    private func resolveAndPublish() {
        let outcome = resolver.resolve(limits: lastReadLimits,
                                       tier: tierProvider(),
                                       isInternalUser: isInternalUser(),
                                       now: dateProvider())
        switch outcome {
        case .warning(let warning, let cheaperModel):
            self.warning = warning
            log(warning, cheaperModel: cheaperModel)
        case .none(let reason):
            self.warning = nil
            Logger.aiChat.debug("Duck.ai usage warning: none — reason=\(reason.rawValue, privacy: .public)")
        }
    }

    /// Leads with the copy the UI will render, so a native decision can be compared straight across
    /// against the web banner. The diagnostic fields follow, since they are what makes each gate
    /// observable while there is no UI.
    ///
    /// The title carries the rounded percentage and goes out `.public`, unlike the `.private` percentage
    /// this replaced. It is a debug-level log behind an internal-only flag, and `severity` already
    /// narrows the number to a 15-point band — redacting the one line the message is meant to be read
    /// from bought little and cost the whole point of logging it.
    private func log(_ warning: DuckAiUsageWarning, cheaperModel: DuckAiCheaperModelOutcome) {
        let message = warning.messagePreview
        let ctaDiagnosis: String
        switch cheaperModel {
        case .suggestion(let suggestion): ctaDiagnosis = "model=\(suggestion.modelId)"
        case .none(let reason): ctaDiagnosis = "none reason=\(reason.rawValue)"
        }

        Logger.aiChat.debug("""
            Duck.ai usage warning: title="\(message.title, privacy: .public)" \
            subtitle="\(message.subtitle ?? "—", privacy: .public)" \
            button="\(message.button ?? "—", privacy: .public)" \
            dismissible=\(warning.isDismissible, privacy: .public) \
            [window=\(warning.window.rawValue, privacy: .public) \
            kind=\(warning.kind.rawValue, privacy: .public) \
            severity=\(warning.severity.loggingName, privacy: .public) \
            tier=\(self.tierProvider().rawValue, privacy: .public) \
            cta=\(ctaDiagnosis, privacy: .public)]
            """)
    }
}
