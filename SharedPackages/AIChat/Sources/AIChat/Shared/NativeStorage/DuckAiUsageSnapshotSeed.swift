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

/// Shared by both debug menus and the decoding tests, so a case a tester can pick always has an
/// asserted decode. Not `#if DEBUG`: Alpha and internal builds are where this gets tested.
public enum DuckAiUsageSnapshotSeed: String, CaseIterable {

    // Free
    case freeDailyReached

    // Paid
    case approachingDaily
    case dailyReachedWithBypass
    case approachingWeekly
    case weeklyReachedDegraded
    case weeklyReached

    /// Grouped as the debug menus present them: what a free account sees, and what a paid one does.
    public static let freeSeeds: [Self] = [.freeDailyReached]

    public static let paidSeeds: [Self] = [
        .approachingDaily, .dailyReachedWithBypass, .approachingWeekly, .weeklyReachedDegraded, .weeklyReached
    ]

    public var displayName: String {
        switch self {
        case .freeDailyReached: return "Daily limit reached"
        case .approachingDaily: return "Approaching daily limit (90%)"
        case .dailyReachedWithBypass: return "Daily limit reached"
        case .approachingWeekly: return "Approaching weekly limit (90%)"
        case .weeklyReachedDegraded: return "Weekly limit reached, free models left"
        case .weeklyReached: return "Weekly limit reached"
        }
    }

    /// So a surprise reads as a bug rather than as the seed.
    public var expectation: String {
        switch self {
        case .freeDailyReached:
            return "\"Daily limit reached\" with Try for free / Subscribe (whichever the account qualifies for)"
        case .approachingDaily:
            return "\"90% of daily limit\" with Switch to {model} and the chevron"
        case .dailyReachedWithBypass:
            return "\"Daily limit reached\" with Start using weekly limit; the card clears once tapped"
        case .approachingWeekly:
            return "\"90% of weekly limit\" with Switch to {model} and the chevron"
        case .weeklyReachedDegraded:
            return "\"Advanced AI models limit reached\" with Switch to a Free Model"
        case .weeklyReached:
            return "\"Weekly usage limit reached\", no button"
        }
    }

    /// `switchTargets` come from the live model list so the CTAs resolve to something selectable;
    /// without them the seeds exercise the hidden-button path instead.
    public func entryValue(now: Date = Date(),
                           switchTargets: [String] = [],
                           selectedModelId: String? = nil) -> String {
        let object = payload(now: now, switchTargets: switchTargets, selectedModelId: selectedModelId)
        // `.sortedKeys` so re-seeding produces the same signature, which decides suppression.
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private func payload(now: Date, switchTargets: [String], selectedModelId: String?) -> [String: Any] {
        let targets = switchTargets.filter { $0 != selectedModelId }

        switch self {
        case .freeDailyReached:
            return [
                "notice": notice(id: "freeReached", window: "daily", percentUsed: 100,
                                 resetsAt: Self.daily(now), reached: true),
                "cta": ["id": "subscribe"]
            ]

        case .approachingDaily:
            return [
                "notice": notice(id: "approaching", window: "daily", percentUsed: 90, resetsAt: Self.daily(now)),
                "cta": switchCta(id: "switchToCheaper", modelIds: Array(targets.prefix(2)))
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

        case .approachingWeekly:
            return [
                "notice": notice(id: "approaching", window: "weekly", percentUsed: 90, resetsAt: Self.weekly(now)),
                "cta": switchCta(id: "switchToCheaper", modelIds: Array(targets.prefix(2)))
            ]

        case .weeklyReachedDegraded:
            return [
                "notice": notice(id: "weeklyReachedDegraded", window: "weekly", percentUsed: 100,
                                 resetsAt: Self.weekly(now), reached: true),
                "cta": switchCta(id: "switchToFree", modelIds: Array(targets.prefix(2)))
            ]

        case .weeklyReached:
            return [
                "notice": notice(id: "weeklyReached", window: "weekly", percentUsed: 100,
                                 resetsAt: Self.weekly(now), reached: true)
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

    // Two different resets, so a message using the wrong window's time is visible.
    private static func daily(_ now: Date) -> Date { now.addingTimeInterval(5 * 60 * 60) }
    private static func weekly(_ now: Date) -> Date { now.addingTimeInterval(3 * 24 * 60 * 60) }

    /// Byte-identical to web's `Date.toISOString()`, which is what it is compared against.
    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
