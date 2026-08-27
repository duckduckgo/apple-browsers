//
//  DuckAiUsageSnapshotTests.swift
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

import XCTest
@testable import AIChat

final class DuckAiUsageSnapshotTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z
    private let resetsAt = "2025-08-12T17:00:00.000Z"

    // MARK: - Notice

    func testDecodesEveryNoticeID() {
        let expected: [String: DuckAiUsageNotice.ID] = [
            "approaching": .approaching,
            "freeReached": .freeReached,
            "dailyReached": .dailyReached,
            "weeklyReachedDegraded": .weeklyReachedDegraded,
            "weeklyReached": .weeklyReached
        ]

        for (raw, id) in expected {
            let snapshot = make("""
                {"notice":{"id":"\(raw)","window":"weekly","percentUsed":100,"resetsAt":"\(resetsAt)","reached":true}}
                """)
            XCTAssertEqual(snapshot.notice?.id, id, raw)
        }
    }

    func testDecodesNoticeFields() {
        let snapshot = make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":75,"resetsAt":"\(resetsAt)",
            "reached":false,"dismissible":true}}
            """)

        XCTAssertEqual(snapshot.notice?.window, .daily)
        XCTAssertEqual(snapshot.notice?.percentUsed, 75)
        XCTAssertEqual(snapshot.notice?.resetsAt, now.addingTimeInterval(5 * 3600))
        XCTAssertEqual(snapshot.notice?.reached, false)
        XCTAssertEqual(snapshot.notice?.dismissible, true)
    }

    /// A message web adds later must render nothing rather than the nearest copy we happen to have.
    func testWhenTheNoticeIDIsUnknownThenThereIsNoNotice() {
        let snapshot = make("""
            {"notice":{"id":"somethingNew","window":"daily","percentUsed":100,"resetsAt":"\(resetsAt)","reached":true},
            "cta":{"id":"subscribe"}}
            """)

        XCTAssertNil(snapshot.notice)
        XCTAssertNil(snapshot.cta)
    }

    func testWhenTheWindowIsUnknownThenThereIsNoNotice() {
        XCTAssertNil(make("""
            {"notice":{"id":"approaching","window":"sixHours","percentUsed":75,"resetsAt":"\(resetsAt)"}}
            """).notice)
    }

    /// It would otherwise warn on after the limit had lifted.
    func testWhenTheResetHasPassedThenThereIsNoNotice() {
        XCTAssertNil(make("""
            {"notice":{"id":"dailyReached","window":"daily","percentUsed":100,
            "resetsAt":"2025-08-12T11:00:00.000Z","reached":true}}
            """).notice)
    }

    func testWhenTheResetIsExactlyNowThenThereIsNoNotice() {
        XCTAssertNil(make("""
            {"notice":{"id":"dailyReached","window":"daily","percentUsed":100,
            "resetsAt":"2025-08-12T12:00:00.000Z","reached":true}}
            """).notice)
    }

    func testAcceptsAResetWithoutFractionalSeconds() {
        XCTAssertEqual(make("""
            {"notice":{"id":"dailyReached","window":"daily","percentUsed":100,
            "resetsAt":"2025-08-12T17:00:00Z","reached":true}}
            """).notice?.resetsAt, now.addingTimeInterval(5 * 3600))
    }

    /// The ids already say whether this is a hard limit, so the flags are only a confirmation.
    func testWhenTheFlagsAreMissingThenTheyFollowTheNoticeID() {
        let reached = make("""
            {"notice":{"id":"weeklyReached","window":"weekly","percentUsed":100,"resetsAt":"\(resetsAt)"}}
            """).notice
        XCTAssertEqual(reached?.reached, true)
        XCTAssertEqual(reached?.dismissible, false)

        let approaching = make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":75,"resetsAt":"\(resetsAt)"}}
            """).notice
        XCTAssertEqual(approaching?.reached, false)
        XCTAssertEqual(approaching?.dismissible, true)
    }

    /// Trusted as sent: web owns this, and a sticky approaching message is a shape it may want.
    func testDismissibleIsTakenFromThePayloadNotDerived() {
        XCTAssertEqual(make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":75,"resetsAt":"\(resetsAt)",
            "reached":false,"dismissible":false}}
            """).notice?.dismissible, false)
    }

    /// "0% of daily limit" is worse than no message.
    func testWhenAnApproachingNoticeHasNoPercentageThenThereIsNoNotice() {
        XCTAssertNil(make("""
            {"notice":{"id":"approaching","window":"daily","resetsAt":"\(resetsAt)"}}
            """).notice)
    }

    func testWhenAReachedNoticeHasNoPercentageThenItReadsAsFull() {
        XCTAssertEqual(make("""
            {"notice":{"id":"weeklyReached","window":"weekly","resetsAt":"\(resetsAt)","reached":true}}
            """).notice?.percentUsed, 100)
    }

    func testPercentageIsRoundedAndClamped() {
        XCTAssertEqual(percent("75.4"), 75)
        XCTAssertEqual(percent("75.6"), 76)
        XCTAssertEqual(percent("-5"), 0)
        XCTAssertEqual(percent("140"), 100)
    }

    /// `true` would otherwise bridge to `1`.
    func testWhenThePercentageIsABooleanThenTheApproachingNoticeIsDropped() {
        XCTAssertNil(make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":true,"resetsAt":"\(resetsAt)"}}
            """).notice)
    }

    // MARK: - CTA

    func testDecodesEveryCtaID() {
        let expected: [String: DuckAiUsageCta.ID] = [
            "bypassWeekly": .bypassWeekly,
            "switchToCheaper": .switchToCheaper,
            "switchToFree": .switchToFree,
            "subscribe": .subscribe
        ]

        for (raw, id) in expected {
            XCTAssertEqual(snapshot(cta: "{\"id\":\"\(raw)\"}").cta?.id, id, raw)
        }
    }

    func testDecodesTheTopLevelTarget() {
        let cta = snapshot(cta: """
            {"id":"switchToCheaper","modelId":"haiku","modelIds":["haiku","mistral-small"]}
            """).cta

        XCTAssertEqual(cta?.target.modelId, "haiku")
        XCTAssertEqual(cta?.target.modelIds, ["haiku", "mistral-small"])
        XCTAssertEqual(cta?.target.candidateModelIds, ["haiku", "mistral-small"])
    }

    func testDecodesTheRetargetTable() {
        let cta = snapshot(cta: """
            {"id":"switchToCheaper","byModelId":{"sonnet":{"modelId":"haiku","modelIds":["haiku"]}}}
            """).cta

        XCTAssertEqual(cta?.target(forSelectedModelId: "sonnet"),
                       DuckAiUsageCta.Target(modelId: "haiku", modelIds: ["haiku"]))
    }

    /// The retarget-only shape from the contract: web is on the cheapest model, other picker models
    /// still have somewhere to go.
    func testWhenThereIsNoRetargetForTheSelectedModelThenTheTopLevelTargetIsUsed() {
        let cta = snapshot(cta: """
            {"id":"switchToCheaper","modelId":"haiku","byModelId":{"sonnet":{"modelId":"mistral-small"}}}
            """).cta

        XCTAssertEqual(cta?.target(forSelectedModelId: "opus").modelId, "haiku")
        XCTAssertEqual(cta?.target(forSelectedModelId: nil).modelId, "haiku")
        XCTAssertEqual(cta?.target(forSelectedModelId: "sonnet").modelId, "mistral-small")
    }

    func testWhenTheCtaIDIsUnknownThenTheNoticeSurvivesWithoutIt() {
        let snapshot = make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":75,"resetsAt":"\(resetsAt)"},
            "cta":{"id":"somethingNew","modelId":"haiku"}}
            """)

        XCTAssertNotNil(snapshot.notice)
        XCTAssertNil(snapshot.cta)
    }

    func testNonStringModelIdsAreDropped() {
        XCTAssertEqual(snapshot(cta: """
            {"id":"switchToCheaper","modelIds":["haiku",7,null,"mistral-small"]}
            """).cta?.target.modelIds, ["haiku", "mistral-small"])
    }

    // MARK: - putEntries

    func testDecodesPutEntriesAsAList() {
        XCTAssertEqual(snapshot(cta: """
            {"id":"bypassWeekly","putEntries":[{"key":"duckai.a","value":"{\\"day\\":\\"x\\"}"}]}
            """).cta?.putEntries,
                       [DuckAiNativeStorageEntry(key: "duckai.a", value: "{\"day\":\"x\"}")])
    }

    /// Accepted defensively, in case web sends the object form instead.
    func testDecodesPutEntriesAsAnObject() {
        XCTAssertEqual(snapshot(cta: """
            {"id":"bypassWeekly","putEntries":{"duckai.b":"2","duckai.a":"1"}}
            """).cta?.putEntries,
                       [DuckAiNativeStorageEntry(key: "duckai.a", value: "1"),
                        DuckAiNativeStorageEntry(key: "duckai.b", value: "2")])
    }

    /// These go straight into the entries blob the web app parses, so a non-string is dropped rather
    /// than coerced into one.
    func testMalformedPutEntriesAreDropped() {
        XCTAssertEqual(snapshot(cta: """
            {"id":"bypassWeekly","putEntries":[{"key":"duckai.a","value":7},{"value":"orphan"},
            {"key":"","value":"1"},{"key":"duckai.b","value":"2"}]}
            """).cta?.putEntries,
                       [DuckAiNativeStorageEntry(key: "duckai.b", value: "2")])
    }

    // MARK: - Payload handling

    /// Per the contract these are written for older clients only; reading them would resurrect the
    /// percent-derived guessing this payload exists to replace.
    func testWindowsOnlyPayloadRendersNothing() {
        let snapshot = make("""
            {"daily":{"percentUsed":100,"resetsAt":"\(resetsAt)"},
            "weekly":{"percentUsed":60,"resetsAt":"\(resetsAt)"}}
            """)

        XCTAssertFalse(snapshot.hasNotice)
        XCTAssertNil(snapshot.cta)
    }

    func testACtaWithoutANoticeIsDropped() {
        XCTAssertNil(make("{\"cta\":{\"id\":\"subscribe\"}}").cta)
    }

    func testUnknownFieldsAreIgnored() {
        let snapshot = make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":75,"resetsAt":"\(resetsAt)",
            "somethingNew":{"nested":true}},"somethingElse":42}
            """)

        XCTAssertEqual(snapshot.notice?.percentUsed, 75)
    }

    func testMalformedValuesDegradeToNoData() {
        XCTAssertEqual(DuckAiUsageSnapshot.make(entryValue: nil, now: now), .noData)
        XCTAssertEqual(DuckAiUsageSnapshot.make(entryValue: "", now: now), .noData)
        XCTAssertEqual(DuckAiUsageSnapshot.make(entryValue: "not json", now: now), .noData)
        XCTAssertEqual(DuckAiUsageSnapshot.make(entryValue: "[1,2,3]", now: now), .noData)
        XCTAssertEqual(DuckAiUsageSnapshot.make(entryValue: 42, now: now), .noData)
    }

    /// The web app stores a JSON string; a dictionary is only accepted in case that ever changes.
    func testAcceptsADictionaryValue() {
        let value: [String: Any] = [
            "notice": ["id": "weeklyReached", "window": "weekly", "percentUsed": 100,
                       "resetsAt": resetsAt, "reached": true]
        ]

        XCTAssertEqual(DuckAiUsageSnapshot.make(entryValue: value, now: now).notice?.id, .weeklyReached)
    }

    // MARK: - Signature

    func testTheSignatureIsTheStoredValue() {
        let json = """
            {"notice":{"id":"weeklyReached","window":"weekly","percentUsed":100,"resetsAt":"\(resetsAt)","reached":true}}
            """

        XCTAssertEqual(make(json).signature, json)
    }

    /// What decides whether a notice the user already acted on stays suppressed.
    func testTheSignatureIsStableAcrossReadsAndChangesWithThePayload() {
        let json = DuckAiUsageSnapshotSeed.dailyReachedWithBypass.entryValue(now: now)

        XCTAssertEqual(make(json).signature, make(json).signature)
        XCTAssertNotEqual(make(json).signature,
                          make(DuckAiUsageSnapshotSeed.weeklyReached.entryValue(now: now)).signature)
    }

    func testAnUnparseableValueHasNoSignature() {
        XCTAssertNil(DuckAiUsageSnapshot.make(entryValue: "not json", now: now).signature)
    }

    // MARK: - Seeds

    /// Every seed a tester can pick from the debug menus, asserted here so the menu and the decoder
    /// can't disagree about what a case means.
    func testEverySeedDecodesToWhatItsNameSays() {
        let targets = ["haiku", "mistral-small"]

        for seed in DuckAiUsageSnapshotSeed.allCases {
            let snapshot = make(seed.entryValue(now: now, switchTargets: targets, selectedModelId: "sonnet"))

            switch seed {
            case .freeDailyReached:
                XCTAssertEqual(snapshot.notice?.id, .freeReached)
                XCTAssertEqual(snapshot.notice?.window, .daily)
                XCTAssertEqual(snapshot.cta?.id, .subscribe)
                XCTAssertEqual(snapshot.notice?.dismissible, false)
            case .approachingDaily:
                XCTAssertEqual(snapshot.notice?.id, .approaching)
                XCTAssertEqual(snapshot.notice?.window, .daily)
                XCTAssertEqual(snapshot.notice?.percentUsed, 90)
                XCTAssertEqual(snapshot.cta?.id, .switchToCheaper)
                XCTAssertEqual(snapshot.cta?.target.candidateModelIds, targets)
            case .dailyReachedWithBypass:
                XCTAssertEqual(snapshot.notice?.id, .dailyReached)
                XCTAssertEqual(snapshot.cta?.id, .bypassWeekly)
                XCTAssertEqual(snapshot.cta?.putEntries.count, 1)
                XCTAssertEqual(snapshot.cta?.putEntries.first?.key, "duckai.fixedCostWindowBypassResetAtById")
            case .approachingWeekly:
                XCTAssertEqual(snapshot.notice?.id, .approaching)
                XCTAssertEqual(snapshot.notice?.window, .weekly)
                XCTAssertEqual(snapshot.notice?.percentUsed, 90)
                XCTAssertEqual(snapshot.cta?.id, .switchToCheaper)
            case .weeklyReachedDegraded:
                XCTAssertEqual(snapshot.notice?.id, .weeklyReachedDegraded)
                XCTAssertEqual(snapshot.notice?.window, .weekly)
                XCTAssertEqual(snapshot.cta?.id, .switchToFree)
            case .weeklyReached:
                XCTAssertEqual(snapshot.notice?.id, .weeklyReached)
                XCTAssertNil(snapshot.cta)
                XCTAssertEqual(snapshot.notice?.dismissible, false)
            }
        }
    }

    /// The seeds' own reset times differ per window, so a message that picked the wrong window's
    /// time is visible in the card rather than plausible.
    func testTheSeedsResetTimesFollowTheirWindow() {
        let daily = make(DuckAiUsageSnapshotSeed.approachingDaily.entryValue(now: now)).notice
        let weekly = make(DuckAiUsageSnapshotSeed.approachingWeekly.entryValue(now: now)).notice

        XCTAssertEqual(daily?.resetsAt, now.addingTimeInterval(5 * 3600))
        XCTAssertEqual(weekly?.resetsAt, now.addingTimeInterval(3 * 24 * 3600))
    }

    /// A seed must never offer the model the picker is already on.
    func testSwitchSeedsExcludeTheSelectedModel() {
        let snapshot = make(DuckAiUsageSnapshotSeed.approachingDaily.entryValue(now: now,
                                                                                switchTargets: ["haiku", "sonnet"],
                                                                                selectedModelId: "sonnet"))

        XCTAssertEqual(snapshot.cta?.target.candidateModelIds, ["haiku"])
    }

    /// Seeded without a live model list, the switch seeds render as the hidden-button case rather
    /// than offering a model that isn't in the picker.
    func testSwitchSeedsWithoutTargetsCarryNoModels() {
        let snapshot = make(DuckAiUsageSnapshotSeed.approachingDaily.entryValue(now: now))

        XCTAssertEqual(snapshot.notice?.id, .approaching)
        XCTAssertTrue(snapshot.cta?.target.isEmpty ?? false)
    }

    // MARK: - Helpers

    private func make(_ json: String) -> DuckAiUsageSnapshot {
        DuckAiUsageSnapshot.make(entryValue: json, now: now)
    }

    private func snapshot(cta: String) -> DuckAiUsageSnapshot {
        make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":75,"resetsAt":"\(resetsAt)"},"cta":\(cta)}
            """)
    }

    private func percent(_ raw: String) -> Int? {
        make("""
            {"notice":{"id":"approaching","window":"daily","percentUsed":\(raw),"resetsAt":"\(resetsAt)"}}
            """).notice?.percentUsed
    }
}

/// The debug menus build their sections from these groups, so a seed left out of all three would be
/// unreachable from the UI while still looking present in the enum.
final class DuckAiUsageSnapshotSeedGroupingTests: XCTestCase {

    func testEverySeedAppearsInExactlyOneMenuSection() {
        let grouped = DuckAiUsageSnapshotSeed.freeSeeds + DuckAiUsageSnapshotSeed.paidSeeds

        XCTAssertEqual(Set(grouped), Set(DuckAiUsageSnapshotSeed.allCases))
        XCTAssertEqual(grouped.count, DuckAiUsageSnapshotSeed.allCases.count)
    }
}
