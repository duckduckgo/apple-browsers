//
//  MockAIChatBonusMessageHandling.swift
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

import Combine
import Foundation
@testable import AIChat

final class MockAIChatBonusMessageHandling: AIChatBonusMessageHandling {
    var storedRecord: AIChatBonusRecord?
    var error: Error?
    let recordSubject = PassthroughSubject<AIChatBonusRecord, Never>()

    private(set) var claimedCampaignNames: [String] = []
    private(set) var appliedOutcomes: [AIChatBonusRedeemOutcome] = []
    private(set) var dismissCallCount = 0
    private(set) var endCallCount = 0

    var recordPublisher: AnyPublisher<AIChatBonusRecord, Never> {
        recordSubject.eraseToAnyPublisher()
    }

    func record() throws -> AIChatBonusRecord? {
        if let error { throw error }
        return storedRecord
    }

    func claim(campaignName: String) throws -> AIChatBonusRecord {
        claimedCampaignNames.append(campaignName)
        if let error { throw error }
        let record = storedRecord ?? AIChatBonusRecord(campaignName: campaignName, bonusId: AIChatBonusRecordMock.bonusId)
        storedRecord = record
        return record
    }

    func applyRedeemOutcome(_ outcome: AIChatBonusRedeemOutcome) throws {
        appliedOutcomes.append(outcome)
        if let error { throw error }
    }

    func dismiss() throws {
        dismissCallCount += 1
        if let error { throw error }
    }

    func end() throws {
        endCallCount += 1
        if let error { throw error }
    }
}
