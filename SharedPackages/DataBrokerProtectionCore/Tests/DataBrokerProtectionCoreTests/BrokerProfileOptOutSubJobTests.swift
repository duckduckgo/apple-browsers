//
//  BrokerProfileOptOutSubJobTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Common
import PixelKit
import PixelKitTestingUtilities
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class BrokerProfileOptOutSubJobTests: XCTestCase {
    var sut: BrokerProfileOptOutSubJob!

    var mockScanRunner: MockScanSubJobWebRunner!
    var mockOptOutRunner: MockOptOutSubJobWebRunner!
    var mockDatabase: MockDatabase!
    var mockEventsHandler: MockOperationEventsHandler!
    var mockPixelHandler: MockPixelHandler!
    var mockDependencies: MockBrokerProfileJobDependencies!

    override func setUp() {
        super.setUp()
        mockScanRunner = MockScanSubJobWebRunner()
        mockOptOutRunner = MockOptOutSubJobWebRunner()
        mockDatabase = MockDatabase()
        mockEventsHandler = MockOperationEventsHandler()
        mockPixelHandler = MockPixelHandler()

        mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.mockScanRunner = self.mockScanRunner
        mockDependencies.mockOptOutRunner = self.mockOptOutRunner
        mockDependencies.database = self.mockDatabase
        mockDependencies.eventsHandler = self.mockEventsHandler
        mockDependencies.pixelHandler = self.mockPixelHandler

        sut = BrokerProfileOptOutSubJob(dependencies: mockDependencies)
    }

    private func makeFixtureIdentifiers() -> BrokerProfileOptOutSubJob.OptOutIdentifiers {
        .init(brokerId: 1, profileQueryId: 1, extractedProfileId: 1)
    }

    private func makeFixtureBrokerProfileQueryData(broker: DataBroker = .mock,
                                                   profileQuery: ProfileQuery = .mock,
                                                   scanHistoryEvents: [HistoryEvent] = [],
                                                   optOutJobHistoryEvents: [HistoryEvent] = [],
                                                   extractedProfile: ExtractedProfile = .mockWithoutRemovedDate) -> BrokerProfileQueryData {
        BrokerProfileQueryData(
            dataBroker: broker,
            profileQuery: profileQuery,
            scanJobData: .init(
                brokerId: broker.id ?? 1,
                profileQueryId: profileQuery.id ?? 1,
                historyEvents: scanHistoryEvents
            ),
            optOutJobData: [
                OptOutJobData(
                    brokerId: broker.id ?? 1,
                    profileQueryId: profileQuery.id ?? 1,
                    createdDate: Date(),
                    preferredRunDate: nil,
                    historyEvents: optOutJobHistoryEvents,
                    attemptCount: 0,
                    extractedProfile: extractedProfile
                )
            ]
        )
    }

    // MARK: - validateOptOutPreconditions

    func testValidateOptOutPreconditions_whenIdsMissing_throws() {
        let extractedProfile = ExtractedProfile(id: nil)
        let broker = DataBroker(name: "broker",
                                url: "broker.com",
                                steps: [],
                                version: "1",
                                schedulingConfig: .default,
                                optOutUrl: "",
                                eTag: "",
                                removedAt: nil)
        let profile = ProfileQuery(firstName: "John", lastName: "Doe", city: "City", state: "State", birthYear: 1990)
        let brokerData = BrokerProfileQueryData(dataBroker: broker,
                                                profileQuery: profile,
                                                scanJobData: .mock)

        XCTAssertThrowsError(
            try sut.validateOptOutPreconditions(for: extractedProfile,
                                                brokerProfileQueryData: brokerData,
                                                database: mockDatabase)
        ) { error in
            XCTAssertEqual(error as? BrokerProfileSubJobError, .idsMissingForBrokerOrProfileQuery)
        }
    }

    func testValidateOptOutPreconditions_whenProfileRemoved_returnsNil() throws {
        let identifiers = try sut.validateOptOutPreconditions(
            for: .mockWithRemovedDate,
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase
        )

        XCTAssertNil(identifiers)
    }

    func testValidateOptOutPreconditions_whenBrokerPerformsParentOptOut_returnsNil() throws {
        let broker = DataBroker.mockWithParentOptOut
        let identifiers = try sut.validateOptOutPreconditions(
            for: .mockWithoutRemovedDate,
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(broker: broker),
            database: mockDatabase
        )

        XCTAssertNil(identifiers)
    }

    func testValidateOptOutPreconditions_whenUserRemovedHistory_returnsNil() throws {
        try mockDatabase.add(HistoryEvent(extractedProfileId: 1,
                                          brokerId: 1,
                                          profileQueryId: 1,
                                          type: .matchRemovedByUser))

        let identifiers = try sut.validateOptOutPreconditions(
            for: .mockWithoutRemovedDate,
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase
        )

        XCTAssertNil(identifiers)
    }

    func testValidateOptOutPreconditions_whenAllChecksPass_returnsIdentifiers() throws {
        let result = try sut.validateOptOutPreconditions(
            for: .mockWithoutRemovedDate,
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase
        )

        XCTAssertEqual(result?.brokerId, 1)
        XCTAssertEqual(result?.profileQueryId, 1)
        XCTAssertEqual(result?.extractedProfileId, 1)
    }

    // MARK: - createStageDurationContext

    func testCreateStageDurationContext_whenWideEventAvailable_attachesRecorderAndFiresStart() {
        let wideEvent = WideEventMock()
        let pixelHandler = MockPixelHandler()

        let brokerData = makeFixtureBrokerProfileQueryData()
        let identifiers = makeFixtureIdentifiers()

        let context = sut.createStageDurationContext(
            for: brokerData,
            identifiers: identifiers,
            database: mockDatabase,
            wideEvent: wideEvent,
            pixelHandler: pixelHandler,
            vpnConnectionState: "connected",
            vpnBypassStatus: "enabled"
        )

        XCTAssertEqual(wideEvent.started.count, 1)
        let recorder = context.wideEventRecorder as? OptOutSubmissionWideEventRecorder
        XCTAssertNotNil(recorder)
        let calculatorRecorder = context.stageDurationCalculator.wideEventRecorder as? OptOutSubmissionWideEventRecorder
        XCTAssertTrue(recorder === calculatorRecorder)
        if let data = wideEvent.started.last as? OptOutSubmissionWideEventData {
            XCTAssertEqual(data.globalData.id, context.stageDurationCalculator.attemptId.uuidString)
        } else {
            XCTFail("Expected OptOutSubmissionWideEventData")
        }
        if case .optOutStart = pixelHandler.lastFiredEvent {
            // expected
        } else {
            XCTFail("Expected opt-out start pixel")
        }
    }

    // MARK: - markOptOutStarted

    func testMarkOptOutStarted_persistsHistoryEvent() throws {
        try sut.markOptOutStarted(identifiers: makeFixtureIdentifiers(), database: mockDatabase)

        XCTAssertTrue(mockDatabase.optOutEvents.contains { $0.type == .optOutStarted })
    }

    func testMarkOptOutStarted_whenHistoryWriteFails_rethrows() {
        mockDatabase.addHistoryEventError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(
            try sut.markOptOutStarted(identifiers: makeFixtureIdentifiers(), database: mockDatabase)
        ) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - makeOptOutRunner

    func testMakeOptOutRunner_usesFactory() {
        var capturedBrokerData: BrokerProfileQueryData?
        var capturedCalculator: StageDurationCalculator?
        var capturedShouldRun: (() -> Bool)?

        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: MockPixelHandler(),
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")

        let runner = sut.makeOptOutRunner(
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            stageDurationCalculator: calculator,
            shouldRunNextStep: { true },
            runnerFactory: { profile, calc, should in
                capturedBrokerData = profile
                capturedCalculator = calc
                capturedShouldRun = should
                return MockOptOutSubJobWebRunner()
            }
        )

        XCTAssertNotNil(runner)
        XCTAssertEqual(capturedBrokerData?.dataBroker.name, "Test broker")
        XCTAssertTrue((capturedCalculator as AnyObject) === (calculator as AnyObject))
        XCTAssertNotNil(capturedShouldRun)
    }

    // MARK: - executeOptOut

    func testExecuteOptOut_invokesRunner() async throws {
        let runner = MockOptOutSubJobWebRunner()

        try await sut.executeOptOut(
            on: runner,
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            extractedProfile: .mockWithoutRemovedDate,
            showWebView: true,
            shouldRunNextStep: { true }
        )

        XCTAssertTrue(runner.wasOptOutCalled)
    }

    func testExecuteOptOut_whenRunnerThrows_rethrows() async {
        let runner = MockOptOutSubJobWebRunner()
        runner.shouldOptOutThrow = { _ in true }

        do {
            try await sut.executeOptOut(
                on: runner,
                brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
                extractedProfile: .mockWithoutRemovedDate,
                showWebView: true,
                shouldRunNextStep: { true }
            )
            XCTFail("Expected runner opt-out to throw")
        } catch {
            XCTAssertTrue(runner.wasOptOutCalled)
        }
    }

    // MARK: - handleEmailConfirmationDecoupling

    func testHandleEmailConfirmationDecoupling_recordsAwaitingEmailConfirmation() throws {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        calculator.setLastActionId("action")
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()

        try sut.handleEmailConfirmationDecoupling(
            database: mockDatabase,
            pixelHandler: mockPixelHandler,
            brokerProfileQueryData: brokerData,
            identifiers: identifiers,
            stageDurationCalculator: calculator
        )

        XCTAssertTrue(mockDatabase.optOutEvents.contains { $0.type == .optOutSubmittedAndAwaitingEmailConfirmation })
        if case let .optOutStageSubmitAwaitingEmailConfirmation(_, _, attemptId, actionId, duration, tries) = mockPixelHandler.lastFiredEvent {
            XCTAssertEqual(attemptId, calculator.attemptId)
            XCTAssertEqual(actionId, "action")
            XCTAssertGreaterThanOrEqual(duration, 0)
            XCTAssertEqual(tries, calculator.tries)
        } else {
            XCTFail("Expected awaiting email confirmation pixel")
        }
        XCTAssertEqual(calculator.stage, .emailConfirmHalted)
    }

    // MARK: - finalizeOptOut

    func testFinalizeOptOut_updatesRepositoryAndPixels() throws {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let database = MockDatabase()
        try database.add(HistoryEvent(extractedProfileId: identifiers.extractedProfileId,
                                      brokerId: identifiers.brokerId,
                                      profileQueryId: identifiers.profileQueryId,
                                      type: .optOutStarted))
        try database.add(HistoryEvent(extractedProfileId: identifiers.extractedProfileId,
                                      brokerId: identifiers.brokerId,
                                      profileQueryId: identifiers.profileQueryId,
                                      type: .optOutRequested))

        try sut.finalizeOptOut(
            database: database,
            brokerProfileQueryData: brokerData,
            identifiers: identifiers,
            stageDurationCalculator: calculator
        )

        XCTAssertTrue(database.optOutEvents.contains { $0.type == .optOutRequested })
        XCTAssertEqual(database.attemptCount, 1)
        if case let .optOutSubmitSuccess(_, _, _, tries, _, _, _) = mockPixelHandler.lastFiredEvent {
            XCTAssertEqual(tries, 1)
        } else {
            XCTFail("Expected opt-out submit success pixel")
        }
    }

    func testFinalizeOptOut_whenHistoryWriteFails_rethrows() {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let failingDatabase = MockDatabase()
        failingDatabase.incrementAttemptShouldThrow = true

        XCTAssertThrowsError(
            try sut.finalizeOptOut(
                database: failingDatabase,
                brokerProfileQueryData: brokerData,
                identifiers: identifiers,
                stageDurationCalculator: calculator
            )
        ) { error in
            XCTAssertTrue(error is MockDatabase.MockError)
        }
    }

    func testHandleEmailConfirmationDecoupling_whenHistoryWriteFails_rethrows() {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        mockDatabase.addHistoryEventError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(
            try sut.handleEmailConfirmationDecoupling(
                database: mockDatabase,
                pixelHandler: mockPixelHandler,
                brokerProfileQueryData: brokerData,
                identifiers: identifiers,
                stageDurationCalculator: calculator
            )
        ) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - recordOptOutFailure

    func testRecordOptOutFailure_whenTimeout_emitsCancelledWideEvent() {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        let wideEvent = WideEventMock()
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEvent,
                                                                        attemptID: calculator.attemptId,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: Date())
        let completionExpectation = expectation(description: "wide event cancelled")
        completionExpectation.assertForOverFulfill = false
        wideEvent.onComplete = { (_: WideEventData, status: WideEventStatus) in
            if status == .cancelled {
                completionExpectation.fulfill()
            }
        }

        sut.recordOptOutFailure(
            error: TimeoutError(),
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase,
            wideEvent: wideEvent,
            wideEventRecorder: recorder,
            schedulingConfig: .default,
            identifiers: identifiers,
            stageDurationCalculator: calculator
        )

        wait(for: [completionExpectation], timeout: 1)
        XCTAssertEqual(wideEvent.completions.first?.1, .cancelled)
        if case .optOutFailure = mockPixelHandler.lastFiredEvent {
            // expected
        } else {
            XCTFail("Expected opt-out failure pixel")
        }
    }

    func testRecordOptOutFailure_whenJobTimeout_emitsCancelledWideEvent() {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        let wideEvent = WideEventMock()
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEvent,
                                                                        attemptID: calculator.attemptId,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: Date())
        let completionExpectation = expectation(description: "wide event cancelled job timeout")
        completionExpectation.assertForOverFulfill = false
        wideEvent.onComplete = { (_: WideEventData, status: WideEventStatus) in
            if status == .cancelled {
                completionExpectation.fulfill()
            }
        }

        sut.recordOptOutFailure(
            error: DataBrokerProtectionError.jobTimeout,
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase,
            wideEvent: wideEvent,
            wideEventRecorder: recorder,
            schedulingConfig: .default,
            identifiers: identifiers,
            stageDurationCalculator: calculator
        )

        wait(for: [completionExpectation], timeout: 1)
        XCTAssertEqual(wideEvent.completions.first?.1, .cancelled)
        if case .optOutFailure = mockPixelHandler.lastFiredEvent {
            // expected
        } else {
            XCTFail("Expected opt-out failure pixel")
        }
    }

    func testRecordOptOutFailure_whenGenericError_emitsFailureAndRecordsEvent() {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        let wideEvent = WideEventMock()
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEvent,
                                                                        attemptID: calculator.attemptId,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: Date())
        mockDependencies.wideEvent = wideEvent
        let completionExpectation = expectation(description: "wide event failure")
        completionExpectation.assertForOverFulfill = false
        wideEvent.onComplete = { (_: WideEventData, status: WideEventStatus) in
            if status == .failure {
                completionExpectation.fulfill()
            }
        }

        sut.recordOptOutFailure(
            error: DataBrokerProtectionError.actionFailed(actionID: "action", message: "msg"),
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase,
            wideEvent: wideEvent,
            wideEventRecorder: recorder,
            schedulingConfig: .default,
            identifiers: identifiers,
            stageDurationCalculator: calculator
        )

        wait(for: [completionExpectation], timeout: 1)
        XCTAssertEqual(wideEvent.completions.first?.1, .failure)
        XCTAssertTrue(mockDatabase.optOutEvents.contains { $0.isError })
        if case .optOutFailure = mockPixelHandler.lastFiredEvent {
            // expected
        } else {
            XCTFail("Expected opt-out failure pixel")
        }
    }

    func testRecordOptOutFailure_whenHistoryWriteFails_stillEmitsPixels() {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        let wideEvent = WideEventMock()
        let recorder = OptOutSubmissionWideEventRecorder.makeIfPossible(wideEvent: wideEvent,
                                                                        attemptID: calculator.attemptId,
                                                                        dataBrokerURL: "broker.com",
                                                                        dataBrokerVersion: "1.0",
                                                                        recordFoundDate: Date())
        mockDependencies.wideEvent = wideEvent
        mockDatabase.saveResult = .failure(MockDatabase.MockError.saveFailed)

        sut.recordOptOutFailure(
            error: DataBrokerProtectionError.actionFailed(actionID: "action", message: "msg"),
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase,
            wideEvent: wideEvent,
            wideEventRecorder: recorder,
            schedulingConfig: .default,
            identifiers: identifiers,
            stageDurationCalculator: calculator
        )

        XCTAssertEqual(wideEvent.completions.first?.1, .failure)
        if case .optOutFailure = mockPixelHandler.lastFiredEvent {
            // expected even when history write fails
        } else {
            XCTFail("Expected opt-out failure pixel")
        }
    }

    func testRecordOptOutFailure_whenIncrementAttemptCountFails_stillHandlesFailure() {
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status")
        let identifiers = makeFixtureIdentifiers()
        mockDatabase.incrementAttemptShouldThrow = true

        sut.recordOptOutFailure(
            error: DataBrokerProtectionError.unknown("failure"),
            brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
            database: mockDatabase,
            wideEvent: nil,
            wideEventRecorder: nil,
            schedulingConfig: .default,
            identifiers: identifiers,
            stageDurationCalculator: calculator
        )

        XCTAssertEqual(mockDatabase.attemptCount, 0)
        if case .optOutFailure = mockPixelHandler.lastFiredEvent {
            // expected
        } else {
            XCTFail("Expected opt-out failure pixel to fire")
        }
    }

    func testWhenNoBrokerIdIsPresent_thenOptOutOperationThrows() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mockWithoutId,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        }
    }

    func testWhenNoProfileQueryIdIsPresent_thenOptOutOperationThrows() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mockWithoutId,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        }
    }

    func testWhenNoExtractedProfileIdIsPresent_thenOptOutOperationThrows() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutId,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutId)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        }
    }

    func testWhenExtractedProfileHasRemovedDate_thenNothingHappens() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.wasDatabaseCalled)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenBrokerHasParentOptOut_thenNothingHappens() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mockWithParentOptOut,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.wasDatabaseCalled)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testOptOutStartedEventIsAdded_whenExtractedProfileOptOutStarts() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutStarted }))
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testOptOutRequestedEventIsAdded_whenExtractedProfileOptOutFinishesWithoutError() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutRequested }))
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testErrorEventIsAdded_whenWebRunnerFails() async {
        do {
            mockOptOutRunner.shouldOptOutThrow = { _ in true }
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Should throw!")
        } catch {
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutStarted }))
            XCTAssertFalse(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutRequested }))
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .error(error: DataBrokerProtectionError.unknown("Test error")) }))
        }
    }

    private func runOptOut(shouldThrow: Bool = false) async throws {
        mockOptOutRunner.shouldOptOutThrow = { _ in shouldThrow }
        _ = try await sut.runOptOut(
            for: .mockWithoutRemovedDate,
            brokerProfileQueryData: .init(
                dataBroker: .mock,
                profileQuery: .mock,
                scanJobData: .mock,
                optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
            ),
            showWebView: false,
            shouldRunNextStep: { true }
        )
    }

    func testCorrectNumberOfTriesIsFired_whenOptOutSucceeds() async {
        try? await runOptOut(shouldThrow: true)
        try? await runOptOut(shouldThrow: true)
        try? await runOptOut()

        if let lastPixelFired = mockPixelHandler.lastFiredEvent {
            switch lastPixelFired {
            case .optOutSubmitSuccess(_, _, _, let tries, _, _, _):
                XCTAssertEqual(tries, 3)
            default: XCTFail("We should be firing the opt-out submit-success pixel last")
            }
        } else {
            XCTFail("We should be firing the opt-out submit-success pixel")
        }
    }

    func testCorrectNumberOfTriesIsFired_whenOptOutFails() async {
        do {
            try? await runOptOut(shouldThrow: true)
            try? await runOptOut(shouldThrow: true)
            try await runOptOut(shouldThrow: true)
            XCTFail("The code above should throw")
        } catch {
            if let lastPixelFired = mockPixelHandler.lastFiredEvent {
                switch lastPixelFired {
                case .optOutFailure(_, _, _, _, _, let tries, _, _, _, _):
                    XCTAssertEqual(tries, 3)
                default: XCTFail("We should be firing the opt-out submit-success pixel last")
                }
            } else {
                XCTFail("We should be firing the opt-out submit-success pixel")
            }
        }
    }

    func testAttemptCountNotIncreased_whenOptOutFails() async {
        do {
            try await runOptOut(shouldThrow: true)
            XCTFail("The code above should throw")
        } catch {
            XCTAssertEqual(mockDatabase.attemptCount, 0)
        }
    }

    func testAttemptCountIncreased_whenOptOutSucceeds() async {
        do {
            try await runOptOut()
            XCTAssertEqual(mockDatabase.attemptCount, 1)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testAttemptCountIncreasedWithEachSuccessfulOptOut() async {
        do {
            for attempt in 0..<10 {
                try await runOptOut()
                XCTAssertEqual(mockDatabase.attemptCount, Int64(attempt) + 1)
                try? await runOptOut(shouldThrow: true)
                XCTAssertEqual(mockDatabase.attemptCount, Int64(attempt) + 1)
            }
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testUpdatingScanDateFromOptOut_thenScanRespectMostRecentDate() throws {
        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()

        let mockDataBroker = DataBroker(
            name: "databroker",
            url: "databroker.com",
            steps: [Step](),
            version: "1.0",
            schedulingConfig: config,
            optOutUrl: "",
            eTag: "",
            removedAt: nil
        )

        let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

        let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
        let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

        let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker, profileQuery: mockProfileQuery, scanJobData: mockScanOperation)
        mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

        try sut.updateOperationDataDates(origin: .optOut, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: config, database: mockDatabase)

        // If the date is not going to be set, we don't call the database function
        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(config.hoursUntilNextOptOutAttempt.hoursToSeconds)))
    }

    func testOptOutSubJob_whenExecutedSuccessfully_returnsTrue() async throws {
        // When
        let result = try await sut.runOptOut(
            for: .mockWithoutRemovedDate,
            brokerProfileQueryData: .init(
                dataBroker: .mock,
                profileQuery: .mock,
                scanJobData: .mock,
                optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
            ),
            showWebView: false,
            shouldRunNextStep: { true }
        )

        // Then
        XCTAssertTrue(result)
    }

    func testOptOutSubJob_whenProfileAlreadyRemoved_returnsFalse() async throws {
        // Given
        let removedProfile = ExtractedProfile(id: 1, name: "Test", profileUrl: "test.com", removedDate: Date())

        // When
        let result = try await sut.runOptOut(
            for: removedProfile,
            brokerProfileQueryData: .init(
                dataBroker: .mock,
                profileQuery: .mock,
                scanJobData: .mock,
                optOutJobData: [OptOutJobData.mock(with: removedProfile)]
            ),
            showWebView: false,
            shouldRunNextStep: { true }
        )

        // Then
        XCTAssertFalse(result)
    }
}
