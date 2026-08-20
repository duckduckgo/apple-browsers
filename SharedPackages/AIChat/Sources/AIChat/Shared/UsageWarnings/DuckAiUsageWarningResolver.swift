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
        case warning(DuckAiUsageWarning, cheaperModel: DuckAiCheaperModelOutcome)
        case none(reason: NoWarningReason)
    }

    /// The payload carries no `isBlocked`; web reports a flat 100 only once the window is blocked.
    private static let blockedPercent: Double = 100

    /// `.internal` never occurs at runtime; internal users arrive separately as `isInternalUser`.
    private static let tiersThatSeeApproachingWarnings: Set<AIChatUserTier> = [.plus, .pro, .internal]

    private let dismissalStore: DuckAiUsageWarningDismissalStoring
    private let cheaperModelSuggester: DuckAiCheaperModelSuggesting

    public init(dismissalStore: DuckAiUsageWarningDismissalStoring,
                cheaperModelSuggester: DuckAiCheaperModelSuggesting = NullDuckAiCheaperModelSuggester()) {
        self.dismissalStore = dismissalStore
        self.cheaperModelSuggester = cheaperModelSuggester
    }

    public func resolve(limits: DuckAiUsageLimits,
                        tier: AIChatUserTier,
                        isInternalUser: Bool,
                        now: Date) -> Outcome {
        var candidates: [Candidate] = []
        var rejection = NoWarningReason.noData

        for window in DuckAiUsageWindow.allCases {
            switch candidate(for: window, limits: limits, tier: tier, isInternalUser: isInternalUser, now: now) {
            case .candidate(let candidate):
                candidates.append(candidate)
            case .rejected(let reason):
                rejection = max(rejection, reason)
            }
        }

        // Filtering before the pick is what lets a live weekly through a dismissed daily.
        guard let winner = candidates.max(by: Self.isLowerPriority) else { return .none(reason: rejection) }
        return .warning(winner.warning, cheaperModel: winner.cheaperModel)
    }

    private enum CandidateResult {
        case candidate(Candidate)
        case rejected(NoWarningReason)
    }

    private struct Candidate {
        let warning: DuckAiUsageWarning
        /// Uncapped, because the rounded one in `warning` can't break a 99.4 / 99.6 tie.
        let percentUsed: Double
        let cheaperModel: DuckAiCheaperModelOutcome
    }

    /// Whichever limit is closest to biting wins; on a tie, daily.
    private static func isLowerPriority(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.warning.severity != rhs.warning.severity { return lhs.warning.severity < rhs.warning.severity }
        if lhs.percentUsed != rhs.percentUsed { return lhs.percentUsed < rhs.percentUsed }
        return lhs.warning.window == .weekly && rhs.warning.window == .daily
    }

    private func candidate(for window: DuckAiUsageWindow,
                           limits: DuckAiUsageLimits,
                           tier: AIChatUserTier,
                           isInternalUser: Bool,
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

        // Nothing left to head off once blocked.
        let cheaperModel = isBlocked ? .none(reason: .notApplicable) : cheaperModelSuggester.suggestion()

        let warning = DuckAiUsageWarning(
            window: window,
            kind: isBlocked ? .reached : .approaching,
            severity: isBlocked ? .reached : (window.severity(forPercentUsed: percentUsed) ?? .info),
            percent: isBlocked ? 100 : min(99, Int(percentUsed.rounded())),
            resetsIn: .from(now: now, resetsAt: data.resetsAt),
            isDismissible: isDismissible,
            cheaperModelSuggestion: cheaperModel.suggestion
        )

        return .candidate(Candidate(warning: warning, percentUsed: percentUsed, cheaperModel: cheaperModel))
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
