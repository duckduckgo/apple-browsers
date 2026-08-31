//
//  DuckAiUsageWarningResolver.swift
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

import Foundation

/// Deliberately thin: web owns which message this is and what it offers, so native decides only
/// whether the user has already dealt with it, and whether an offered model works on this surface.
public struct DuckAiUsageWarningResolver {

    /// Reported so each gate stays observable in the log.
    public enum NoWarningReason: String {
        case noNotice
        case dismissedUntilReset
        case actedOnThisSnapshot
    }

    public enum Outcome {
        case warning(DuckAiUsageWarning, modelSuggestion: DuckAiModelSuggestionOutcome)
        case none(reason: NoWarningReason)
    }

    private let dismissalStore: DuckAiUsageWarningDismissalStoring
    private let modelSuggester: DuckAiModelSuggesting

    public init(dismissalStore: DuckAiUsageWarningDismissalStoring,
                modelSuggester: DuckAiModelSuggesting = NullDuckAiModelSuggester()) {
        self.dismissalStore = dismissalStore
        self.modelSuggester = modelSuggester
    }

    public func resolve(snapshot: DuckAiUsageSnapshot,
                        isTrialEligible: Bool,
                        now: Date) -> Outcome {
        guard let notice = snapshot.notice else { return .none(reason: .noNotice) }

        if let dismissal = dismissalStore.dismissal(), dismissal.applies(to: notice) {
            return .none(reason: .dismissedUntilReset)
        }

        // The payload it was resolved from still says the limit is hit, so re-showing it would read
        // as the button having done nothing.
        if let acted = dismissalStore.actedSnapshot(), acted.applies(to: notice, signature: snapshot.signature) {
            return .none(reason: .actedOnThisSnapshot)
        }

        let suggestion = snapshot.cta.map(modelSuggester.resolve) ?? .none(reason: .notApplicable)
        let action = self.action(for: snapshot.cta, suggestion: suggestion, isTrialEligible: isTrialEligible)

        let warning = DuckAiUsageWarning(
            window: notice.window,
            message: notice.id,
            severity: .from(percentUsed: notice.percentUsed, reached: notice.reached),
            percent: notice.percentUsed,
            resetsIn: .from(now: now, resetsAt: notice.resetsAt),
            isDismissible: notice.dismissible,
            action: action,
            offersModelPicker: action?.offersModelPicker ?? false
        )
        return .warning(warning, modelSuggestion: suggestion)
    }

    /// `nil` hides the button and keeps the notice — the payload's own "already on the cheapest
    /// model" case, and what happens when nothing web offered fits this draft.
    private func action(for cta: DuckAiUsageCta?,
                        suggestion: DuckAiModelSuggestionOutcome,
                        isTrialEligible: Bool) -> DuckAiUsageAction? {
        guard let cta else { return nil }

        switch cta.id {
        case .switchToCheaper:
            return suggestion.suggestion.map(DuckAiUsageAction.switchToModel)
        case .switchToFree:
            return suggestion.suggestion.map(DuckAiUsageAction.switchToFreeModel)
        case .subscribe:
            return .tryForFree(isTrialEligible: isTrialEligible)
        case .bypassWeekly:
            // Nothing to write means nothing would happen on tap.
            return cta.putEntries.isEmpty ? nil : .startUsingWeeklyLimit(entries: cta.putEntries)
        }
    }
}
