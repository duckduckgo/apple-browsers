//
//  AIChatServiceTests.swift
//  DuckDuckGo
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
import AIChat
import AIChatTestingUtilities
@testable import DuckDuckGo

@Suite("AIChatBonus - Service Tests")
@MainActor
struct AIChatServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_792_036_890)
    private static let expiredBoost = AIChatBonusRecord(
        campaignName: "launch",
        bonusId: "8a7b9c1d-2e3f-4a5b-8c6d-7e8f9a0b1c2d",
        terms: AIChatBonusRecord.Terms(multiplier: 2, expiresAt: now.timeIntervalSince1970 - 1)
    )

    private let store = MockAIChatBonusStore()
    private let sut: AIChatService

    init() {
        sut = AIChatService(
            aiChatSettings: MockAIChatSettingsProvider(),
            aiChatBonusService: AIChatBonusService(store: store, now: { Self.now })
        )
    }

    @Test("Check resuming ends an expired boost")
    func resumingEndsAnExpiredBoost() {
        // GIVEN
        store.storedRecord = Self.expiredBoost

        // WHEN
        sut.resume()

        // THEN
        #expect(store.storedRecord == AIChatBonusRecord(campaignName: "launch"))
    }
}
