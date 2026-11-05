//
//  UserAssistanceTests.swift
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
import PrivacyConfig
import XCTest
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class UserAssistanceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var settings: DataBrokerProtectionSettings!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "UserAssistanceTests-\(UUID().uuidString)")
        settings = DataBrokerProtectionSettings(defaults: defaults)
    }

    // MARK: - Config

    func testWhenSubfeatureIsEnabled_thenEnabledBrokersComeFromItsSettings() throws {
        let privacyConfig = try makePrivacyConfig()
        privacyConfig.isSubfeatureEnabledCheck = { ($0 as? DBPSubfeature) == .userAssistance }
        privacyConfig.subfeatureSettings = { _ in #"{ "enabledBrokers": ["beenverified.com"] }"# }

        let config = UserAssistanceConfig.current(privacyConfig: privacyConfig, settings: settings)

        XCTAssertTrue(config.isEnabled(forBrokerURL: "beenverified.com"))
        XCTAssertFalse(config.isEnabled(forBrokerURL: "spokeo.com"))
    }

    func testWhenSubfeatureIsDisabled_thenNoBrokerIsEnabled() throws {
        let privacyConfig = try makePrivacyConfig()
        privacyConfig.subfeatureSettings = { _ in #"{ "enabledBrokers": ["beenverified.com"] }"# }

        XCTAssertFalse(UserAssistanceConfig.current(privacyConfig: privacyConfig, settings: settings).isEnabled)
    }

    func testWhenDebugOverrideIsSet_thenItReplacesRemoteConfig() throws {
        let privacyConfig = try makePrivacyConfig()
        privacyConfig.isSubfeatureEnabledCheck = { _ in true }
        privacyConfig.subfeatureSettings = { _ in #"{ "enabledBrokers": ["beenverified.com"] }"# }

        settings.userAssistanceEnabledBrokersOverride = ["example.com"]
        XCTAssertEqual(UserAssistanceConfig.current(privacyConfig: privacyConfig, settings: settings).enabledBrokers, ["example.com"])

        settings.userAssistanceEnabledBrokersOverride = []
        XCTAssertFalse(UserAssistanceConfig.current(privacyConfig: privacyConfig, settings: settings).isEnabled)
    }

    // MARK: - Broker JSON

    func testWhenStepHasUserAssistAction_thenItDecodesWithItsOptions() throws {
        let actions = try Step.parse([
            ["actionType": "fillForm", "id": "1", "step": "Entering your name", "selector": "#form", "elements": []],
            ["actionType": "userAssist", "id": "2", "step": "Prove you’re human", "highlight": "#captcha", "handOffAfterMs": 10000,
             "completeWhen": [["type": "element", "selector": "//iframe[@data-hcaptcha-response != '']"]]]
        ])

        let userAssist = try XCTUnwrap(actions.last as? UserAssistAction)
        XCTAssertEqual(userAssist.highlight, "#captcha")
        XCTAssertEqual(userAssist.handOffAfterMs, 10000)
        XCTAssertEqual(userAssist.step, "Prove you’re human")
        XCTAssertEqual(actions.first?.step, "Entering your name")
    }

    func testWhenStepHasAnUnknownAction_thenParsingStillFails() {
        XCTAssertThrowsError(try Step.parse([["actionType": "somethingNew", "id": "1"]])) { error in
            XCTAssertEqual(error as? Step.DecodingError, .unsupportedActionType)
        }
    }

    func testWhenUserAssistCompletes_thenResponseDecodes() throws {
        let json = #"{ "result": { "success": { "actionID": "2", "actionType": "userAssist", "response": null } } }"#
        let result = try JSONDecoder().decode(CCFResult.self, from: Data(json.utf8))

        guard case .success(let success) = result.result else { return XCTFail("Expected success") }
        XCTAssertEqual(success.actionType, .userAssist)
        XCTAssertEqual(DataBrokerProtectionFeature.actionID(inCompletedParams: try JSONSerialization.jsonObject(with: Data(json.utf8))), "2")
    }

    func testTestBrokersUseUserAssistAndInstallAsActive() throws {
        let resources = try UserAssistanceTestBrokers.files.map(UserAssistanceTestBrokers.resource(from:))
        XCTAssertEqual(resources.map(\.broker.url), ["beenverified.com"])

        for broker in resources.map(\.broker) {
            let actions = try XCTUnwrap(broker.optOutStep()?.actions)
            XCTAssertNil(broker.removedAt)
            XCTAssertEqual(actions.filter { $0 is UserAssistAction }.count, 3)
            XCTAssertFalse(actions.contains { $0 is GetCaptchaInfoAction || $0 is SolveCaptchaAction })
            XCTAssertEqual(AssistedOptOutSteps(actions: actions).titles,
                           ["Entering your name", "Searching for your record", "Selecting your record", "Prove you’re human", "Review and submit"])
        }
    }

    // MARK: - Steps

    func testStepTitlesAreDistinctLabelsInOrderIncludingConditions() throws {
        let actions = try Step.parse([
            ["actionType": "navigate", "id": "1", "url": "https://example.com", "step": "A"],
            ["actionType": "click", "id": "2", "elements": []],
            ["actionType": "condition", "id": "3", "step": "B", "expectations": [],
             "actions": [["actionType": "click", "id": "4", "elements": [], "step": "C"]]],
            ["actionType": "click", "id": "5", "elements": [], "step": "A"],
            ["actionType": "click", "id": "6", "elements": [], "step": "D"]
        ])

        let steps = AssistedOptOutSteps(actions: actions)

        XCTAssertEqual(steps.titles, ["A", "B", "C", "D"])
        XCTAssertEqual(steps.index(of: actions[3]), 0)
        XCTAssertNil(steps.index(of: actions[1]))
    }

    // MARK: - Dashboard model

    func testStateMapping() {
        XCTAssertEqual(AssistedOptOut.State(phase: .queued, isWindowKey: true), .waiting)
        XCTAssertEqual(AssistedOptOut.State(phase: .agentInControl, isWindowKey: true), .agentInControl)
        XCTAssertEqual(AssistedOptOut.State(phase: .userTurn, isWindowKey: false), .needsUser)
        XCTAssertEqual(AssistedOptOut.State(phase: .userTurn, isWindowKey: true), .userInControl)
        XCTAssertEqual(AssistedOptOut.State(phase: .submitted, isWindowKey: false), .submitted)
    }

    func testAssistedOptOutEncodesToTheDashboardShape() throws {
        let item = AssistedOptOut(id: "1-2-3", dataBroker: .init(name: "BeenVerified", url: "beenverified.com"), recordCount: 2,
                                  state: .needsUser, step: .init(index: 1, count: 4, title: "Searching for your record"))

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AssistedOptOutList(optOuts: [item]))) as? [String: Any])
        let optOut = try XCTUnwrap((json["optOuts"] as? [[String: Any]])?.first)

        XCTAssertEqual(optOut["id"] as? String, "1-2-3")
        XCTAssertEqual(optOut["state"] as? String, "needsUser")
        XCTAssertEqual(optOut["recordCount"] as? Int, 2)
        XCTAssertEqual((optOut["dataBroker"] as? [String: String])?["url"], "beenverified.com")
        XCTAssertEqual((optOut["step"] as? [String: Any])?["index"] as? Int, 1)
        XCTAssertEqual((optOut["step"] as? [String: Any])?["title"] as? String, "Searching for your record")
    }

    func testAssistedOptOutIDRoundTrips() {
        let id = AssistedOptOutID(brokerId: 4, profileQueryId: 5, extractedProfileId: 6)
        XCTAssertEqual(AssistedOptOutID(id.description), id)
        XCTAssertNil(AssistedOptOutID("4-5"))
    }

    @MainActor
    func testSessionFollowsActionsAndUserTurns() throws {
        let actions = try Step.parse([
            ["actionType": "fillForm", "id": "1", "step": "Name", "selector": "#f", "elements": []],
            ["actionType": "userAssist", "id": "2", "step": "Captcha", "completeWhen": [["type": "element", "selector": "#ok"]]],
            ["actionType": "click", "id": "3", "elements": []]
        ])
        var userTurns = 0
        let session = AssistedOptOutSession(id: .init(brokerId: 1, profileQueryId: 1, extractedProfileId: 1),
                                            broker: .init(name: "Broker", url: "broker.com"), recordCount: 1,
                                            steps: AssistedOptOutSteps(actions: actions))
        session.onUserTurnStarted = { _ in userTurns += 1 }
        XCTAssertEqual(session.dashboardItem.state, .waiting)

        session.attemptWillRun(actions[1])
        XCTAssertEqual(session.dashboardItem.state, .agentInControl)
        XCTAssertEqual(session.dashboardItem.step, .init(index: 1, count: 2, title: "Captcha"))

        session.attemptNeedsUser(actionID: "2")
        session.attemptNeedsUser(actionID: "2")
        XCTAssertEqual(userTurns, 1)
        XCTAssertEqual(session.dashboardItem.state, .needsUser)
        session.isWindowKey = true
        XCTAssertEqual(session.dashboardItem.state, .userInControl)

        session.attemptWillRun(actions[2])
        XCTAssertEqual(session.dashboardItem.state, .agentInControl)
        XCTAssertEqual(session.currentStepIndex, 1)

        session.markSubmitted()
        XCTAssertEqual(session.dashboardItem.state, .submitted)
        XCTAssertNil(session.dashboardItem.step)
    }

    // MARK: - Scheduling

    func testOptOutAwaitingUserAssistanceKeepsItsPreferredRunDate() throws {
        let preferredRunDate = Date().addingTimeInterval(-3600)
        let events = [HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, type: .optOutStarted),
                      HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, type: .optOutAwaitingUserAssistance)]

        let date = try OperationPreferredDateCalculator().dateForOptOutOperation(currentPreferredRunDate: preferredRunDate,
                                                                                 optOutHistoryEvents: events,
                                                                                 extractedProfileID: 1,
                                                                                 schedulingConfig: .mock,
                                                                                 attemptCount: 0)

        XCTAssertEqual(date, preferredRunDate)
    }

    func testOptOutAwaitingUserAssistanceEndsAnAttemptCleanly() {
        let start = Date().addingTimeInterval(-2 * 24 * 3600)
        let events = [HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutStarted, date: start),
                      HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutAwaitingUserAssistance, date: start.addingTimeInterval(600))]
        let data = [BrokerProfileQueryData.mock(optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate, historyEvents: events)])]

        let result = StalledOperationCalculator.optOut.calculate(from: data)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.stalled, 0)
    }

    func testWhenAssistedAttemptEnds_thenItWaitsForTheUserWithoutAnError() throws {
        let database = MockDatabase()
        let dependencies = MockBrokerProfileJobDependencies()
        dependencies.database = database
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.0",
                                                                     handler: MockDataBrokerProtectionPixelsHandler(), isFreeScan: false,
                                                                     vpnConnectionState: "", vpnBypassStatus: "")

        BrokerProfileOptOutSubJob(dependencies: dependencies)
            .recordAssistedOptOutEnd(error: DataBrokerProtectionError.cancelled,
                                     brokerProfileQueryData: .mock(),
                                     database: database,
                                     schedulingConfig: .mock,
                                     featureFlagger: MockDBPFeatureFlagger(),
                                     identifiers: .init(brokerId: 1, profileQueryId: 1, extractedProfileId: 1),
                                     stageDurationCalculator: calculator)

        XCTAssertEqual(database.optOutEvents.map(\.type), [.optOutAwaitingUserAssistance])
    }

    // MARK: - Queues

    func testWhenBrokerIsEnabled_thenRegularQueueSkipsItsOptOutsButStillScans() async {
        let (dependencies, database) = makeDependencies(optOutEvents: [])
        settings.userAssistanceEnabledBrokersOverride = ["broker.com"]

        await runRegularJob(dependencies)

        XCTAssertFalse(dependencies.mockOptOutRunner.wasOptOutCalled)
        XCTAssertTrue(database.scanEvents.contains { $0.type == .scanStarted })
        XCTAssertFalse(database.optOutEvents.contains { $0.type == .optOutStarted })
    }

    func testWhenFlagTurnsOff_thenWaitingOptOutsReturnToTheRegularQueue() async {
        let (dependencies, _) = makeDependencies(optOutEvents: [.optOutAwaitingUserAssistance])
        settings.userAssistanceEnabledBrokersOverride = []

        await runRegularJob(dependencies)

        XCTAssertTrue(dependencies.mockOptOutRunner.wasOptOutCalled)
    }

    @MainActor
    func testNeedsYouListsWaitingOptOutsOnlyWhileEnabled() {
        let (dependencies, _) = makeDependencies(optOutEvents: [.optOutAwaitingUserAssistance])
        let queue = AssistedOptOutQueue(dependencies: dependencies)

        settings.userAssistanceEnabledBrokersOverride = ["broker.com"]
        XCTAssertEqual(queue.assistedOptOuts(), [AssistedOptOut(id: "1-1-1", dataBroker: .init(name: "Broker", url: "broker.com"), state: .waiting)])

        settings.userAssistanceEnabledBrokersOverride = nil
        XCTAssertEqual(queue.assistedOptOuts(), [])
    }

    @MainActor
    func testRefreshMarksDueOptOutsAsWaitingOnce() {
        settings.userAssistanceEnabledBrokersOverride = ["broker.com"]

        let (due, dueDatabase) = makeDependencies(optOutEvents: [.optOutRequested])
        AssistedOptOutQueue(dependencies: due).refresh()
        XCTAssertEqual(dueDatabase.optOutEvents.map(\.type), [.optOutAwaitingUserAssistance])

        let (waiting, waitingDatabase) = makeDependencies(optOutEvents: [.optOutAwaitingUserAssistance])
        AssistedOptOutQueue(dependencies: waiting).refresh()
        XCTAssertTrue(waitingDatabase.optOutEvents.isEmpty)

        let (interrupted, interruptedDatabase) = makeDependencies(optOutEvents: [.optOutStarted], preferredRunDate: .distantFuture)
        AssistedOptOutQueue(dependencies: interrupted).refresh()
        XCTAssertEqual(interruptedDatabase.optOutEvents.map(\.type), [.optOutAwaitingUserAssistance])
    }

    // MARK: - Helpers

    private func makePrivacyConfig() throws -> PrivacyConfigurationMock {
        try XCTUnwrap(PrivacyConfigurationManagingMock().privacyConfig as? PrivacyConfigurationMock)
    }

    private func makeDependencies(optOutEvents: [HistoryEvent.EventType],
                                  preferredRunDate: Date = Date().addingTimeInterval(-3600)) -> (MockBrokerProfileJobDependencies, MockDatabase) {
        let database = MockDatabase()
        let dependencies = MockBrokerProfileJobDependencies()
        dependencies.database = database
        dependencies.dataBrokerProtectionSettings = settings

        let broker = DataBroker(id: 1, name: "Broker", url: "broker.com", steps: [], version: "1.0",
                                schedulingConfig: .mock, optOutUrl: "", eTag: "", removedAt: nil)
        let events = optOutEvents.enumerated().map { index, type in
            HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, type: type, date: Date().addingTimeInterval(Double(index - 10)))
        }
        let optOut = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: Date(), preferredRunDate: preferredRunDate,
                                   historyEvents: events, attemptCount: 0, extractedProfile: ExtractedProfile(id: 1, name: "Name", profileUrl: "abc"))
        database.brokerProfileQueryDataToReturn = [
            BrokerProfileQueryData(dataBroker: broker,
                                   profileQuery: ProfileQuery(id: 1, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1980),
                                   scanJobData: ScanJobData(brokerId: 1, profileQueryId: 1, preferredRunDate: Date(), historyEvents: []),
                                   optOutJobData: [optOut])
        ]
        return (dependencies, database)
    }

    private func runRegularJob(_ dependencies: MockBrokerProfileJobDependencies) async {
        let delegate = MockBrokerProfileJobStatusReportingDelegate()
        let job = BrokerProfileJob(dataBrokerID: 1, jobType: .all, showWebView: false,
                                   statusReportingDelegate: delegate, jobDependencies: dependencies)
        let finished = XCTestExpectation(description: "Job finished")
        job.completionBlock = { finished.fulfill() }
        job.start()
        await fulfillment(of: [finished], timeout: 15)
    }
}
