//
//  DuckAiUsageSnapshotSeed.swift
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

/// Hand-seeded `usageLimits` payloads, one per case native can render — plus the edge cases that are
/// easy to get wrong. Both platforms' debug menus and the decoding tests build from this, so a case
/// a tester can pick always has an asserted decode.
///
/// Not `#if DEBUG`: the app targets build this module in Release too, and gating it would mean the
/// debug menus couldn't see it in the very builds (Alpha, internal) the feature is tested in.
public enum DuckAiUsageSnapshotSeed: String, CaseIterable {

    // Approaching
    case approachingDailyOneModel
    case approachingDailySeveralModels
    case approachingWeekly
    case approachingRetargetOnly
    case approachingNotDismissible

    // Reached
    case freeReached
    case dailyReachedWithBypass
    case dailyReachedWithoutBypass
    case weeklyReachedDegraded
    case weeklyReached

    // Edge cases
    case unknownNoticeID
    case unknownCtaID
    case staleReset
    case legacyWindowsOnly

    /// Grouped the way the debug menus present them.
    public static let approachingSeeds: [Self] = [
        .approachingDailyOneModel, .approachingDailySeveralModels, .approachingWeekly,
        .approachingRetargetOnly, .approachingNotDismissible
    ]

    public static let reachedSeeds: [Self] = [
        .freeReached, .dailyReachedWithBypass, .dailyReachedWithoutBypass,
        .weeklyReachedDegraded, .weeklyReached
    ]

    public static let edgeCaseSeeds: [Self] = [
        .unknownNoticeID, .unknownCtaID, .staleReset, .legacyWindowsOnly
    ]

    public var displayName: String {
        switch self {
        case .approachingDailyOneModel: return "Approaching daily, one cheaper model"
        case .approachingDailySeveralModels: return "Approaching daily, several cheaper models"
        case .approachingWeekly: return "Approaching weekly (90%)"
        case .approachingRetargetOnly: return "Approaching, retarget only (button hidden)"
        case .approachingNotDismissible: return "Approaching, not dismissible"
        case .freeReached: return "Free user, limit reached"
        case .dailyReachedWithBypass: return "Daily reached, bypass available"
        case .dailyReachedWithoutBypass: return "Daily reached, no bypass"
        case .weeklyReachedDegraded: return "Weekly reached, free models left"
        case .weeklyReached: return "Weekly reached"
        case .unknownNoticeID: return "Unknown notice id (renders nothing)"
        case .unknownCtaID: return "Unknown cta id (no button)"
        case .staleReset: return "Reset already passed (renders nothing)"
        case .legacyWindowsOnly: return "Legacy payload, windows only (renders nothing)"
        }
    }

    /// What the tester should expect to see, so a surprise reads as a bug rather than as the seed.
    public var expectation: String {
        switch self {
        case .approachingDailyOneModel: return "\"75% of daily limit\" with a Switch to {model} button"
        case .approachingDailySeveralModels: return "As above, plus the chevron opening the model picker"
        case .approachingWeekly: return "\"90% of weekly limit\", ring at 90 on iOS"
        case .approachingRetargetOnly: return "Message with no button — this picker is already on the cheapest model"
        case .approachingNotDismissible: return "Approaching copy with no close button"
        case .freeReached: return "Reached copy with Try for free / Subscribe (whichever the account qualifies for)"
        case .dailyReachedWithBypass: return "\"Daily limit reached\" with Start using weekly limit; the card clears once tapped"
        case .dailyReachedWithoutBypass: return "\"Daily limit reached\", no button, no close button"
        case .weeklyReachedDegraded: return "\"Advanced AI models limit reached\" with Switch to a Free Model"
        case .weeklyReached: return "\"Weekly usage limit reached\", no button"
        case .unknownNoticeID, .staleReset, .legacyWindowsOnly: return "No message at all"
        case .unknownCtaID: return "Approaching copy with no button"
        }
    }

    /// - Parameters:
    ///   - switchTargets: accessible model ids from the live model list, so the switch CTAs resolve
    ///     to something the picker can actually select. Seeding without them exercises the
    ///     hidden-button path instead.
    ///   - selectedModelId: what the native picker is on, used to key the `byModelId` seeds.
    public func entryValue(now: Date = Date(),
                           switchTargets: [String] = [],
                           selectedModelId: String? = nil) -> String {
        let object = payload(now: now, switchTargets: switchTargets, selectedModelId: selectedModelId)
        // `.sortedKeys` so re-seeding the same case produces the same signature, which is what
        // decides whether an acted-on notice stays suppressed.
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private func payload(now: Date, switchTargets: [String], selectedModelId: String?) -> [String: Any] {
        switch self {
        case .approachingDailyOneModel:
            return [
                "notice": notice(id: "approaching", window: "daily", percentUsed: 75, resetsAt: Self.daily(now)),
                "cta": switchCta(id: "switchToCheaper", modelIds: Array(switchTargets.prefix(1)))
            ]

        case .approachingDailySeveralModels:
            return [
                "notice": notice(id: "approaching", window: "daily", percentUsed: 75, resetsAt: Self.daily(now)),
                "cta": switchCta(id: "switchToCheaper", modelIds: Array(switchTargets.prefix(2)))
            ]

        case .approachingWeekly:
            return [
                "notice": notice(id: "approaching", window: "weekly", percentUsed: 90, resetsAt: Self.weekly(now)),
                "cta": switchCta(id: "switchToCheaper", modelIds: Array(switchTargets.prefix(2)))
            ]

        case .approachingRetargetOnly:
            // The contract's "already on the cheapest model" shape: a retarget table for other
            // models, nothing for this one.
            var byModelId: [String: Any] = [:]
            for target in switchTargets.dropFirst() {
                byModelId[target] = ["modelId": switchTargets[0], "modelIds": [switchTargets[0]]]
            }
            if let selectedModelId { byModelId.removeValue(forKey: selectedModelId) }
            return [
                "notice": notice(id: "approaching", window: "daily", percentUsed: 80, resetsAt: Self.daily(now)),
                "cta": ["id": "switchToCheaper", "byModelId": byModelId]
            ]

        case .approachingNotDismissible:
            return [
                "notice": notice(id: "approaching", window: "daily", percentUsed: 95,
                                 resetsAt: Self.daily(now), dismissible: false),
                "cta": switchCta(id: "switchToCheaper", modelIds: Array(switchTargets.prefix(1)))
            ]

        case .freeReached:
            return [
                "notice": notice(id: "freeReached", window: "daily", percentUsed: 100,
                                 resetsAt: Self.daily(now), reached: true),
                "cta": ["id": "subscribe"]
            ]

        case .dailyReachedWithBypass:
            return [
                "notice": notice(id: "dailyReached", window: "daily", percentUsed: 100,
                                 resetsAt: Self.daily(now), reached: true),
                "cta": [
                    "id": "bypassWeekly",
                    "putEntries": [[
                        "key": "duckai.fixedCostWindowBypassResetAtById",
                        "value": "{\"day\":\"\(Self.iso(Self.daily(now)))\"}"
                    ]]
                ]
            ]

        case .dailyReachedWithoutBypass:
            return [
                "notice": notice(id: "dailyReached", window: "daily", percentUsed: 100,
                                 resetsAt: Self.daily(now), reached: true)
            ]

        case .weeklyReachedDegraded:
            return [
                "notice": notice(id: "weeklyReachedDegraded", window: "weekly", percentUsed: 100,
                                 resetsAt: Self.weekly(now), reached: true),
                "cta": switchCta(id: "switchToFree", modelIds: Array(switchTargets.prefix(2)))
            ]

        case .weeklyReached:
            return [
                "notice": notice(id: "weeklyReached", window: "weekly", percentUsed: 100,
                                 resetsAt: Self.weekly(now), reached: true)
            ]

        case .unknownNoticeID:
            return [
                "notice": notice(id: "somethingWebAddedLater", window: "daily", percentUsed: 100,
                                 resetsAt: Self.daily(now), reached: true),
                "cta": ["id": "subscribe"]
            ]

        case .unknownCtaID:
            return [
                "notice": notice(id: "approaching", window: "daily", percentUsed: 75, resetsAt: Self.daily(now)),
                "cta": ["id": "somethingWebAddedLater", "modelId": switchTargets.first ?? "unknown-model"]
            ]

        case .staleReset:
            return [
                "notice": notice(id: "dailyReached", window: "daily", percentUsed: 100,
                                 resetsAt: now.addingTimeInterval(-60), reached: true)
            ]

        case .legacyWindowsOnly:
            return [
                "daily": ["percentUsed": 100, "resetsAt": Self.iso(Self.daily(now))],
                "weekly": ["percentUsed": 60, "resetsAt": Self.iso(Self.weekly(now))]
            ]
        }
    }

    private func notice(id: String,
                        window: String,
                        percentUsed: Int,
                        resetsAt: Date,
                        reached: Bool = false,
                        dismissible: Bool? = nil) -> [String: Any] {
        [
            "id": id,
            "window": window,
            "percentUsed": percentUsed,
            "resetsAt": Self.iso(resetsAt),
            "reached": reached,
            "dismissible": dismissible ?? !reached
        ]
    }

    private func switchCta(id: String, modelIds: [String]) -> [String: Any] {
        guard let first = modelIds.first else { return ["id": id] }
        return ["id": id, "modelId": first, "modelIds": modelIds]
    }

    // Two different resets, so a message that picked the wrong window's time is visible.
    private static func daily(_ now: Date) -> Date { now.addingTimeInterval(5 * 60 * 60) }
    private static func weekly(_ now: Date) -> Date { now.addingTimeInterval(3 * 24 * 60 * 60) }

    /// Byte-identical to the web app's `Date.toISOString()`.
    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
