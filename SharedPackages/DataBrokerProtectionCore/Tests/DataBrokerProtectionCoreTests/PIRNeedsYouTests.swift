//
//  PIRNeedsYouTests.swift
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

#if os(macOS) && DEBUG
import XCTest
@testable import DataBrokerProtectionCore

final class PIRNeedsYouTests: XCTestCase {

    private func optOut(broker: Int64, record: Int64?, url: String = "peoplefinders.com", name: String = "PeopleFinders") -> PIRAssistedOptOut {
        PIRAssistedOptOut(brokerId: broker, profileQueryId: 1, extractedProfileId: record, brokerName: name, brokerURL: url, recordName: nil)
    }

    func testWhenRecordsShareABroker_thenTheyFormOneRowWithTheirCount() {
        let items = PIRNeedsYou.items(pending: [optOut(broker: 1, record: 10), optOut(broker: 1, record: 11)], running: [])

        XCTAssertEqual(items, [DBPUINeedsYouItem(id: "optOut-1-1-10", brokerName: "PeopleFinders", brokerUrl: "peoplefinders.com",
                                                 kind: .optOut, recordCount: 2, state: .waiting)])
    }

    func testWhenABrokerHasAHeldScanAndRecords_thenEachGetsItsOwnRow() {
        let items = PIRNeedsYou.items(pending: [optOut(broker: 3, record: nil, url: "spyfly.com", name: "SpyFly"),
                                                optOut(broker: 3, record: 30, url: "spyfly.com", name: "SpyFly")], running: [])

        XCTAssertEqual(items.map(\.kind), [.scan, .optOut])
        XCTAssertEqual(items.map(\.recordCount), [0, 1])
        XCTAssertEqual(items.first?.id, "scan-3-1")
    }

    func testWhenOneOfARowsRecordsIsRunning_thenTheRowOpensThatRecord() {
        let running = PIRNeedsYou.RunningItem(id: PIRAssistItemID(brokerId: 1, profileQueryId: 1, extractedProfileId: 11),
                                              brokerName: "PeopleFinders", brokerURL: "peoplefinders.com", state: .needsYou)

        let items = PIRNeedsYou.items(pending: [optOut(broker: 1, record: 10), optOut(broker: 1, record: 11)], running: [running])

        XCTAssertEqual(items.first?.id, "optOut-1-1-11")
        XCTAssertEqual(items.first?.state, .needsYou)
    }

    func testWhenAJobThatIsNoLongerHeldNeedsTheUser_thenItIsListed() {
        let confirmation = PIRNeedsYou.RunningItem(id: PIRAssistItemID(brokerId: 2, profileQueryId: 1, extractedProfileId: 20),
                                                   brokerName: "Glad I Know", brokerURL: "https://www.gladiknow.com", state: .needsYou)
        let runningOnItsOwn = PIRNeedsYou.RunningItem(id: PIRAssistItemID(brokerId: 3, profileQueryId: 1, extractedProfileId: 30),
                                                      brokerName: "SpyFly", brokerURL: "spyfly.com", state: .running)

        let items = PIRNeedsYou.items(pending: [], running: [confirmation, runningOnItsOwn])

        XCTAssertEqual(items, [DBPUINeedsYouItem(id: "optOut-2-1-20", brokerName: "Glad I Know", brokerUrl: "gladiknow.com",
                                                 kind: .optOut, recordCount: 1, state: .needsYou)])
    }

    func testWhenNothingIsHeldOrWaiting_thenTheListIsEmpty() {
        XCTAssertEqual(PIRNeedsYou.items(pending: [], running: []), [])
    }

    func testNeedsYouIDsRoundTrip() {
        let optOut = PIRAssistItemID(brokerId: 4, profileQueryId: 5, extractedProfileId: 6)
        let scan = PIRAssistItemID(brokerId: 4, profileQueryId: 5, extractedProfileId: nil)

        XCTAssertEqual(PIRAssistItemID(needsYouID: optOut.needsYouID), optOut)
        XCTAssertEqual(PIRAssistItemID(needsYouID: scan.needsYouID), scan)
        XCTAssertNil(PIRAssistItemID(needsYouID: "optOut-4-5"))
        XCTAssertNil(PIRAssistItemID(needsYouID: "scan-4-x"))
        XCTAssertNil(PIRAssistItemID(needsYouID: "other-4-5"))
    }

    func testBrokerURLsBecomeBareDomains() {
        XCTAssertEqual(PIRNeedsYou.bareDomain("peoplefinders.com"), "peoplefinders.com")
        XCTAssertEqual(PIRNeedsYou.bareDomain("https://www.PeopleFinders.com/opt-out"), "peoplefinders.com")
    }

    func testNeedsYouListEncodesTheDashboardContract() throws {
        let list = DBPUINeedsYouList(items: [DBPUINeedsYouItem(id: "scan-3-1", brokerName: "SpyFly", brokerUrl: "spyfly.com",
                                                               kind: .scan, recordCount: 0, state: .running)])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any])
        let item = try XCTUnwrap((json["items"] as? [[String: Any]])?.first)

        XCTAssertEqual(item["id"] as? String, "scan-3-1")
        XCTAssertEqual(item["brokerUrl"] as? String, "spyfly.com")
        XCTAssertEqual(item["kind"] as? String, "scan")
        XCTAssertEqual(item["recordCount"] as? Int, 0)
        XCTAssertEqual(item["state"] as? String, "running")
    }
}

final class PIRAssistChecklistTests: XCTestCase {

    private let checklist = PIRAssistChecklist(isOptOut: true, items: ["Open the form", "Entering your name",
                                                                       PIRAssistChecklist.proveHumanLabel, "Submit request"],
                                               currentIndex: 1)

    func testWhileAutomationRuns_thenTheCurrentStepRunsAndTheChallengeIsFlaggedAhead() {
        XCTAssertEqual(checklist.steps(userTurn: nil).map(\.state), [.done, .running, .needsUserLater, .upcoming])
    }

    func testDuringTheUsersTurn_thenTheCurrentStepIsTheirs() {
        XCTAssertEqual(checklist.steps(userTurn: .turnstile).map(\.state), [.done, .userTurn, .needsUserLater, .upcoming])
    }
}

final class PIRAssistedOptOutsTests: XCTestCase {

    func testAStartLetsTheJobRunOnce() {
        XCTAssertFalse(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: 2))

        PIRAssistedOptOuts.markStarted(brokerId: 90, profileQueryId: 1, extractedProfileId: 2)

        XCTAssertFalse(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: nil))
        XCTAssertTrue(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: 2))
        XCTAssertFalse(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: 2))
    }
}
#endif
