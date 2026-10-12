//
//  AIChatBonusHandlerTests.swift
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
import Security
import Testing
@testable import AIChat

@Suite("AIChatBonus - Handler Tests")
struct AIChatBonusHandlerTests {
    private let service = MockAIChatBonusMessageHandling()
    private let factsProvider = MockAIChatBonusFactsProvider()
    private let sut: AIChatBonusHandler

    init() {
        sut = AIChatBonusHandler(service: service, factsProvider: factsProvider)
    }

    // MARK: - getAIChatBonusRecord

    @Test("Check getAIChatBonusRecord replies with the stored record and the facts")
    func recordRepliesWithRecordAndFacts() {
        // GIVEN
        service.storedRecord = AIChatBonusRecordMock.active
        factsProvider.isNewInstall = false
        factsProvider.isAIChatEnabled = false

        // WHEN
        let result = sut.getAIChatBonusRecord()

        // THEN
        #expect(result == AIChatBonusRecordPayload(record: AIChatBonusRecordMock.active, isNewInstall: false, aiChatEnabled: false))
    }

    @Test("Check getAIChatBonusRecord replies with a null record when the device has none")
    func recordRepliesWithNullRecordWhenNoneIsStored() {
        // GIVEN
        factsProvider.isNewInstall = true
        factsProvider.isAIChatEnabled = true

        // WHEN
        let result = sut.getAIChatBonusRecord()

        // THEN
        #expect(result == AIChatBonusRecordPayload(record: nil, isNewInstall: true, aiChatEnabled: true))
    }

    @Test("Check getAIChatBonusRecord replies with nothing when the record can't be read")
    func recordRepliesWithNothingWhenReadFails() {
        // GIVEN
        service.error = AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)

        // WHEN
        let result = sut.getAIChatBonusRecord()

        // THEN
        #expect(result == nil)
    }

    // MARK: - getAIChatNewBonusRecord

    @Test("Check getAIChatNewBonusRecord claims the campaign and replies with the record and the facts")
    func newRecordClaimsTheCampaign() throws {
        // WHEN
        let result = sut.getAIChatNewBonusRecord(params: try Self.params(#"{ "campaignName": "launch" }"#))

        // THEN
        #expect(service.claimedCampaignNames == ["launch"])
        #expect(result == AIChatBonusRecordPayload(record: AIChatBonusRecordMock.pending, isNewInstall: true, aiChatEnabled: true))
    }

    @Test("Check getAIChatNewBonusRecord replies with nothing when the claim can't be stored")
    func newRecordRepliesWithNothingWhenClaimFails() throws {
        // GIVEN
        service.error = AIChatBonusStoreError.writeFailed(errSecNotAvailable)

        // WHEN
        let result = sut.getAIChatNewBonusRecord(params: try Self.params(#"{ "campaignName": "launch" }"#))

        // THEN
        #expect(result == nil)
    }

    @Test(
        "Check getAIChatNewBonusRecord drops invalid params without claiming",
        arguments: [
            #"{}"#,
            #"{ "campaignName": 1 }"#,
            #"{ "campaignName": null }"#,
            #"{ "campaignName": "" }"#
        ]
    )
    func newRecordDropsInvalidParams(json: String) throws {
        // WHEN
        let payload = sut.getAIChatNewBonusRecord(params: try Self.params(json))

        // THEN
        #expect(payload == nil)
        #expect(service.claimedCampaignNames.isEmpty)
    }

    // MARK: - aiChatBonusRedeemOutcome

    @Test("Check a success outcome is applied with the granted terms")
    func successOutcomeIsAppliedWithTerms() throws {
        // GIVEN
        let json = """
        {
            "bonusId": "\(AIChatBonusRecordMock.bonusId)",
            "result": "success",
            "grant": { "campaignName": "launch", "multiplier": 2, "expiresAt": 1790000000000 }
        }
        """

        // WHEN
        sut.aiChatBonusRedeemOutcome(params: try Self.params(json))

        // THEN
        #expect(service.appliedOutcomes == [.success(bonusId: AIChatBonusRecordMock.bonusId, terms: AIChatBonusRecordMock.terms)])
    }

    @Test(
        "Check a failure outcome is applied with whether it's definitive",
        arguments: [true, false]
    )
    func failureOutcomeIsApplied(isDefinitive: Bool) throws {
        // GIVEN
        let json = """
        { "bonusId": "\(AIChatBonusRecordMock.bonusId)", "result": "failure", "reason": "ended", "definitive": \(isDefinitive) }
        """

        // WHEN
        sut.aiChatBonusRedeemOutcome(params: try Self.params(json))

        // THEN
        #expect(service.appliedOutcomes == [.failure(bonusId: AIChatBonusRecordMock.bonusId, isDefinitive: isDefinitive)])
    }

    @Test(
        "Check a failure outcome is applied whatever its reason",
        arguments: [#""reason": "ended","#, #""reason": "ineligible","#, #""reason": "newReason","#, ""]
    )
    func failureOutcomeIsAppliedWhateverItsReason(reason: String) throws {
        // GIVEN
        let json = """
        { "bonusId": "\(AIChatBonusRecordMock.bonusId)", "result": "failure", \(reason) "definitive": false }
        """

        // WHEN
        sut.aiChatBonusRedeemOutcome(params: try Self.params(json))

        // THEN
        #expect(service.appliedOutcomes.count == 1)
    }

    @Test(
        "Check an invalid redeem outcome is dropped",
        arguments: [
            // No Bonus ID
            #"{ "result": "failure", "reason": "ended", "definitive": true }"#,
            // Unknown result
            #"{ "bonusId": "id", "result": "pending" }"#,
            // Success without a grant
            #"{ "bonusId": "id", "result": "success" }"#,
            // Grant without a campaign
            #"{ "bonusId": "id", "result": "success", "grant": { "multiplier": 2, "expiresAt": 1790000000000 } }"#,
            // Grant without an expiry
            #"{ "bonusId": "id", "result": "success", "grant": { "campaignName": "launch", "multiplier": 2 } }"#,
            // Grant with a string multiplier
            #"{ "bonusId": "id", "result": "success", "grant": { "campaignName": "launch", "multiplier": "2", "expiresAt": 1790000000000 } }"#,
            // Failure without definitive
            #"{ "bonusId": "id", "result": "failure", "reason": "ended" }"#,
            // Definitive that isn't a Bool
            #"{ "bonusId": "id", "result": "failure", "reason": "ended", "definitive": "yes" }"#
        ]
    )
    func invalidRedeemOutcomeIsDropped(json: String) throws {
        // WHEN
        sut.aiChatBonusRedeemOutcome(params: try Self.params(json))

        // THEN
        #expect(service.appliedOutcomes.isEmpty)
    }

    // MARK: - aiChatBonusDismiss

    @Test("Check aiChatBonusDismiss dismisses the offer")
    func dismissDismissesTheOffer() {
        // WHEN
        sut.aiChatBonusDismiss()

        // THEN
        #expect(service.dismissCallCount == 1)
    }

    // MARK: - aiChatBonusEnd

    @Test("Check aiChatBonusEnd ends the boost")
    func endEndsTheBoost() {
        // WHEN
        sut.aiChatBonusEnd()

        // THEN
        #expect(service.endCallCount == 1)
    }

    // MARK: - recordPayloadPublisher

    @Test("Check a record change publishes the payload with the facts")
    func recordChangePublishesThePayload() {
        // GIVEN
        let published = PublishedValues(sut.recordPayloadPublisher)

        // WHEN
        service.recordSubject.send(AIChatBonusRecordMock.active)

        // THEN
        #expect(published.values == [AIChatBonusRecordPayload(record: AIChatBonusRecordMock.active, isNewInstall: true, aiChatEnabled: true)])
    }

    @Test("Check a deleted record publishes a payload with a null record")
    func deletedRecordPublishesANullRecord() {
        // GIVEN
        let published = PublishedValues(sut.recordPayloadPublisher)

        // WHEN
        service.recordSubject.send(nil)

        // THEN
        #expect(published.values == [AIChatBonusRecordPayload(record: nil, isNewInstall: true, aiChatEnabled: true)])
    }

    @Test("Check the published payload carries the facts at the time of the change")
    func publishedPayloadReadsTheFactsWhenTheRecordChanges() {
        // GIVEN
        let published = PublishedValues(sut.recordPayloadPublisher)
        factsProvider.isNewInstall = false
        factsProvider.isAIChatEnabled = false

        // WHEN
        service.recordSubject.send(AIChatBonusRecordMock.ended)

        // THEN
        #expect(published.values == [AIChatBonusRecordPayload(record: AIChatBonusRecordMock.ended, isNewInstall: false, aiChatEnabled: false)])
    }

    // MARK: - Params that aren't JSON objects

    @Test("Check params that aren't a JSON object are dropped")
    func nonObjectParamsAreDropped() {
        // WHEN
        let payload = sut.getAIChatNewBonusRecord(params: "launch")
        sut.aiChatBonusRedeemOutcome(params: "id")

        // THEN
        #expect(payload == nil)
        #expect(service.claimedCampaignNames.isEmpty)
        #expect(service.appliedOutcomes.isEmpty)
    }
}

// MARK: - Helpers

private extension AIChatBonusHandlerTests {

    /// The params as the bridge hands them over: a JSON object parsed by `JSONSerialization`.
    static func params(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }
}
