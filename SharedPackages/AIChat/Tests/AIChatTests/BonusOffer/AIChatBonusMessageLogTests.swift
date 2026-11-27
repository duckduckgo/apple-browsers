//
//  AIChatBonusMessageLogTests.swift
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

@Suite("AIChatBonus - Message Log Tests")
struct AIChatBonusMessageLogTests {

    // MARK: - Masking

    @Test("Check the Bonus ID in params is masked to its last 4 characters")
    func bonusIdInParamsIsMasked() throws {
        // GIVEN
        let sut = AIChatBonusMessageLog()
        sut.isEnabled = true

        // WHEN
        sut.record(.notification, method: "aiChatBonusRedeemOutcome", params: ["bonusId": "f0785d4c-014f-4b94-bc7a-7af0720cc7e9", "result": "success"])

        // THEN
        let params = try #require(sut.recentEntries.first?.params as? [String: Any])
        #expect(params["bonusId"] as? String == "•••• c7e9")
        #expect(params["result"] as? String == "success")
    }

    @Test("Check the Bonus ID in a nested payload is masked")
    func bonusIdInANestedPayloadIsMasked() throws {
        // GIVEN
        let sut = AIChatBonusMessageLog()
        sut.isEnabled = true
        let payload = AIChatBonusRecordPayload(record: AIChatBonusRecordMock.active, isNewInstall: true, aiChatEnabled: true)

        // WHEN
        sut.record(.push, method: "submitAIChatBonusRecord", body: payload)

        // THEN
        let body = try #require(sut.recentEntries.first?.body as? [String: Any])
        let record = try #require(body["record"] as? [String: Any])
        #expect(record["bonusId"] as? String == AIChatBonusMessageLog.maskedBonusId(AIChatBonusRecordMock.bonusId))
        #expect(record["campaignName"] as? String == AIChatBonusRecordMock.campaignName)
    }

    @Test("Check a Bonus ID of 4 characters or fewer is fully masked", arguments: ["", "abc", "abcd"])
    func shortBonusIdIsFullyMasked(_ bonusId: String) {
        #expect(AIChatBonusMessageLog.maskedBonusId(bonusId) == "••••")
    }
}
