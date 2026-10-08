//
//  AIChatBonusRecordTests.swift
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
import Testing
@testable import AIChat

@Suite("AIChatBonus - Record Tests")
struct AIChatBonusRecordTests {

    private static let terms = AIChatBonusRecord.Terms(multiplier: 2, expiresAt: 1_790_000_000)

    // MARK: - Invariant

    @available(iOS 16, macOS 13, *)
    @Test("Check record that satisfies invariant is valid", .timeLimit(.minutes(1)), arguments: [
        AIChatBonusRecord(),
        AIChatBonusRecord(dismissed: true),
        AIChatBonusRecord(campaignName: "test-campaign"),
        AIChatBonusRecord(campaignName: "test-campaign", bonusId: "ABC123"),
        AIChatBonusRecord(campaignName: "test-campaign", bonusId: "ABC123", terms: terms),
        AIChatBonusRecord(campaignName: "test-campaign", bonusId: "ABC123", dismissed: true, terms: terms, lastRedeemAttemptAt: 1)
    ])
    func recordsThatKeepTheInvariantAreValid(_ record: AIChatBonusRecord) {
        #expect(!record.breaksInvariant)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check record that does not satisfy the invariant is not valid", .timeLimit(.minutes(1)), arguments: [
        AIChatBonusRecord(bonusId: "id"),
        AIChatBonusRecord(terms: terms),
        AIChatBonusRecord(campaignName: "launch", terms: terms),
        AIChatBonusRecord(bonusId: "id", terms: terms)
    ])
    func recordsThatBreakTheInvariantAreInvalid(_ record: AIChatBonusRecord) {
        #expect(record.breaksInvariant)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check record with an empty identifier is not valid", .timeLimit(.minutes(1)), arguments: [
        AIChatBonusRecord(campaignName: ""),
        AIChatBonusRecord(campaignName: "", bonusId: "ABC123"),
        AIChatBonusRecord(campaignName: "test-campaign", bonusId: ""),
        AIChatBonusRecord(campaignName: "test-campaign", bonusId: "", terms: terms)
    ])
    func recordsWithAnEmptyIdentifierAreInvalid(_ record: AIChatBonusRecord) {
        #expect(record.breaksInvariant)
    }

    // MARK: - Terms

    @available(iOS 16, macOS 13, *)
    @Test("Check milliseconds are decoded and seconds are exposed to client", .timeLimit(.minutes(1)))
    func termsDecodeExpiryFromMillisecondsAndExposeSeconds() throws {
        // GIVEN
        let json = Data(#"{"multiplier":2,"expiresAt":1790000000123}"#.utf8)

        // WHEN
        let result = try JSONDecoder().decode(AIChatBonusRecord.Terms.self, from: json)

        // THEN
        #expect(result.expiresAt == 1_790_000_000.123)
        #expect(result == AIChatBonusRecord.Terms(multiplier: 2, expiresAt: 1_790_000_000.123))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check encodes same milliseconds that were decoded", .timeLimit(.minutes(1)))
    func termsRoundTripTheExpiryMillisecondsUnchanged() throws {
        // GIVEN
        let json = Data(#"{"multiplier":2,"expiresAt":1790000000123.5}"#.utf8)
        let decoded = try JSONDecoder().decode(AIChatBonusRecord.Terms.self, from: json)

        // WHEN
        let result = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])

        // THEN
        #expect(result["expiresAt"] as? Double == 1_790_000_000_123.5)
    }

    // MARK: - Payload

    @available(iOS 16, macOS 13, *)
    @Test("Check nil record is encoded", .timeLimit(.minutes(1)))
    func payloadEncodesAMissingRecordAsNull() throws {
        // GIVEN
        let payload = AIChatBonusRecordPayload(record: nil, isNewInstall: true, aiChatEnabled: false)

        // WHEN
        let result = try jsonObject(payload)

        // THEN
        #expect(result["record"] is NSNull)
        #expect(result["isNewInstall"] as? Bool == true)
        #expect(result["aiChatEnabled"] as? Bool == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check encoding works", .timeLimit(.minutes(1)))
    func payloadEncodesAFullRecord() throws {
        // GIVEN
        let record = AIChatBonusRecord(
            campaignName: "launch",
            bonusId: "8a7b9c1d-2e3f-4a5b-8c6d-7e8f9a0b1c2d",
            dismissed: true,
            terms: AIChatBonusRecord.Terms(multiplier: 2.5, expiresAt: 1_790_000_000),
            lastRedeemAttemptAt: 1_780_000_000_000
        )
        let payload = AIChatBonusRecordPayload(record: record, isNewInstall: false, aiChatEnabled: true)

        // WHEN
        let result = try #require(try jsonObject(payload)["record"] as? [String: Any])

        // THEN
        #expect(result["campaignName"] as? String == "launch")
        #expect(result["bonusId"] as? String == "8a7b9c1d-2e3f-4a5b-8c6d-7e8f9a0b1c2d")
        #expect(result["dismissed"] as? Bool == true)
        let resultTerms = try #require(result["terms"] as? [String: Any])
        #expect(resultTerms["multiplier"] as? Double == 2.5)
        #expect(resultTerms["expiresAt"] as? Int == 1_790_000_000_000)
        #expect(result["lastRedeemAttemptAt"] as? Int == 1_780_000_000_000)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check nil fields are omitted from Record", .timeLimit(.minutes(1)))
    func payloadOmitsUnsetRecordFields() throws {
        // GIVEN
        let payload = AIChatBonusRecordPayload(
            record: AIChatBonusRecord(dismissed: true),
            isNewInstall: true,
            aiChatEnabled: true
        )

        // WHEN
        let result = try #require(try jsonObject(payload)["record"] as? [String: Any])

        // THEN
        #expect(Set(result.keys) == ["dismissed"])
    }
}

// MARK: - Helpers

private extension AIChatBonusRecordTests {

    func jsonObject(_ payload: AIChatBonusRecordPayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

}
