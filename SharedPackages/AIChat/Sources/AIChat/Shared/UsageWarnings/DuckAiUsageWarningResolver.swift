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

/// Pure: every input is a parameter or an injected collaborator, so the rule set is testable without UI.
public struct DuckAiUsageWarningResolver {

    /// Reported so each gate stays observable while there is no UI.
    public enum NoWarningReason: String, Comparable {
        case noData
        case belowVisibilityFloor
        case tierNotEligible
        case dismissedUntilReset

        /// When both windows are rejected, the more specific reason is the more useful to report.
        private var specificity: Int {
            switch self {
            case .noData: return 0
            case .belowVisibilityFloor: return 1
            case .tierNotEligible: return 2
            case .dismissedUntilReset: return 3
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.specificity < rhs.specificity }
    }

    public enum Outcome {
        case warning(DuckAiUsageWarning, modelSuggestion: DuckAiModelSuggestionOutcome)
        case none(reason: NoWarningReason)
    }

    /// The payload carries no `isBlocked`; web reports a flat 100 only once the window is blocked.
    private static let blockedPercent: Double = 100

    /// `.internal` never occurs at runtime; internal users arrive separately as `isInternalUser`.
    private static let tiersThatSeeApproachingWarnings: Set<AIChatUserTier> = [.plus, .pro, .internal]

    private let dismissalStore: DuckAiUsageWarningDismissalStoring
    private let modelSuggester: DuckAiModelSuggesting

    public init(dismissalStore: DuckAiUsageWarningDismissalStoring,
                modelSuggester: DuckAiModelSuggesting = NullDuckAiModelSuggester()) {
        self.dismissalStore = dismissalStore
        self.modelSuggester = modelSuggester
    }

    /// `advancedModelsWindow` names the window carrying the advanced-model allowance, which distinguishes
    /// "Advanced AI models limit reached" from "Weekly usage limit reached". Absent from the payload today.
    public func resolve(limits: DuckAiUsageLimits,
                        tier: AIChatUserTier,
                        isInternalUser: Bool,
                        isTrialEligible: Bool,
                        advancedModelsWindow: DuckAiUsageWindow? = nil,
                        now: Date) -> Outcome {
        var candidates: [Candidate] = []
        var rejection = NoWarningReason.noData

        for window in DuckAiUsageWindow.allCases {
            switch candidate(for: window,
                             limits: limits,
                             tier: tier,
                             isInternalUser: isInternalUser,
                             isTrialEligible: isTrialEligible,
                             advancedModelsWindow: advancedModelsWindow,
                             now: now) {
            case .candidate(let candidate):
                candidates.append(candidate)
            case .rejected(let reason):
                rejection = max(rejection, reason)
            }
        }

        // Filtering before the pick is what lets a live weekly through a dismissed daily.
        guard let winner = candidates.max(by: Self.isLowerPriority) else { return .none(reason: rejection) }
        return .warning(winner.warning, modelSuggestion: winner.modelSuggestion)
    }

    private enum CandidateResult {
        case candidate(Candidate)
        case rejected(NoWarningReason)
    }

    private struct Candidate {
        let warning: DuckAiUsageWarning
        /// Uncapped, because the rounded one in `warning` can't break a 99.4 / 99.6 tie.
        let percentUsed: Double
        let modelSuggestion: DuckAiModelSuggestionOutcome
    }

    /// Whichever limit is closest to biting wins. When both are blocked, weekly: a daily reset won't
    /// unblock anything. Otherwise daily breaks the tie.
    private static func isLowerPriority(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.warning.severity != rhs.warning.severity { return lhs.warning.severity < rhs.warning.severity }
        if lhs.warning.message.isReached && rhs.warning.message.isReached {
            return lhs.warning.window == .daily && rhs.warning.window == .weekly
        }
        if lhs.percentUsed != rhs.percentUsed { return lhs.percentUsed < rhs.percentUsed }
        return lhs.warning.window == .weekly && rhs.warning.window == .daily
    }

    private func candidate(for window: DuckAiUsageWindow,
                           limits: DuckAiUsageLimits,
                           tier: AIChatUserTier,
                           isInternalUser: Bool,
                           isTrialEligible: Bool,
                           advancedModelsWindow: DuckAiUsageWindow?,
                           now: Date) -> CandidateResult {
        guard let data = limits.window(window) else { return .rejected(.noData) }

        let percentUsed = data.percentUsed
        let isBlocked = percentUsed >= Self.blockedPercent

        // Raw, not rounded, so 49.6% never renders as a "50%" message.
        guard isBlocked || percentUsed >= DuckAiUsageWindow.visibilityFloor else {
            return .rejected(.belowVisibilityFloor)
        }

        let canSeeApproachingWarnings = isInternalUser || Self.tiersThatSeeApproachingWarnings.contains(tier)
        guard isBlocked || canSeeApproachingWarnings else { return .rejected(.tierNotEligible) }

        let isDismissible = !isBlocked && canSeeApproachingWarnings
        if isDismissible, isSuppressedByDismissal(window: window, percentUsed: percentUsed, resetsAt: data.resetsAt) {
            return .rejected(.dismissedUntilReset)
        }

        let message = Self.message(for: window, isBlocked: isBlocked, advancedModelsWindow: advancedModelsWindow)
        let suggestion = modelSuggestion(for: message)
        let action = self.action(for: message,
                                 suggestion: suggestion,
                                 isPaid: canSeeApproachingWarnings,
                                 isTrialEligible: isTrialEligible,
                                 weeklyHasRoom: Self.hasRoom(limits.weekly))

        let warning = DuckAiUsageWarning(
            window: window,
            message: message,
            severity: isBlocked ? .reached : (window.severity(forPercentUsed: percentUsed) ?? .info),
            percent: isBlocked ? 100 : min(99, Int(percentUsed.rounded())),
            resetsIn: .from(now: now, resetsAt: data.resetsAt),
            isDismissible: isDismissible,
            action: action,
            offersModelPicker: message == .approaching && action != nil
        )

        return .candidate(Candidate(warning: warning, percentUsed: percentUsed, modelSuggestion: suggestion))
    }

    private static func message(for window: DuckAiUsageWindow,
                                isBlocked: Bool,
                                advancedModelsWindow: DuckAiUsageWindow?) -> DuckAiUsageMessage {
        guard isBlocked else { return .approaching }
        if window == .daily { return .dailyLimitReached }
        // Defaults to the plain weekly copy until the payload says which allowance was spent.
        return advancedModelsWindow == window ? .advancedModelsLimitReached : .weeklyLimitReached
    }

    private func modelSuggestion(for message: DuckAiUsageMessage) -> DuckAiModelSuggestionOutcome {
        switch message {
        case .approaching: return modelSuggester.cheaperModel()
        case .advancedModelsLimitReached: return modelSuggester.freeModel()
        case .dailyLimitReached, .weeklyLimitReached: return .none(reason: .notApplicable)
        }
    }

    private func action(for message: DuckAiUsageMessage,
                        suggestion: DuckAiModelSuggestionOutcome,
                        isPaid: Bool,
                        isTrialEligible: Bool,
                        weeklyHasRoom: Bool) -> DuckAiUsageAction? {
        // Free tier only ever sees a reached message, and the only thing to offer is the upsell.
        guard isPaid else { return .tryForFree(isTrialEligible: isTrialEligible) }

        switch message {
        case .approaching:
            return suggestion.suggestion.map(DuckAiUsageAction.switchToModel)
        case .advancedModelsLimitReached:
            return suggestion.suggestion.map(DuckAiUsageAction.switchToFreeModel)
        case .dailyLimitReached:
            // Only worth offering when the weekly allowance can actually absorb more.
            return weeklyHasRoom ? .startUsingWeeklyLimit : nil
        case .weeklyLimitReached:
            return nil
        }
    }

    private static func hasRoom(_ window: DuckAiUsageLimitWindow?) -> Bool {
        guard let window else { return false }
        return window.percentUsed < blockedPercent
    }

    private func isSuppressedByDismissal(window: DuckAiUsageWindow, percentUsed: Double, resetsAt: Date) -> Bool {
        guard let dismissal = dismissalStore.dismissal(for: window), dismissal.applies(to: resetsAt) else {
            return false
        }
        return window.redisplayThreshold(forPercentUsed: percentUsed) <= dismissal.threshold
    }
}

extension DuckAiUsageLimits {

    func window(_ window: DuckAiUsageWindow) -> DuckAiUsageLimitWindow? {
        switch window {
        case .daily: return daily
        case .weekly: return weekly
        }
    }
}
