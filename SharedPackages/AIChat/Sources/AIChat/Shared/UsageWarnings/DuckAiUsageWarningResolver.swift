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

/// Turns a raw usage snapshot into the one message that should be on screen, if any. Pure: every input is
/// a parameter or an injected collaborator, so the whole rule set is unit-testable without a UI.
public struct DuckAiUsageWarningResolver {

    /// Why nothing is shown. Reported so each gate stays observable while there is no UI.
    public enum NoWarningReason: String, Comparable {
        case noData
        case belowVisibilityFloor
        case tierNotEligible
        case dismissedUntilReset

        /// When both windows are rejected, the more specific reason is the more useful one to report.
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

    /// The payload carries no `isBlocked`. The web app clamps `percentUsed` to 0–100 and only reports a
    /// flat 100 once the window is actually blocked, so 100 is the signal.
    private static let blockedPercent: Double = 100

    /// `.internal` is here for completeness but is never produced at runtime — internal users are
    /// identified through `InternalUserDecider`, which arrives separately as `isInternalUser`.
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

        // Filtering happens before the pick, so a dismissed daily correctly lets a live weekly through.
        guard let winner = candidates.max(by: Self.isLowerPriority) else { return .none(reason: rejection) }
        return .warning(winner.warning, cheaperModel: winner.cheaperModel)
    }

    private enum CandidateResult {
        case candidate(Candidate)
        case rejected(NoWarningReason)
    }

    private struct Candidate {
        let warning: DuckAiUsageWarning
        /// The raw, uncapped percentage — the rounded one in `warning` can't break a 99.4 / 99.6 tie.
        let percentUsed: Double
        let cheaperModel: DuckAiCheaperModelOutcome
    }

    /// Whichever limit is closest to biting wins; on a tie, daily. Total, because the two candidates
    /// always come from different windows.
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

        // Gated on the raw value, not the rounded one, so 49.6% never renders as a "50%" message.
        guard isBlocked || percentUsed >= DuckAiUsageWindow.visibilityFloor else {
            return .rejected(.belowVisibilityFloor)
        }

        // Free and unknown tiers only ever see the reached message, and can't dismiss it.
        let canSeeApproachingWarnings = isInternalUser || Self.tiersThatSeeApproachingWarnings.contains(tier)
        guard isBlocked || canSeeApproachingWarnings else { return .rejected(.tierNotEligible) }

        let isDismissible = !isBlocked && canSeeApproachingWarnings
        if isDismissible, isSuppressedByDismissal(window: window, percentUsed: percentUsed, resetsAt: data.resetsAt) {
            return .rejected(.dismissedUntilReset)
        }

        // A reached message has nothing left to head off, so it carries no CTA.
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

    /// A dismissal holds until the window resets or the user crosses the next redisplay threshold.
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
